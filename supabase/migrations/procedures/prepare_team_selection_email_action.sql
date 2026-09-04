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
  if new.event_type not in ('fixture_selected', 'team_published_player', 'reserve_promoted')
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
      when new.event_type = 'fixture_selected'
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
    and coalesce(tsm.is_selected, false) = true
    and (
      (new.event_type in ('fixture_selected', 'team_published_player', 'reserve_promoted')
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
      (new.event_type = 'fixture_selected'
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ))
      or
      (new.event_type = 'fixture_selected'
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
$function$;

comment on function public.prepare_team_selection_email_action() is
  'Adds modular Accept/Decline action blocks to active published-player, promoted-player, member-opponent and named-marker selection emails.';

grant execute
on function public.prepare_team_selection_email_action()
to public, anon, authenticated, service_role;
