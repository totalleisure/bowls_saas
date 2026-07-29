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
  v_marker_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select
    f.club_id,
    ts.id,
    lower(coalesce(ct.selection_mode::text, ''))
  into
    v_club_id,
    v_team_selection_id,
    v_selection_mode
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
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
        end
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

  -- Reuses the existing duplicate-safe marker routine.
  select public.queue_open_marker_request_communications(p_fixture_id)
  into v_marker_result;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'fixture_selected_queued', v_fixture_selected_queued,
    'marker_communications',
      coalesce(v_marker_result, '{}'::jsonb),
    'total_communications_queued',
      v_fixture_selected_queued
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
