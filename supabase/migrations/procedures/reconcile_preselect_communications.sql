CREATE OR REPLACE FUNCTION public.reconcile_preselect_communications(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_team_selection_id uuid;
  v_selection_mode text := '';
  v_is_superuser boolean := false;
  v_has_permission boolean := false;
  v_fixture_selected_queued integer := 0;
  v_leadership_queued integer := 0;
  v_fixture_label text;
  v_start_at timestamptz;
  v_is_home boolean;
  v_venue_name text;
  v_captain uuid;
  v_vice uuid;
  v_marker_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select
    f.club_id,
    ts.id,
    lower(coalesce(ct.selection_mode::text, '')),
    coalesce(nullif(btrim(f.team_name), ''), nullif(btrim(ct.name), ''), 'Pre-Select Fixture'),
    f.start_at,
    f.is_home,
    coalesce(v.name, ov.name, ''),
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_club_id,
    v_team_selection_id,
    v_selection_mode,
    v_fixture_label,
    v_start_at,
    v_is_home,
    v_venue_name,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  left join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_team_selection_id is null then
    raise exception 'No team selection exists for this fixture.';
  end if;

  if v_selection_mode <> 'preselect' then
    raise exception 'This repair routine is only for Pre-Select fixtures.';
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
      'You do not have permission to repair this fixture''s communications.';
  end if;

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
    'fixture_selected',
    v_actor_member_profile_id,
    fra.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label',
        coalesce(
          nullif(btrim(f.team_name), ''),
          nullif(btrim(ct.name), ''),
          'Pre-Select Fixture'
        ),
      'start_at', f.start_at,
      'fixture_date', f.start_at,
      'fixture_rink_id', fr.id,
      'team_no', fr.fixture_rink_no,
      'home_rink_label', fr.home_rink_label,
      'players_per_rink', fr.players_per_rink,
      'position', fra.position,
      'role',
        case
          when fra.position = 201 then 'marker'
          when fra.position between 101 and (100 + fr.players_per_rink)
            then 'opponent'
          else 'player'
        end,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  join public.fixtures f
    on f.id = fr.fixture_id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and (
      fra.position between 1 and fr.players_per_rink
      or fra.position between 101 and (100 + fr.players_per_rink)
      or fra.position = 201
    )
    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = v_team_selection_id
        and nq.event_type = 'fixture_selected'
        and nq.target_member_profile_id = fra.member_profile_id
        and (
          nullif(nq.payload ->> 'position', '') is null
          or nq.payload ->> 'position' = fra.position::text
        )
        and (
          nullif(nq.payload ->> 'team_no', '') is null
          or nq.payload ->> 'team_no' = fr.fixture_rink_no::text
        )
    );

  get diagnostics v_fixture_selected_queued = row_count;

  -- Leadership who are not already receiving an assignment-specific message
  -- receive one informational publication copy of the same Team Sheet.
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
    leadership.event_type,
    v_actor_member_profile_id,
    leadership.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'start_at', v_start_at,
      'home_away', case when v_is_home then 'Home' else 'Away' end,
      'venue_name', v_venue_name,
      'team_sheet_required', true
    ),
    'pending'
  from (
    values
      ('team_published_captain'::text, v_captain),
      ('team_published_vice'::text, v_vice)
  ) as leadership(event_type, member_profile_id)
  where leadership.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = p_fixture_id
        and existing.team_selection_id = v_team_selection_id
        and existing.target_member_profile_id = leadership.member_profile_id
        and existing.status in ('pending', 'sent')
        and existing.event_type in (
          'fixture_selected',
          'team_published_captain',
          'team_published_vice'
        )
    );

  get diagnostics v_leadership_queued = row_count;

  -- Reuses the existing duplicate-safe marker routine.
  select public.queue_open_marker_request_communications(p_fixture_id)
  into v_marker_result;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'fixture_selected_queued', v_fixture_selected_queued,
    'leadership_queued', v_leadership_queued,
    'marker_communications',
      coalesce(v_marker_result, '{}'::jsonb),
    'total_communications_queued',
      v_fixture_selected_queued
      + v_leadership_queued
      + coalesce(
          (v_marker_result ->> 'communications_queued')::integer,
          0
        )
  );
end;
$function$;


revoke all on function public.reconcile_preselect_communications(uuid) from public;
revoke all on function public.reconcile_preselect_communications(uuid) from anon;
revoke all on function public.reconcile_preselect_communications(uuid) from authenticated;
