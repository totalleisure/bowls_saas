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

  if not (
    public.can_manage_team_selection(p_fixture_id)
    or exists (
      select 1
      from public.fixtures f
      where f.id = p_fixture_id
        and (
          f.captain_member_profile_id = v_current_member
          or f.vice_captain_member_profile_id = v_current_member
        )
    )
  ) then
    raise exception 'You do not have permission to queue team communications.';
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
