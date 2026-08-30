-- Active Email team-selection responses, synchronized from the live project.
-- Secret values and environment-specific cron configuration are deliberately
-- not embedded in this migration.

create table public.email_action_requests (
  id uuid not null default gen_random_uuid(),
  club_id uuid not null,
  member_profile_id uuid not null,
  recipient_email text not null,
  action_type text not null,
  target_record_id uuid not null,
  fixture_id uuid,
  team_selection_id uuid,
  source_email_queue_id uuid,
  allowed_actions text[] not null,
  response_code_hash text not null,
  expires_at timestamp with time zone,
  status text not null default 'pending'::text,
  last_action text,
  last_responded_at timestamp with time zone,
  last_sender_email text,
  last_graph_message_id text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint email_action_requests_pkey primary key (id),
  constraint email_action_requests_response_code_hash_key unique (response_code_hash),
  constraint email_action_requests_action_type_check
    check (action_type = 'team_selection'::text),
  constraint email_action_requests_allowed_actions_check
    check (cardinality(allowed_actions) > 0),
  constraint email_action_requests_status_check
    check (
      status = any (
        array[
          'pending'::text,
          'responded'::text,
          'expired'::text,
          'cancelled'::text
        ]
      )
    ),
  constraint email_action_requests_club_id_fkey
    foreign key (club_id) references public.clubs(id) on delete cascade,
  constraint email_action_requests_fixture_id_fkey
    foreign key (fixture_id) references public.fixtures(id) on delete cascade,
  constraint email_action_requests_member_profile_id_fkey
    foreign key (member_profile_id)
    references public.member_profiles(id) on delete cascade,
  constraint email_action_requests_source_email_queue_id_fkey
    foreign key (source_email_queue_id)
    references public.email_queue(id) on delete set null,
  constraint email_action_requests_team_selection_id_fkey
    foreign key (team_selection_id)
    references public.team_selections(id) on delete cascade
);

comment on table public.email_action_requests is
  'Reusable correlation and audit records for member responses initiated from email action blocks.';

create index email_action_requests_pending_idx
  on public.email_action_requests using btree (status, expires_at)
  where status = 'pending'::text;

create index email_action_requests_target_idx
  on public.email_action_requests using btree (action_type, target_record_id);

alter table public.email_action_requests enable row level security;

revoke all on table public.email_action_requests from anon, authenticated;
grant all on table public.email_action_requests to service_role;

create table public.email_action_response_log (
  id uuid not null default gen_random_uuid(),
  request_id uuid,
  graph_message_id text not null,
  sender_email text,
  command text,
  result_status text not null,
  result_detail text,
  received_at timestamp with time zone,
  processed_at timestamp with time zone not null default now(),
  constraint email_action_response_log_pkey primary key (id),
  constraint email_action_response_log_graph_message_id_key
    unique (graph_message_id),
  constraint email_action_response_log_request_id_fkey
    foreign key (request_id)
    references public.email_action_requests(id) on delete set null
);

create index email_action_response_log_request_idx
  on public.email_action_response_log using btree (request_id, processed_at desc);

alter table public.email_action_response_log enable row level security;

revoke all on table public.email_action_response_log from anon, authenticated;
grant all on table public.email_action_response_log to service_role;

create table public.email_inbox_sync_state (
  mailbox text not null,
  delta_link text,
  initialized_at timestamp with time zone,
  last_checked_at timestamp with time zone,
  last_success_at timestamp with time zone,
  last_error text,
  updated_at timestamp with time zone not null default now(),
  constraint email_inbox_sync_state_pkey primary key (mailbox)
);

comment on table public.email_inbox_sync_state is
  'Microsoft Graph inbox delta cursor used by the modular email response processor.';

alter table public.email_inbox_sync_state enable row level security;

revoke all on table public.email_inbox_sync_state from anon, authenticated;
grant all on table public.email_inbox_sync_state to service_role;

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
begin
  if new.event_type <> 'fixture_selected'
     or new.member_profile_id is null
     or new.fixture_id is null then
    return new;
  end if;

  select
    ts.id,
    tsm.id,
    f.club_id,
    f.start_at
  into
    v_team_selection_id,
    v_team_selection_member_id,
    v_club_id,
    v_expires_at
  from public.team_selections ts
  join public.team_selection_members tsm
    on tsm.team_selection_id = ts.id
   and tsm.member_profile_id = new.member_profile_id
  join public.fixtures f
    on f.id = ts.fixture_id
  where ts.fixture_id = new.fixture_id
    and ts.status = 'published'
    and coalesce(tsm.is_selected, false) = true
    and tsm.role::text = 'player'
    and f.cancelled_at is null
  limit 1;

  if v_team_selection_member_id is null then
    return new;
  end if;

  update public.email_action_requests
     set status = 'cancelled',
         updated_at = now()
   where action_type = 'team_selection'
     and target_record_id = v_team_selection_member_id
     and status in ('pending', 'responded');

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
    'team_selection',
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
           'action_type', 'team_selection',
           'heading', 'Please respond to your selection',
           'instructions',
             'Select Accept or Decline. Your email application will open a prepared reply; send it without changing the response code.',
           'response_code', v_code,
           'expires_at', v_expires_at,
           'actions', jsonb_build_array(
             jsonb_build_object(
               'command', 'ACCEPT',
               'label', 'Accept selection',
               'style', 'positive'
             ),
             jsonb_build_object(
               'command', 'DECLINE',
               'label', 'Decline selection',
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
  'Adds a modular Accept/Decline action block to newly queued fixture-selected player emails.';

grant execute
on function public.prepare_team_selection_email_action()
to public, anon, authenticated, service_role;

create trigger trg_prepare_team_selection_email_action
after insert on public.email_queue
for each row
execute function public.prepare_team_selection_email_action();

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

  if v_request.action_type <> 'team_selection' then
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
      'The player is no longer actively selected for this published fixture',
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
    'processed', 'Team selection acceptance was updated', p_received_at
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
