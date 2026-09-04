CREATE OR REPLACE FUNCTION public.queue_open_marker_request_communications(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_team_selection_id uuid;
  v_marker_mailing_list_id uuid;
  v_marker_mailing_list_name text;

  v_is_superuser boolean := false;
  v_has_permission boolean := false;

  v_queued_count integer := 0;
  v_open_request_count integer := 0;
  v_volunteer_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select f.club_id, ts.id
  into v_club_id, v_team_selection_id
  from public.fixtures f
  left join public.team_selections ts
    on ts.fixture_id = f.id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission :=
    v_is_superuser
    or exists (
      select 1
      from public.fixtures f
      where f.id = p_fixture_id
        and (
          f.captain_member_profile_id = v_actor_member_profile_id
          or f.vice_captain_member_profile_id = v_actor_member_profile_id
        )
    )
    or exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) in ('admin', 'selector')
    );

  if not v_has_permission then
    raise exception
      'You do not have permission to send marker requests for this fixture.';
  end if;

  select vt.mailing_list_id, ml.name
  into v_marker_mailing_list_id, v_marker_mailing_list_name
  from public.volunteer_tasks vt
  join public.mailing_lists ml
    on ml.id = vt.mailing_list_id
   and ml.club_id = vt.club_id
   and ml.is_active = true
  where vt.club_id = v_club_id
    and vt.task_code = 'marker'
    and vt.is_active = true
  limit 1;

  if v_marker_mailing_list_id is null then
    raise exception
      'No active Marker volunteer task with an active mailing list is configured for this club.';
  end if;

  select count(*)
  into v_open_request_count
  from public.fixture_marker_requests mr
  join public.fixture_rinks fr
    on fr.id = mr.fixture_rink_id
  where fr.fixture_id = p_fixture_id
    and mr.status = 'open';

  select count(distinct mlm.member_profile_id)
  into v_volunteer_count
  from public.mailing_list_members mlm
  join public.club_memberships cm
    on cm.club_id = v_club_id
   and cm.member_profile_id = mlm.member_profile_id
   and cm.is_active = true
  where mlm.mailing_list_id = v_marker_mailing_list_id
    and mlm.is_active = true
    and not exists (
      select 1
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id = mlm.member_profile_id
        and tsm.is_selected = true
    )
    and not exists (
      select 1
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id = mlm.member_profile_id
    );

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
    'marker_request_opened',
    v_actor_member_profile_id,
    mlm.member_profile_id,
    p_fixture_id,
    v_team_selection_id,

    jsonb_build_object(
      'marker_request_id', mr.id,
      'fixture_rink_id', fr.id,
      'team_no', fr.fixture_rink_no,
      'home_rink_label', fr.home_rink_label,
      'players_per_rink', fr.players_per_rink,
      'mailing_list_id', v_marker_mailing_list_id,
      'mailing_list_name', v_marker_mailing_list_name,

      'fixture_label',
        coalesce(
          nullif(btrim(f.team_name), ''),
          nullif(btrim(ct.name), ''),
          'Pre-Select Fixture'
        ),

      'fixture_date', f.start_at,
      'start_at', f.start_at,
      'end_at', f.end_at,

      'home_away',
        case when f.is_home = true then 'Home' else 'Away' end,

      'venue_name',
        case
          when f.is_home = true
            then coalesce(home_venue.name, '')
          else coalesce(opponent_venue.name, home_venue.name, '')
        end,

      'opponent_name', coalesce(opponent_venue.name, ''),

      'message',
        'A marker is required for Team '
        || fr.fixture_rink_no::text
        || '.'
    ),

    'pending'

  from public.fixture_marker_requests mr
  join public.fixture_rinks fr
    on fr.id = mr.fixture_rink_id
  join public.fixtures f
    on f.id = fr.fixture_id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues home_venue
    on home_venue.id = f.venue_id
  left join public.venues opponent_venue
    on opponent_venue.id = f.opponent_venue_id
  join public.mailing_list_members mlm
    on mlm.mailing_list_id = v_marker_mailing_list_id
   and mlm.is_active = true
  join public.club_memberships cm
    on cm.club_id = f.club_id
   and cm.member_profile_id = mlm.member_profile_id
   and cm.is_active = true

  where fr.fixture_id = p_fixture_id
    and mr.status = 'open'
    and not exists (
      select 1
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id = mlm.member_profile_id
        and tsm.is_selected = true
    )
    and not exists (
      select 1
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id = mlm.member_profile_id
    )
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.event_type = 'marker_request_opened'
        and existing.target_member_profile_id = mlm.member_profile_id
        and existing.payload ->> 'marker_request_id' = mr.id::text
    );

  get diagnostics v_queued_count = row_count;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'mailing_list_id', v_marker_mailing_list_id,
    'mailing_list_name', v_marker_mailing_list_name,
    'open_request_count', v_open_request_count,
    'active_marker_volunteer_count', v_volunteer_count,
    'communications_queued', v_queued_count
  );
end;
$function$;
