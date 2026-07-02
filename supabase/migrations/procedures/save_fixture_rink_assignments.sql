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
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if not exists (
    select 1
    from public.fixtures f
    where f.id = p_fixture_id
  ) then
    raise exception 'Fixture not found.';
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
     and fr.fixture_id = p_fixture_id
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

  update public.team_selection_members tsm
  set role = 'player'::selection_member_role
  where tsm.team_selection_id = p_team_selection_id
    and tsm.role = 'reserve'::selection_member_role
    and exists (
      select 1
      from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
      where (item->>'member_profile_id')::uuid = tsm.member_profile_id
    );

  delete from public.fixture_rink_assignments
  where fixture_id = p_fixture_id;

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    position
  )
  select
    p_fixture_id,
    (item->>'fixture_rink_id')::uuid,
    (item->>'member_profile_id')::uuid,
    (item->>'position')::integer
  from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
  where nullif(item->>'member_profile_id', '') is not null;
end;
$$;