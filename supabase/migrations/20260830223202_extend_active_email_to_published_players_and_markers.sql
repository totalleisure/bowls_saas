-- Extend Active Email responses to ordinary published players and named
-- Pre-Select markers. Outbound and inbound transport remain unchanged.

alter table public.email_action_requests
  drop constraint email_action_requests_action_type_check;

alter table public.email_action_requests
  add constraint email_action_requests_action_type_check
  check (action_type in ('team_selection', 'marker_assignment'));

CREATE OR REPLACE FUNCTION public.prepare_team_selection_email_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_request_id uuid;
  v_code text;
  v_code_hash text;
  v_team_selection_id uuid;
  v_team_selection_member_id uuid;
  v_club_id uuid;
  v_expires_at timestamptz;
  v_action_type text;
  v_heading text;
  v_accept_label text;
  v_decline_label text;
begin
  if new.event_type not in ('fixture_selected', 'team_published_player')
     or new.member_profile_id is null
     or new.fixture_id is null then
    return new;
  end if;

  select
    ts.id,
    tsm.id,
    f.club_id,
    f.start_at,
    case
      when new.event_type = 'fixture_selected'
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ) then 'marker_assignment'
      when tsm.role::text = 'player' then 'team_selection'
      else null
    end
  into
    v_team_selection_id,
    v_team_selection_member_id,
    v_club_id,
    v_expires_at,
    v_action_type
  from public.team_selections ts
  join public.team_selection_members tsm
    on tsm.team_selection_id = ts.id
   and tsm.member_profile_id = new.member_profile_id
  join public.fixtures f
    on f.id = ts.fixture_id
  where ts.fixture_id = new.fixture_id
    and (new.team_selection_id is null or ts.id = new.team_selection_id)
    and ts.status = 'published'
    and coalesce(tsm.is_selected, false) = true
    and (
      (new.event_type in ('fixture_selected', 'team_published_player')
       and tsm.role::text = 'player')
      or
      (new.event_type = 'fixture_selected'
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ))
    )
    and f.cancelled_at is null
  limit 1;

  if v_team_selection_member_id is null or v_action_type is null then
    return new;
  end if;

  update public.email_action_requests
     set status = 'cancelled',
         updated_at = now()
   where action_type = v_action_type
     and target_record_id = v_team_selection_member_id
     and status in ('pending', 'responded');

  if v_action_type = 'marker_assignment' then
    v_heading := 'Please respond to your marker assignment';
    v_accept_label := 'Accept marker assignment';
    v_decline_label := 'Decline marker assignment';
  else
    v_heading := 'Please respond to your selection';
    v_accept_label := 'Accept selection';
    v_decline_label := 'Decline selection';
  end if;

  v_code := 'BWL-' || upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_code_hash := encode(
    extensions.digest(upper(v_code), 'sha256'),
    'hex'
  );

  insert into public.email_action_requests (
    club_id,
    member_profile_id,
    recipient_email,
    action_type,
    target_record_id,
    fixture_id,
    team_selection_id,
    source_email_queue_id,
    allowed_actions,
    response_code_hash,
    expires_at
  )
  values (
    v_club_id,
    new.member_profile_id,
    new.recipient_email,
    v_action_type,
    v_team_selection_member_id,
    new.fixture_id,
    v_team_selection_id,
    new.id,
    array['ACCEPT','DECLINE'],
    v_code_hash,
    v_expires_at
  )
  returning id into v_request_id;

  update public.email_queue
     set payload = coalesce(payload, '{}'::jsonb) ||
       jsonb_build_object(
         'action_block',
         jsonb_build_object(
           'version', 1,
           'request_id', v_request_id,
           'action_type', v_action_type,
           'heading', v_heading,
           'instructions',
             'Select Accept or Decline. Your email application will open a prepared reply; send it without changing the response code.',
           'response_code', v_code,
           'expires_at', v_expires_at,
           'actions', jsonb_build_array(
             jsonb_build_object(
               'command', 'ACCEPT',
               'label', v_accept_label,
               'style', 'positive'
             ),
             jsonb_build_object(
               'command', 'DECLINE',
               'label', v_decline_label,
               'style', 'negative'
             )
           )
         )
       )
   where id = new.id;

  return new;
end;
$function$;

comment on function public.prepare_team_selection_email_action() is
  'Adds modular Accept/Decline action blocks to active published-player and named-marker selection emails.';

grant execute
on function public.prepare_team_selection_email_action()
to public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.apply_email_action_response(p_response_code text, p_command text, p_sender_email text, p_graph_message_id text, p_received_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_request public.email_action_requests%rowtype;
  v_command text := upper(btrim(coalesce(p_command, '')));
  v_sender text := lower(btrim(coalesce(p_sender_email, '')));
  v_code_hash text;
  v_acceptance public.acceptance_status;
  v_target_valid boolean := false;
  v_result_detail text;
begin
  if nullif(btrim(coalesce(p_graph_message_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'status', 'invalid_message_id');
  end if;

  if exists (
    select 1
    from public.email_action_response_log
    where graph_message_id = p_graph_message_id
  ) then
    return jsonb_build_object('ok', true, 'status', 'duplicate');
  end if;

  if nullif(btrim(coalesce(p_response_code, '')), '') is null then
    insert into public.email_action_response_log(
      graph_message_id, sender_email, command, result_status,
      result_detail, received_at
    ) values (
      p_graph_message_id, v_sender, v_command, 'invalid_code',
      'Response code was empty', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_code');
  end if;

  v_code_hash := encode(
    extensions.digest(upper(btrim(p_response_code)), 'sha256'),
    'hex'
  );

  select *
  into v_request
  from public.email_action_requests
  where response_code_hash = v_code_hash
  for update;

  if not found then
    insert into public.email_action_response_log(
      graph_message_id, sender_email, command, result_status,
      result_detail, received_at
    ) values (
      p_graph_message_id, v_sender, v_command, 'invalid_code',
      'No action request matched the supplied response code', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_code');
  end if;

  if v_request.status in ('cancelled', 'expired') then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      v_request.status, 'The action request is no longer active', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', v_request.status);
  end if;

  if v_request.expires_at is not null and now() >= v_request.expires_at then
    update public.email_action_requests
       set status = 'expired', updated_at = now()
     where id = v_request.id;

    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'expired', 'The response arrived after the fixture response deadline',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'expired');
  end if;

  if v_sender = ''
     or v_sender <> lower(btrim(v_request.recipient_email)) then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'sender_mismatch', 'Sender did not match the selected member email address',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'sender_mismatch');
  end if;

  if not (v_command = any(v_request.allowed_actions)) then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'invalid_command', 'Command is not allowed for this action request',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_command');
  end if;

  if v_request.action_type = 'team_selection' then
    select exists (
      select 1
      from public.team_selection_members tsm
      join public.team_selections ts
        on ts.id = tsm.team_selection_id
      join public.fixtures f
        on f.id = ts.fixture_id
      where tsm.id = v_request.target_record_id
        and tsm.member_profile_id = v_request.member_profile_id
        and tsm.role::text = 'player'
        and coalesce(tsm.is_selected, false) = true
        and ts.status = 'published'
        and f.cancelled_at is null
        and f.id = v_request.fixture_id
    ) into v_target_valid;

    v_result_detail := 'Team selection acceptance was updated';

  elsif v_request.action_type = 'marker_assignment' then
    select exists (
      select 1
      from public.team_selection_members tsm
      join public.team_selections ts
        on ts.id = tsm.team_selection_id
      join public.fixtures f
        on f.id = ts.fixture_id
      where tsm.id = v_request.target_record_id
        and tsm.member_profile_id = v_request.member_profile_id
        and tsm.role::text = 'marker'
        and coalesce(tsm.is_selected, false) = true
        and ts.status = 'published'
        and f.cancelled_at is null
        and f.id = v_request.fixture_id
        and exists (
          select 1
          from public.fixture_rink_assignments fra
          where fra.fixture_id = f.id
            and fra.member_profile_id = tsm.member_profile_id
            and fra.position = 201
        )
    ) into v_target_valid;

    v_result_detail := 'Marker assignment acceptance was updated';

  else
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'unsupported_action_type', 'No response handler is installed for this action type',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'unsupported_action_type');
  end if;

  if not v_target_valid then
    update public.email_action_requests
       set status = 'cancelled', updated_at = now()
     where id = v_request.id;

    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'selection_no_longer_active',
      case
        when v_request.action_type = 'marker_assignment'
          then 'The member is no longer the active named marker for this published fixture'
        else 'The player is no longer actively selected for this published fixture'
      end,
      p_received_at
    );

    return jsonb_build_object(
      'ok', false,
      'status', 'selection_no_longer_active'
    );
  end if;

  v_acceptance := case v_command
    when 'ACCEPT' then 'accepted'::public.acceptance_status
    when 'DECLINE' then 'declined'::public.acceptance_status
  end;

  update public.team_selection_members
     set acceptance = v_acceptance,
         responded_at = p_received_at,
         acceptance_by = v_request.member_profile_id
   where id = v_request.target_record_id;

  update public.email_action_requests
     set status = 'responded',
         last_action = v_command,
         last_responded_at = p_received_at,
         last_sender_email = v_sender,
         last_graph_message_id = p_graph_message_id,
         updated_at = now()
   where id = v_request.id;

  insert into public.email_action_response_log(
    request_id, graph_message_id, sender_email, command,
    result_status, result_detail, received_at
  ) values (
    v_request.id, p_graph_message_id, v_sender, v_command,
    'processed', v_result_detail, p_received_at
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'processed',
    'action_type', v_request.action_type,
    'action', v_command,
    'fixture_id', v_request.fixture_id,
    'team_selection_member_id', v_request.target_record_id
  );
end;
$function$;

revoke all
on function public.apply_email_action_response(text, text, text, text, timestamptz)
from public, anon, authenticated;

grant execute
on function public.apply_email_action_response(text, text, text, text, timestamptz)
to service_role;
