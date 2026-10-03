CREATE OR REPLACE FUNCTION public.confirm_team_changes(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb, p_rinks jsonb, p_original_rinks jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fixture public.fixtures%rowtype;
  v_rinks jsonb;
  v_saved_rinks jsonb;
  v_expected_rinks jsonb;
  v_structure_changed boolean;
  v_before_selected uuid[];
  v_dropped_count integer := 0;
  v_withdrawn jsonb := '{}'::jsonb;
  v_withdrawn_count integer := 0;
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_current_version bigint;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_before_positioned uuid[] := array[]::uuid[];
  v_before_reserves uuid[] := array[]::uuid[];
  v_after_positioned uuid[] := array[]::uuid[];
  v_added uuid[] := array[]::uuid[];
  v_removed uuid[] := array[]::uuid[];
  v_before_assignments jsonb := '{}'::jsonb;
  v_after_assignments jsonb := '{}'::jsonb;
  v_member_id uuid;
  v_event_type text;
  v_added_count integer := 0;
  v_removed_count integer := 0;
  v_promoted_count integer := 0;
  v_moved_count integer := 0;
  v_reserve_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;

  v_actor := public.my_member_profile_id();
  if v_actor is null then
    raise exception 'Member profile not found.';
  end if;

  if jsonb_typeof(coalesce(p_members, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Team change payload must contain arrays.';
  end if;

  -- Match the existing structure editor's fixture-before-selection lock order.
  select f.* into v_fixture from public.fixtures f
  join public.team_selections ts on ts.fixture_id=f.id
  where ts.id=p_team_selection_id for update of f;
  if not found or v_fixture.cancelled_at is not null then
    raise exception 'Active fixture not found.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select
    ts.fixture_id,
    f.club_id,
    ts.composition_version,
    lower(btrim(coalesce(ct.selection_mode, ''))),
    f.team_id,
    coalesce(f.requires_rsvp, false)
  into
    v_fixture_id,
    v_club_id,
    v_current_version,
    v_selection_mode,
    v_team_id,
    v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
    and ts.status = 'published'::public.selection_status
  for update of ts;

  if not found then
    raise exception 'Published team selection not found.';
  end if;

  if v_selection_mode = 'preselect'
     or (v_team_id is null and not v_requires_rsvp) then
    raise exception 'Confirm Team Changes is only available for published Team or RSVP fixtures.';
  end if;

  if not (
    public.is_app_superuser()
    or (
      exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = v_actor
          and cm.is_active = true
          and lower(cm.role::text) <> 'guest'
      )
      and (
        public.can_manage_team_selection(v_fixture_id)
        or exists (
          select 1 from public.fixtures f
          where f.id = v_fixture_id
            and v_actor in (
              f.captain_member_profile_id,
              f.vice_captain_member_profile_id
            )
        )
      )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  if jsonb_typeof(p_rinks) is distinct from 'array'
     or jsonb_typeof(p_original_rinks) is distinct from 'array'
     or jsonb_array_length(p_rinks)=0 then
    raise exception 'At least one desired team is required.';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_rinks)
    as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text)
    where r.id is null or r.fixture_rink_no is null or r.fixture_rink_no<1
      or r.players_per_rink is distinct from case r.format
        when 'singles' then 1 when 'pairs' then 2 when 'aussie_pairs' then 2
        when 'triples' then 3 when 'rinks' then 4 when 'fours' then 4 end
      or r.format is null or r.format not in ('singles','pairs','aussie_pairs','triples','rinks','fours')
      or exists(select 1 from public.fixture_rinks fr where fr.id=r.id and fr.fixture_id<>v_fixture_id)) then
    raise exception 'Invalid desired team structure.';
  end if;
  if (select count(distinct r.id) from jsonb_to_recordset(p_rinks) as r(id uuid))<>jsonb_array_length(p_rinks)
     or (select count(distinct r.fixture_rink_no) from jsonb_to_recordset(p_rinks) as r(fixture_rink_no integer))<>jsonb_array_length(p_rinks)
     or (select max(r.fixture_rink_no) from jsonb_to_recordset(p_rinks) as r(fixture_rink_no integer))<>jsonb_array_length(p_rinks)
     or exists(select 1 from jsonb_to_recordset(p_rinks) as r(home_rink_label text)
       where nullif(btrim(r.home_rink_label),'') is not null
       group by btrim(r.home_rink_label) having count(*)>1) then
    raise exception 'Duplicate or invalid team numbers or physical rinks.';
  end if;
  select jsonb_agg(jsonb_build_object('id',r.id,'fixture_rink_no',r.fixture_rink_no,
      'format',r.format,'players_per_rink',r.players_per_rink,
      'home_rink_label',nullif(btrim(r.home_rink_label),'')) order by r.id)
  into v_rinks from jsonb_to_recordset(p_rinks)
    as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text);
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'fixture_rink_no',r.fixture_rink_no,
      'format',r.format,'players_per_rink',r.players_per_rink,
      'home_rink_label',nullif(btrim(r.home_rink_label),'')) order by r.id),'[]'::jsonb)
  into v_saved_rinks from public.fixture_rinks r where r.fixture_id=v_fixture_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'fixture_rink_no',r.fixture_rink_no,
      'format',r.format,'players_per_rink',r.players_per_rink,
      'home_rink_label',nullif(btrim(r.home_rink_label),'')) order by r.id),'[]'::jsonb)
  into v_expected_rinks from jsonb_to_recordset(p_original_rinks)
    as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text);
  v_structure_changed := v_rinks is distinct from v_saved_rinks;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where m.member_profile_id is null
       or lower(btrim(coalesce(m.role, ''))) not in ('player', 'reserve')
       or coalesce(m.is_selected, false) = false
  ) then
    raise exception 'Invalid desired team member state.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    group by m.member_profile_id
    having count(*) > 1
  ) then
    raise exception 'A member cannot appear more than once in the desired team.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where not exists (
      select 1 from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = m.member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
    )
  ) then
    raise exception 'Target member is not an active non-Guest member of this club';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    left join jsonb_to_recordset(v_rinks) as fr(id uuid,players_per_rink integer)
      on fr.id = a.fixture_rink_id
    where a.member_profile_id is null
       or fr.id is null
       or a.position is null
       or a.position not between 1 and fr.players_per_rink
       or not exists (
         select 1
         from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
           as m(member_profile_id uuid, role text, is_selected boolean)
         where m.member_profile_id = a.member_profile_id
           and lower(btrim(m.role)) = 'player'
           and m.is_selected = true
       )
  ) then
    raise exception 'Invalid player-position assignment.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.member_profile_id
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.fixture_rink_id, a.position
    having count(*) > 1
  ) then
    raise exception 'Duplicate desired player-position assignment.';
  end if;

  perform 1 from public.team_selection_members
  where team_selection_id = p_team_selection_id for update;
  perform 1 from public.fixture_rink_assignments
  where fixture_id = v_fixture_id for update;

  if not v_structure_changed and not exists (
    (
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
      except
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
    )
    union all
    (
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      except
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
    )
  ) and not exists (
    (
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
      except
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    )
    union all
    (
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
      except
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
    )
  ) then
    return jsonb_build_object(
      'composition_version', v_current_version,
      'newly_positioned', 0,
      'reserve_promotions', 0,
      'removed_from_player_positions', 0,
      'position_only_moves', 0,
      'communications_queued', 0,
      'no_change', true
    );
  end if;

  if p_expected_version is distinct from v_current_version
     or v_saved_rinks is distinct from v_expected_rinks then
    raise exception 'TEAM_COMPOSITION_VERSION_CONFLICT:%:%',
      p_expected_version, v_current_version;
  end if;

  -- Validate capacity/availability once for the final structure, not each intermediate edit.
  if v_structure_changed and v_fixture.green_area_id is not null then
    perform 1 from public.green_areas where id=v_fixture.green_area_id for update;
  end if;
  if v_structure_changed and exists(select 1 from jsonb_to_recordset(v_rinks) as r(home_rink_label text)
      where r.home_rink_label is not null) then
    if not v_fixture.is_home or v_fixture.green_area_id is null then
      raise exception 'Only a home fixture can be assigned a physical rink.';
    end if;
    if exists(select 1 from jsonb_to_recordset(v_rinks) as r(home_rink_label text)
      where r.home_rink_label is not null and not exists(
        select 1 from public.get_green_rink_availability(v_fixture.green_area_id,
          v_fixture.start_at,v_fixture.end_at,v_fixture.id) a
        where a.rink_label=r.home_rink_label and not a.is_booked)) then
      raise exception 'That physical rink is not available.';
    end if;
  end if;
  select coalesce(array_agg(member_profile_id),array[]::uuid[]) into v_before_selected
  from public.team_selection_members where team_selection_id=p_team_selection_id
    and is_selected and role in ('player','reserve');

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_before_positioned, v_before_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(member_profile_id), array[]::uuid[])
  into v_before_reserves
  from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and is_selected = true
    and role = 'reserve'::public.selection_member_role;

  if exists(select 1 from unnest(v_before_positioned) m(id)
      join jsonb_to_recordset(p_members) as desired(member_profile_id uuid,role text)
        on desired.member_profile_id=m.id and desired.role='player'
      where not exists(select 1 from jsonb_to_recordset(p_assignments)
        as a(member_profile_id uuid) where a.member_profile_id=m.id)) then
    raise exception 'Resolve unpositioned players: assign a position, make reserve or remove before confirming.';
  end if;

  -- Capture members of deleted teams before changing their positions or team numbers.
  select coalesce(jsonb_object_agg(a.key, r.fixture_rink_no), '{}'::jsonb)
    into v_withdrawn
  from jsonb_each(v_before_assignments) a
  join public.fixture_rinks r on r.id=(a.value->>'fixture_rink_id')::uuid
    and r.fixture_id=v_fixture_id
  where not exists(select 1 from jsonb_to_recordset(v_rinks) as desired(id uuid)
    where desired.id=r.id);

  insert into public.team_selection_members (
    team_selection_id, member_profile_id, role, acceptance,
    responded_at, is_selected, acceptance_by
  )
  select
    p_team_selection_id,
    m.member_profile_id,
    lower(btrim(m.role))::public.selection_member_role,
    'pending'::public.acceptance_status,
    null,
    true,
    null
  from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
    as m(member_profile_id uuid, role text, is_selected boolean)
  on conflict (team_selection_id, member_profile_id) do update set
    role = excluded.role,
    is_selected = true;

  update public.team_selection_members tsm
  set is_selected = false
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role in (
      'player'::public.selection_member_role,
      'reserve'::public.selection_member_role
    )
    and not exists (
      select 1
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      where m.member_profile_id = tsm.member_profile_id
    );

  delete from public.fixture_rink_assignments fra
  using public.fixture_rinks fr
  where fra.fixture_id = v_fixture_id
    and fr.id = fra.fixture_rink_id
    and fr.fixture_id = v_fixture_id
    and fra.position between 1 and fr.players_per_rink;

  if v_structure_changed then
    delete from public.fixture_rinks fr where fr.fixture_id=v_fixture_id
      and not exists(select 1 from jsonb_to_recordset(v_rinks) as r(id uuid) where r.id=fr.id);
    -- Temporary numbers avoid collisions while deleted teams are renumbered.
    update public.fixture_rinks set fixture_rink_no=fixture_rink_no+1000000
      where fixture_id=v_fixture_id;
    insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label)
    select r.id,v_fixture_id,r.fixture_rink_no,r.format,r.players_per_rink,r.home_rink_label
    from jsonb_to_recordset(v_rinks)
      as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text)
    on conflict(id) do update set fixture_rink_no=excluded.fixture_rink_no,
      format=excluded.format,players_per_rink=excluded.players_per_rink,home_rink_label=excluded.home_rink_label;
    update public.fixtures set rinks_required=jsonb_array_length(v_rinks),
      players_per_rink=(select max(r.players_per_rink) from jsonb_to_recordset(v_rinks) as r(players_per_rink integer))
      where id=v_fixture_id;
  end if;

  insert into public.fixture_rink_assignments (
    fixture_id, fixture_rink_id, member_profile_id, position
  )
  select v_fixture_id, a.fixture_rink_id, a.member_profile_id, a.position
  from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
    as a(fixture_rink_id uuid, position integer, member_profile_id uuid);

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_after_positioned, v_after_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(x), array[]::uuid[]) into v_added
  from unnest(v_after_positioned) x where not (x = any(v_before_positioned));
  select coalesce(array_agg(x), array[]::uuid[]) into v_removed
  from unnest(v_before_positioned) x where not (x = any(v_after_positioned));

  update public.team_selection_members
  set acceptance = 'pending'::public.acceptance_status,
      responded_at = null,
      acceptance_by = null
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added);

  delete from public.notification_queue
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added)
    and event_type = 'team_acceptance_changed'
    and status = 'pending'
    and payload->>'new_acceptance' = 'pending';

  update public.email_action_requests
  set status = 'cancelled', updated_at = now()
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and status in ('pending', 'responded');

  update public.notification_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and target_member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status = 'pending';

  update public.email_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status in ('pending', 'failed')
    and sent_at is null;

  foreach v_member_id in array v_added loop
    v_event_type := case
      when v_member_id = any(v_before_reserves) then 'reserve_promoted'
      else 'fixture_selected'
    end;
    perform public.queue_post_publication_player_change(
      (select id from public.team_selection_members
       where team_selection_id = p_team_selection_id
         and member_profile_id = v_member_id),
      v_event_type,
      v_actor
    );
    v_added_count := v_added_count + 1;
    if v_event_type = 'reserve_promoted' then
      v_promoted_count := v_promoted_count + 1;
    end if;
  end loop;


  -- Communicate the final reserve state once, rather than a removal notice.
  -- Existing attachment handling blocks delivery until the current PDF exists.
  insert into public.notification_queue (
    event_type, member_profile_id, target_member_profile_id,
    fixture_id, team_selection_id, payload, status
  )
  select
    'team_published_reserve', v_actor, tsm.member_profile_id,
    v_fixture_id, p_team_selection_id,
    jsonb_build_object(
      'fixture_label', coalesce(nullif(btrim(f.team_name), ''), 'Fixture'),
      'fixture_date', f.start_at,
      'start_at', f.start_at,
      'home_away', case when f.is_home then 'Home' else 'Away' end,
      'venue_name', coalesce(v.name, ov.name, ''),
      'role', 'reserve',
      'new_role', 'reserve',
      'team_sheet_required', true
    ),
    'pending'
  from public.team_selection_members tsm
  join public.fixtures f on f.id = v_fixture_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'reserve'::public.selection_member_role
    and not (tsm.member_profile_id = any(v_before_reserves))
    and not (v_withdrawn ? tsm.member_profile_id::text);
  get diagnostics v_reserve_count = row_count;

  -- Cancel unsent selection/reserve messages for people absent from the final team.
  update public.notification_queue nq set status='cancelled'
  where nq.team_selection_id=p_team_selection_id and nq.status in ('pending','failed')
    and nq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve')
    and nq.target_member_profile_id=any(v_before_selected)
    and not exists(select 1 from jsonb_to_recordset(p_members) as m(member_profile_id uuid)
      where m.member_profile_id=nq.target_member_profile_id);
  update public.email_queue eq set status='cancelled'
  where eq.team_selection_id=p_team_selection_id and eq.status in ('pending','failed') and eq.sent_at is null
    and eq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve')
    and eq.member_profile_id=any(v_before_selected)
    and not exists(select 1 from jsonb_to_recordset(p_members) as m(member_profile_id uuid)
      where m.member_profile_id=eq.member_profile_id);

  -- Only explicitly removed members get a dropped notice. Reserves receive their final reserve event above.
  insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,
    fixture_id,team_selection_id,payload,status)
  select 'fixture_message',v_actor,m.id,v_fixture_id,p_team_selection_id,
    jsonb_build_object('title','Team selection changed',
      'message','You are no longer selected for this fixture.',
      'fixture_label',coalesce(nullif(v_fixture.team_name,''),'Fixture'),
      'fixture_date',v_fixture.start_at,'change_kind','removed_from_selection'), 'pending'
  from unnest(v_before_selected) m(id)
  where not (v_withdrawn ? m.id::text)
    and not exists(select 1 from jsonb_to_recordset(p_members) as x(member_profile_id uuid)
    where x.member_profile_id=m.id);
  get diagnostics v_dropped_count = row_count;

  -- Supersede older unsent status messages with one final withdrawal outcome.
  update public.notification_queue nq set status='cancelled'
  where nq.team_selection_id=p_team_selection_id and nq.status in ('pending','failed')
    and v_withdrawn ? nq.target_member_profile_id::text
    and (nq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve')
      or (nq.event_type='fixture_message' and nq.payload->>'change_kind'='team_withdrawn'));
  update public.email_queue eq set status='cancelled'
  where eq.team_selection_id=p_team_selection_id and eq.status in ('pending','failed') and eq.sent_at is null
    and v_withdrawn ? eq.member_profile_id::text
    and eq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve');

  -- Use the existing fixture-message delivery path, with an explicit change kind.
  -- Its required-sheet flag blocks retained/reserve delivery until the PDF is rebuilt.
  insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,
    fixture_id,team_selection_id,payload,status)
  select 'fixture_message',v_actor,w.key::uuid,v_fixture_id,p_team_selection_id,
    jsonb_build_object(
      'title','Team withdrawn',
      'message',format('Your team (Team %s) has been withdrawn from this fixture. ',w.value) ||
        case when m.role='reserve' then 'You are now a reserve.'
          when m.role='player' then format('You have been reassigned to Team %s.',r.fixture_rink_no)
          else 'You are no longer required to play.' end ||
        ' The fixture is still going ahead.',
      'fixture_label',coalesce(nullif(v_fixture.team_name,''),'Fixture'),
      'fixture_date',v_fixture.start_at,
      'change_kind','team_withdrawn',
      'previous_team_number',w.value::integer,
      'final_role',coalesce(m.role,'removed'),
      'final_team_number',r.fixture_rink_no,
      'team_sheet_required',coalesce(m.role in ('player','reserve'),false)
    ),'pending'
  from jsonb_each_text(v_withdrawn) w
  left join jsonb_to_recordset(p_members) as m(member_profile_id uuid,role text)
    on m.member_profile_id=w.key::uuid
  left join jsonb_to_recordset(p_assignments) as a(member_profile_id uuid,fixture_rink_id uuid)
    on a.member_profile_id=w.key::uuid
  left join public.fixture_rinks r on r.id=a.fixture_rink_id and r.fixture_id=v_fixture_id;
  get diagnostics v_withdrawn_count = row_count;

  v_removed_count := coalesce(array_length(v_removed, 1), 0);
  select count(*) into v_moved_count
  from unnest(v_after_positioned) x
  where x = any(v_before_positioned)
    and v_before_assignments->(x::text) is distinct from v_after_assignments->(x::text);

  update public.team_selections
  set composition_version = composition_version + 1
  where id = p_team_selection_id
  returning composition_version into v_current_version;

  return jsonb_build_object(
    'composition_version', v_current_version,
    'newly_positioned', v_added_count,
    'reserve_promotions', v_promoted_count,
    'removed_from_player_positions', v_removed_count,
    'position_only_moves', v_moved_count,
    'communications_queued', v_added_count + v_reserve_count + v_dropped_count + v_withdrawn_count,
    'team_withdrawal_messages', v_withdrawn_count,
    'dropped', v_dropped_count,
    'structure_changed', v_structure_changed
  );
end;
$function$;

revoke all on function public.confirm_team_changes(uuid,bigint,jsonb,jsonb,jsonb,jsonb) from public, anon;
grant execute on function public.confirm_team_changes(uuid,bigint,jsonb,jsonb,jsonb,jsonb) to authenticated;
