-- Recovery only. Restores previous incomplete role coverage.
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
  if new.event_type not in ('fixture_selected', 'team_published_player', 'reserve_promoted', 'acceptance_reminder', 'fixture_rescheduled_selected')
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
      when new.event_type in ('fixture_selected', 'acceptance_reminder', 'fixture_rescheduled_selected')
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ) then 'marker_assignment'
      when new.event_type = 'fixture_rescheduled_selected' and tsm.role::text = 'reserve' then 'team_selection'
      when tsm.role::text = 'player'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 1 and fr.players_per_rink
       ) then 'team_selection'
      when new.event_type in ('fixture_selected', 'acceptance_reminder', 'fixture_rescheduled_selected')
       and tsm.role::text = 'opponent'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 101 and (100 + fr.players_per_rink)
       ) then 'team_selection'
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
    and (new.event_type not in ('acceptance_reminder', 'fixture_rescheduled_selected') or tsm.acceptance::text = 'pending')
    and coalesce(tsm.is_selected, false) = true
    and (
      (new.event_type = 'fixture_rescheduled_selected' and tsm.role::text = 'reserve') or
      (new.event_type in ('fixture_selected', 'team_published_player', 'reserve_promoted', 'acceptance_reminder', 'fixture_rescheduled_selected')
       and tsm.role::text = 'player'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 1 and fr.players_per_rink
       ))
      or
      (new.event_type in ('fixture_selected', 'acceptance_reminder', 'fixture_rescheduled_selected')
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ))
      or
      (new.event_type in ('fixture_selected', 'acceptance_reminder', 'fixture_rescheduled_selected')
       and tsm.role::text = 'opponent'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 101 and (100 + fr.players_per_rink)
       ))
    )
    and f.cancelled_at is null
  limit 1;

  if v_team_selection_member_id is null or v_action_type is null then
    return new;
  end if;

  -- Superseded unsent messages must not reach the token issuer.
  -- Keep sent messages as historical records; their old action is cancelled below.
  update public.email_queue eq
     set status = 'cancelled', last_error = null
   where eq.id in (
     select ear.source_email_queue_id from public.email_action_requests ear
     where ear.action_type = v_action_type
       and ear.target_record_id = v_team_selection_member_id
       and ear.status in ('pending', 'responded')
   )
     and eq.id <> new.id
     and eq.sent_at is null
     and eq.status in ('pending', 'failed');

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
    response_protocol_version,
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
    2,
    v_expires_at
  )
  returning id into v_request_id;

  update public.email_queue
     set payload = coalesce(payload, '{}'::jsonb) ||
       jsonb_build_object(
         'action_block',
         jsonb_build_object(
           'version', 2,
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
$function$
;
CREATE OR REPLACE FUNCTION public.apply_email_action_response(p_response_code text, p_command text, p_sender_email text, p_response_token text, p_graph_message_id text, p_received_at timestamp with time zone DEFAULT now())
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
  v_token_hash text;
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

  if v_request.response_protocol_version >= 2
     and v_request.status = 'responded' then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'already_responded', 'The single-use action request has already been completed',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'already_responded');
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

  if v_request.response_protocol_version >= 2 then
    if v_request.response_token_hash is null then
      insert into public.email_action_response_log(
        request_id, graph_message_id, sender_email, command,
        result_status, result_detail, received_at
      ) values (
        v_request.id, p_graph_message_id, v_sender, v_command,
        'token_not_issued', 'The response token has not been issued for delivery',
        p_received_at
      );

      return jsonb_build_object('ok', false, 'status', 'token_not_issued');
    end if;

    if nullif(btrim(coalesce(p_response_token, '')), '') is null then
      insert into public.email_action_response_log(
        request_id, graph_message_id, sender_email, command,
        result_status, result_detail, received_at
      ) values (
        v_request.id, p_graph_message_id, v_sender, v_command,
        'invalid_token', 'The signed response token was missing',
        p_received_at
      );

      return jsonb_build_object('ok', false, 'status', 'invalid_token');
    end if;

    v_token_hash := encode(
      extensions.digest(upper(btrim(p_response_token)), 'sha256'),
      'hex'
    );

    if v_token_hash <> v_request.response_token_hash then
      insert into public.email_action_response_log(
        request_id, graph_message_id, sender_email, command,
        result_status, result_detail, received_at
      ) values (
        v_request.id, p_graph_message_id, v_sender, v_command,
        'invalid_token', 'The signed response token did not match the action request',
        p_received_at
      );

      return jsonb_build_object('ok', false, 'status', 'invalid_token');
    end if;
  end if;

  -- Tokens identify the request; the sender must also match its recipient.
  if v_sender = ''
     or v_sender <> lower(btrim(v_request.recipient_email)) then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'sender_mismatch',
      'Response sender did not match the intended recipient email address',
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
        and tsm.role::text in ('player', 'opponent', 'reserve')
        and coalesce(tsm.is_selected, false) = true
        and ts.status = 'published'
        and f.cancelled_at is null
        and f.id = v_request.fixture_id
        and ((tsm.role::text = 'reserve' and exists (select 1 from public.email_queue eq where eq.id=v_request.source_email_queue_id and eq.event_type='fixture_rescheduled_selected')) or (tsm.role::text in ('player','opponent') and exists (
          select 1
          from public.fixture_rink_assignments fra
          join public.fixture_rinks fr
            on fr.id = fra.fixture_rink_id
           and fr.fixture_id = f.id
          where fra.fixture_id = f.id
            and fra.member_profile_id = tsm.member_profile_id
            and (
              fra.position between 1 and fr.players_per_rink
              or fra.position between 101 and (100 + fr.players_per_rink)
            )
        )
        ))
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
        else 'The player or member opponent is no longer actively selected for this published fixture'
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
$function$
;
CREATE OR REPLACE FUNCTION public.queue_team_publication_communications(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_fixture_label text;
  v_start_at timestamptz;
  v_home_away text;
  v_venue_name text;
  v_team_id uuid;
  v_captain uuid;
  v_vice uuid;
  v_required integer;
  v_assigned integer;
  v_missing integer;
  v_count integer := 0;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if not public.can_manage_team_selection(p_fixture_id) then
    raise exception 'You do not have permission to queue team communications.';
  end if;

  -- Direct RPC callers must bind the selection to the authorised fixture.
  if not exists (
    select 1 from public.team_selections ts
    where ts.id = p_team_selection_id and ts.fixture_id = p_fixture_id
  ) then
    raise exception 'Team selection does not belong to this fixture.' using errcode = '22023';
  end if;

  select
    coalesce(nullif(f.team_name, ''), 'Fixture'),
    f.start_at,
    case when f.is_home then 'Home' else 'Away' end,
    coalesce(v.name, ov.name, ''),
    f.team_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_fixture_label,
    v_start_at,
    v_home_away,
    v_venue_name,
    v_team_id,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where f.id = p_fixture_id;

  select coalesce(sum(players_per_rink), 0)
  into v_required
  from public.fixture_rinks
  where fixture_id = p_fixture_id;

  select count(*)
  into v_assigned
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and fra.position between 1 and fr.players_per_rink;

  v_missing := greatest(v_required - v_assigned, 0);

  -- Assigned players
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'team_published_player',
    v_current_member,
    fra.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
'special_instructions', (select notes from public.fixtures where id=p_fixture_id),
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id

    -- Only real club members can receive a player notification.
    and fra.member_profile_id is not null

    -- Only actual player positions, not opponents/markers/request rows.
    and fra.position between 1 and fr.players_per_rink

    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = fra.member_profile_id
        and nq.event_type = 'team_published_player'
    );

  get diagnostics v_count = row_count;

  -- Reserves
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'team_published_reserve',
    v_current_member,
    tsm.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
'special_instructions', (select notes from public.fixtures where id=p_fixture_id),
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'reserve'::selection_member_role
    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = tsm.member_profile_id
        and nq.event_type = 'team_published_reserve'
    );

  -- Captain copy
  if v_captain is not null then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'team_published_captain',
      v_current_member,
      v_captain,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
'special_instructions', (select notes from public.fixtures where id=p_fixture_id),
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_captain
        and nq.event_type = 'team_published_captain'
    );
  end if;

  -- Vice captain copy
  if v_vice is not null and v_vice is distinct from v_captain then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'team_published_vice',
      v_current_member,
      v_vice,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
'special_instructions', (select notes from public.fixtures where id=p_fixture_id),
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_vice
        and nq.event_type = 'team_published_vice'
    );
  end if;

  -- Available but not selected: notification/email, no team sheet.
  -- Assumes team_members has team_id/member_profile_id/is_active.
  if v_team_id is not null then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      case
        when p_allow_incomplete = true and v_missing > 0
          then 'team_published_incomplete_request'
        else 'team_published_not_selected'
      end,
      v_current_member,
      tm.member_profile_id,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
'special_instructions', (select notes from public.fixtures where id=p_fixture_id),
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', false
      ),
      'pending'
    from public.team_members tm
    where tm.team_id = v_team_id
      and tm.member_profile_id is not null
      and coalesce(tm.is_active, true) = true
      and not exists (
        select 1
        from public.team_selection_members tsm
        where tsm.team_selection_id = p_team_selection_id
          and tsm.member_profile_id = tm.member_profile_id
          and tsm.is_selected = true
      )
      and not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = p_team_selection_id
          and nq.target_member_profile_id = tm.member_profile_id
          and nq.event_type in (
            'team_published_not_selected',
            'team_published_incomplete_request'
          )
      );
  end if;

  return v_count;
end;
$function$
;
