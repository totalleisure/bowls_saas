create or replace function public.save_fixture_rink_assignments(
  p_fixture_id uuid,
  p_team_selection_id uuid,
  p_assignments jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_fixture_id uuid;
  v_club_id uuid;
  v_promoted_ids uuid[] := array[]::uuid[];
  v_promoted_id uuid;
begin
  if auth.uid() is null or v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select ts.fixture_id, f.club_id
  into v_fixture_id, v_club_id
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  where ts.id = p_team_selection_id
  for update of ts;

  if not found then raise exception 'Team selection not found.'; end if;
  if p_fixture_id is distinct from v_fixture_id then
    raise exception 'Team selection does not belong to this fixture.';
  end if;

  if not (
    public.can_manage_team_selection(v_fixture_id)
    or exists (
      select 1 from public.fixtures f
      where f.id = v_fixture_id
        and v_current_member in (
          f.captain_member_profile_id,
          f.vice_captain_member_profile_id
        )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  if exists (
    select 1
    from (
      select item->>'member_profile_id' as member_profile_id
      from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
      where nullif(item->>'member_profile_id', '') is not null
      group by item->>'member_profile_id'
      having count(*) > 1
    ) d
  ) then
    raise exception 'A player cannot be assigned more than once.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    left join public.fixture_rinks fr
      on fr.id = (item->>'fixture_rink_id')::uuid
     and fr.fixture_id = v_fixture_id
    where fr.id is null
  ) then
    raise exception 'Invalid team/rink assignment.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    left join public.team_selection_members tsm
      on tsm.team_selection_id = p_team_selection_id
     and tsm.member_profile_id = (item->>'member_profile_id')::uuid
     and tsm.is_selected = true
    where nullif(item->>'member_profile_id', '') is not null
      and tsm.member_profile_id is null
  ) then
    raise exception 'Assigned member is not active in the team selection.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    join public.team_selection_members tsm
      on tsm.team_selection_id = p_team_selection_id
     and tsm.member_profile_id = (item->>'member_profile_id')::uuid
     and tsm.is_selected = true
     and tsm.role in (
       'player'::public.selection_member_role,
       'reserve'::public.selection_member_role
     )
    where nullif(item->>'member_profile_id', '') is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = tsm.member_profile_id
          and cm.is_active = true
      )
  ) then
    raise exception 'Target member is not an active member of this club';
  end if;

  perform 1
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
  for update;

  with promoted as (
    update public.team_selection_members tsm
    set role = 'player'::selection_member_role,
        acceptance = 'pending'::acceptance_status,
        responded_at = null,
        acceptance_by = null
    where tsm.team_selection_id = p_team_selection_id
      and tsm.role = 'reserve'::selection_member_role
      and tsm.is_selected = true
      and exists (
        select 1
        from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
        where (item->>'member_profile_id')::uuid = tsm.member_profile_id
      )
    returning tsm.id
  )
  select coalesce(array_agg(id), array[]::uuid[]) into v_promoted_ids
  from promoted;

  delete from public.notification_queue
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and event_type = 'team_acceptance_changed'
    and status = 'pending'
    and payload->>'new_acceptance' = 'pending'
    and member_profile_id in (
      select tsm.member_profile_id
      from public.team_selection_members tsm
      where tsm.id = any(v_promoted_ids)
    );

  delete from public.fixture_rink_assignments
  where fixture_id = v_fixture_id;

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    position
  )
  select
    v_fixture_id,
    (item->>'fixture_rink_id')::uuid,
    (item->>'member_profile_id')::uuid,
    (item->>'position')::integer
  from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
  where nullif(item->>'member_profile_id', '') is not null;

  foreach v_promoted_id in array v_promoted_ids loop
    perform public.queue_post_publication_player_change(
      v_promoted_id, 'reserve_promoted', v_current_member
    );
  end loop;
end;
$$;

revoke all on function public.save_fixture_rink_assignments(uuid, uuid, jsonb)
from public, anon;
grant execute on function public.save_fixture_rink_assignments(uuid, uuid, jsonb)
to authenticated;
