create or replace function public.confirm_team_changes(
  p_team_selection_id uuid,
  p_expected_version bigint,
  p_members jsonb,
  p_assignments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
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
    public.can_manage_team_selection(v_fixture_id)
    or exists (
      select 1 from public.fixtures f
      where f.id = v_fixture_id
        and v_actor in (f.captain_member_profile_id, f.vice_captain_member_profile_id)
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

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
    )
  ) then
    raise exception 'Target member is not an active member of this club';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    left join public.fixture_rinks fr
      on fr.id = a.fixture_rink_id and fr.fixture_id = v_fixture_id
    where a.member_profile_id is null
       or fr.id is null
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

  if not exists (
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

  if p_expected_version is distinct from v_current_version then
    raise exception 'TEAM_COMPOSITION_VERSION_CONFLICT:%:%',
      p_expected_version, v_current_version;
  end if;

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
    'communications_queued', v_added_count
  );
end;
$function$;

revoke all on function public.confirm_team_changes(uuid, bigint, jsonb, jsonb)
from public, anon;
grant execute on function public.confirm_team_changes(uuid, bigint, jsonb, jsonb)
to authenticated;
