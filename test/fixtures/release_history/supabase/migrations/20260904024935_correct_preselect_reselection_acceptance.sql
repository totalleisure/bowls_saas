create or replace function public.save_preselect_fixture_state(
  p_fixture_id uuid,
  p_assignments jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_players_per_rink integer;
  v_captain_member_profile_id uuid;
  v_vice_captain_member_profile_id uuid;
  v_selection_mode text;
  v_team_selection_id uuid;

  v_is_superuser boolean := false;
  v_has_permission boolean := false;

  v_added jsonb := '[]'::jsonb;
  v_removed jsonb := '[]'::jsonb;
  v_retained jsonb := '[]'::jsonb;
  v_role_changed jsonb := '[]'::jsonb;
  v_marker_events jsonb := '[]'::jsonb;
  v_external_opponents jsonb := '[]'::jsonb;
  v_communications jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Assignments must be supplied as a JSON array.';
  end if;

  select
    f.club_id,
    f.players_per_rink,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id,
    lower(btrim(coalesce(ct.selection_mode, '')))
  into
    v_club_id,
    v_players_per_rink,
    v_captain_member_profile_id,
    v_vice_captain_member_profile_id,
    v_selection_mode
  from public.fixtures f
  join public.competition_types ct
    on ct.id = f.competition_type_id
  where f.id = p_fixture_id
  for update of f;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_selection_mode <> 'preselect' then
    raise exception 'This fixture does not use the Pre-Select workflow.';
  end if;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  v_has_permission :=
    v_is_superuser
    or exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
        and (
          lower(cm.role::text) in ('admin', 'selector')
          or v_actor_member_profile_id = v_captain_member_profile_id
          or v_actor_member_profile_id = v_vice_captain_member_profile_id
        )
    );

  if not v_has_permission then
    raise exception 'You do not have permission to maintain this fixture.';
  end if;

  -- ==========================================================
  -- NORMALISE THE COMPLETE SUBMITTED STATE
  --
  -- Positions:
  --   1–4       players
  --   101–104   opponents
  --   201       marker / marker-state record
  -- ==========================================================

  create temporary table preselect_desired_assignments (
    fixture_rink_id uuid not null,
    position integer not null,
    member_profile_id uuid,
    display_name text,
    marker_required boolean not null default false,
    request_marker boolean not null default false,
    role text
  ) on commit drop;

  insert into preselect_desired_assignments (
    fixture_rink_id,
    position,
    member_profile_id,
    display_name,
    marker_required,
    request_marker,
    role
  )
  select
    nullif(btrim(item->>'fixture_rink_id'), '')::uuid,
    nullif(item->>'position', '')::integer,

    case
      when nullif(
        btrim(coalesce(item->>'member_profile_id', '')),
        ''
      ) is null then null
      else (item->>'member_profile_id')::uuid
    end,

    nullif(
      btrim(coalesce(item->>'display_name', '')),
      ''
    ),

    coalesce(
      nullif(item->>'marker_required', '')::boolean,
      false
    ),

    coalesce(
      nullif(item->>'request_marker', '')::boolean,
      false
    ),

    case
      when nullif(item->>'position', '')::integer
        between 1 and v_players_per_rink
        then 'player'

      when nullif(item->>'position', '')::integer
        between 101 and (100 + v_players_per_rink)
        then 'opponent'

      when nullif(item->>'position', '')::integer = 201
        then 'marker'

      else null
    end

  from jsonb_array_elements(
    coalesce(p_assignments, '[]'::jsonb)
  ) as submitted(item);

  -- Every referenced rink must belong to this fixture.
  if exists (
    select 1
    from preselect_desired_assignments d
    left join public.fixture_rinks fr
      on fr.id = d.fixture_rink_id
     and fr.fixture_id = p_fixture_id
    where fr.id is null
  ) then
    raise exception 'An assignment refers to an invalid fixture rink.';
  end if;

  -- Validate the supported slot positions.
  if exists (
    select 1
    from preselect_desired_assignments d
    where not (
      d.position between 1 and v_players_per_rink
      or d.position between 101 and (100 + v_players_per_rink)
      or d.position = 201
    )
  ) then
    raise exception 'An invalid Pre-Select position was supplied.';
  end if;

  -- Only one submitted record may occupy a rink position.
  if exists (
    select 1
    from preselect_desired_assignments
    group by fixture_rink_id, position
    having count(*) > 1
  ) then
    raise exception
      'More than one assignment was supplied for the same rink position.';
  end if;

  -- A known member can only occupy one slot in this fixture.
  if exists (
    select 1
    from preselect_desired_assignments
    where member_profile_id is not null
    group by member_profile_id
    having count(*) > 1
  ) then
    raise exception
      'The same member cannot occupy more than one position in the fixture.';
  end if;

  -- A slot cannot contain both a member and an external name.
  if exists (
    select 1
    from preselect_desired_assignments
    where member_profile_id is not null
      and display_name is not null
  ) then
    raise exception
      'An assignment cannot contain both a member and an external name.';
  end if;

  -- External names are only valid for opponents.
  if exists (
    select 1
    from preselect_desired_assignments
    where display_name is not null
      and role <> 'opponent'
  ) then
    raise exception
      'External names may only be used for opponent positions.';
  end if;

  -- Player/opponent slots need an identity.
  if exists (
    select 1
    from preselect_desired_assignments
    where role in ('player', 'opponent')
      and member_profile_id is null
      and display_name is null
  ) then
    raise exception 'A player or opponent assignment has no identity.';
  end if;

  -- Marker-state-only rows may have no identity, but must actually
  -- represent a requirement or request.
  if exists (
    select 1
    from preselect_desired_assignments
    where role = 'marker'
      and member_profile_id is null
      and display_name is null
      and marker_required = false
      and request_marker = false
  ) then
    raise exception 'An empty marker-state record was supplied.';
  end if;

  if exists (
    select 1
    from preselect_desired_assignments
    where role <> 'marker'
      and (marker_required or request_marker)
  ) then
    raise exception
      'Marker requirement settings must use position 201.';
  end if;

  if exists (
    select 1
    from preselect_desired_assignments
    where role = 'marker'
      and member_profile_id is not null
      and request_marker = true
  ) then
    raise exception
      'A rink cannot request a marker when a marker is already assigned.';
  end if;

  -- All known people must be active members of the fixture club.
  if exists (
    select 1
    from preselect_desired_assignments d
    where d.member_profile_id is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = d.member_profile_id
          and cm.is_active = true
      )
  ) then
    raise exception
      'One or more selected people are not active members of this club.';
  end if;

  -- ==========================================================
  -- ENSURE THE FIXTURE HAS A TEAM SELECTION
  -- ==========================================================

  select ts.id
  into v_team_selection_id
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  for update;

  if v_team_selection_id is null then
    insert into public.team_selections (
      fixture_id,
      status,
      published_at,
      published_by_member_profile_id
    )
    values (
      p_fixture_id,
      'published',
      now(),
      v_actor_member_profile_id
    )
    returning id into v_team_selection_id;
  end if;

  -- Snapshot only the people who were selected immediately before
  -- this Save. Inactive historical rows remain available separately.
  create temporary table preselect_old_selected
  on commit drop
  as
  select
    tsm.member_profile_id,
    tsm.role::text as role,
    tsm.acceptance::text as acceptance,
    tsm.responded_at,
    tsm.acceptance_by
  from public.team_selection_members tsm
  where tsm.team_selection_id = v_team_selection_id
    and tsm.is_selected = true;

  create temporary table preselect_desired_members
  on commit drop
  as
  select
    d.member_profile_id,
    d.role
  from preselect_desired_assignments d
  where d.member_profile_id is not null;

  -- ==========================================================
  -- BUILD THE MEMBER CHANGE SET BEFORE WRITING
  -- ==========================================================

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', d.member_profile_id,
        'role', d.role
      )
      order by d.role, d.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_added
  from preselect_desired_members d
  left join preselect_old_selected o
    on o.member_profile_id = d.member_profile_id
  where o.member_profile_id is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', o.member_profile_id,
        'role', o.role,
        'acceptance', o.acceptance
      )
      order by o.role, o.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_removed
  from preselect_old_selected o
  left join preselect_desired_members d
    on d.member_profile_id = o.member_profile_id
  where d.member_profile_id is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', d.member_profile_id,
        'role', d.role,
        'acceptance', o.acceptance
      )
      order by d.role, d.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_retained
  from preselect_desired_members d
  join preselect_old_selected o
    on o.member_profile_id = d.member_profile_id
   and o.role = d.role;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', d.member_profile_id,
        'old_role', o.role,
        'new_role', d.role
      )
      order by d.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_role_changed
  from preselect_desired_members d
  join preselect_old_selected o
    on o.member_profile_id = d.member_profile_id
   and o.role <> d.role;

  -- ==========================================================
  -- REPLACE THE COMPLETE RINK ASSIGNMENT STATE
  -- ==========================================================

  delete from public.fixture_rink_assignments
  where fixture_id = p_fixture_id;

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    display_name,
    position
  )
  select
    p_fixture_id,
    d.fixture_rink_id,
    d.member_profile_id,
    d.display_name,
    d.position
  from preselect_desired_assignments d
  where d.member_profile_id is not null
     or d.display_name is not null;

  -- ==========================================================
  -- UPDATE TEAM-SELECTION MEMBERS
  --
  -- Removed people remain in history with is_selected=false.
  -- A confirmed re-addition starts a fresh acceptance cycle.
  -- A role change resets acceptance to pending.
  -- ==========================================================

  update public.team_selection_members existing
  set is_selected = false
  where existing.team_selection_id = v_team_selection_id
    and existing.is_selected = true
    and not exists (
      select 1
      from preselect_desired_members desired
      where desired.member_profile_id = existing.member_profile_id
    );

  insert into public.team_selection_members as existing (
    team_selection_id,
    member_profile_id,
    role,
    acceptance,
    responded_at,
    is_selected,
    acceptance_by
  )
  select
    v_team_selection_id,
    desired.member_profile_id,
    desired.role::selection_member_role,

    case
      when desired.member_profile_id =
        v_captain_member_profile_id
        then 'accepted'::acceptance_status
      else 'pending'::acceptance_status
    end,

    null,
    true,
    null

  from preselect_desired_members desired

  on conflict (
    team_selection_id,
    member_profile_id
  )
  do update set
    is_selected = true,

    role = excluded.role,

    acceptance = case
      when excluded.member_profile_id =
        v_captain_member_profile_id
        then 'accepted'::acceptance_status

      when existing.is_selected = false
        then 'pending'::acceptance_status

      when existing.role = excluded.role
        then existing.acceptance

      else 'pending'::acceptance_status
    end,

    responded_at = case
      when existing.is_selected = true
       and existing.role = excluded.role
        then existing.responded_at
      else null
    end,

    acceptance_by = case
      when existing.is_selected = true
       and existing.role = excluded.role
        then existing.acceptance_by
      else null
    end;

  update public.team_selections
  set updated_at = now()
  where id = v_team_selection_id;

  -- ==========================================================
  -- PER-RINK MARKER REQUIREMENTS
  -- ==========================================================

  update public.fixture_rinks fr
  set marker_required = exists (
    select 1
    from preselect_desired_assignments d
    where d.fixture_rink_id = fr.id
      and d.position = 201
      and (
        d.marker_required = true
        or d.request_marker = true
        or d.member_profile_id is not null
      )
  )
  where fr.fixture_id = p_fixture_id;

  create temporary table preselect_marker_events (
    action text not null,
    fixture_rink_id uuid not null,
    member_profile_id uuid
  ) on commit drop;

  -- Assigning a named marker fulfils any open request for that rink.
  with fulfilled as (
    update public.fixture_marker_requests request
    set
      status = 'fulfilled',
      fulfilled_by_member_profile_id = marker.member_profile_id,
      fulfilled_at = now(),
      updated_at = now()
    from preselect_desired_assignments marker
    where request.fixture_rink_id = marker.fixture_rink_id
      and request.status = 'open'
      and marker.position = 201
      and marker.member_profile_id is not null
    returning
      request.fixture_rink_id,
      request.fulfilled_by_member_profile_id
  )
  insert into preselect_marker_events (
    action,
    fixture_rink_id,
    member_profile_id
  )
  select
    'fulfilled',
    fulfilled.fixture_rink_id,
    fulfilled.fulfilled_by_member_profile_id
  from fulfilled;

  -- Cancel open requests no longer present in the authoritative state.
  with cancelled as (
    update public.fixture_marker_requests request
    set
      status = 'cancelled',
      cancelled_by_member_profile_id = v_actor_member_profile_id,
      cancelled_at = now(),
      updated_at = now()
    where request.status = 'open'
      and exists (
        select 1
        from public.fixture_rinks fr
        where fr.id = request.fixture_rink_id
          and fr.fixture_id = p_fixture_id
      )
      and not exists (
        select 1
        from preselect_desired_assignments desired
        where desired.fixture_rink_id = request.fixture_rink_id
          and desired.position = 201
          and desired.request_marker = true
          and desired.member_profile_id is null
      )
    returning request.fixture_rink_id
  )
  insert into preselect_marker_events (
    action,
    fixture_rink_id,
    member_profile_id
  )
  select
    'cancelled',
    cancelled.fixture_rink_id,
    null
  from cancelled;

  -- Open new requests where requested and no request is already open.
  with opened as (
    insert into public.fixture_marker_requests (
      fixture_rink_id,
      status,
      requested_by_member_profile_id
    )
    select
      desired.fixture_rink_id,
      'open',
      v_actor_member_profile_id
    from preselect_desired_assignments desired
    where desired.position = 201
      and desired.request_marker = true
      and desired.member_profile_id is null
      and not exists (
        select 1
        from public.fixture_marker_requests existing
        where existing.fixture_rink_id = desired.fixture_rink_id
          and existing.status = 'open'
      )
    returning fixture_rink_id
  )
  insert into preselect_marker_events (
    action,
    fixture_rink_id,
    member_profile_id
  )
  select
    'opened',
    opened.fixture_rink_id,
    null
  from opened;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'action', event.action,
        'fixture_rink_id', event.fixture_rink_id,
        'fixture_rink_no', fr.fixture_rink_no,
        'member_profile_id', event.member_profile_id
      )
      order by fr.fixture_rink_no, event.action
    ),
    '[]'::jsonb
  )
  into v_marker_events
  from preselect_marker_events event
  join public.fixture_rinks fr
    on fr.id = event.fixture_rink_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'fixture_rink_id', d.fixture_rink_id,
        'fixture_rink_no', fr.fixture_rink_no,
        'position', d.position,
        'display_name', d.display_name
      )
      order by fr.fixture_rink_no, d.position
    ),
    '[]'::jsonb
  )
  into v_external_opponents
  from preselect_desired_assignments d
  join public.fixture_rinks fr
    on fr.id = d.fixture_rink_id
  where d.display_name is not null;

  -- Communications are reconciled inside the same transaction as the save.
  -- If reconciliation fails, the entire save is rolled back.
  perform set_config(
    'app.preselect_reselected_member_ids',
    coalesce(
      (
        select string_agg(d.member_profile_id::text, ',')
        from preselect_desired_members d
        left join preselect_old_selected o
          on o.member_profile_id = d.member_profile_id
        where o.member_profile_id is null
      ),
      ''
    ),
    true
  );

  select public.reconcile_preselect_communications(p_fixture_id)
  into v_communications;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'team_selection_id', v_team_selection_id,
    'added', v_added,
    'removed', v_removed,
    'retained', v_retained,
    'role_changed', v_role_changed,
    'marker_events', v_marker_events,
    'external_opponents', v_external_opponents,
    'communications', coalesce(v_communications, '{}'::jsonb),
    'assignment_count', (
      select count(*)
      from preselect_desired_assignments
      where member_profile_id is not null
         or display_name is not null
    )
  );
end;
$$;

revoke all
on function public.save_preselect_fixture_state(uuid, jsonb)
from public, anon, service_role;

grant execute
on function public.save_preselect_fixture_state(uuid, jsonb)
to authenticated;
