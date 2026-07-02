create or replace function public.publish_team_selection_safe(
  p_fixture_id uuid,
  p_team_selection_id uuid,
  p_allow_incomplete boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_required integer;
  v_assigned integer;
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
    raise exception 'You do not have permission to publish this team.';
  end if;

  select coalesce(sum(players_per_rink), 0)
  into v_required
  from public.fixture_rinks
  where fixture_id = p_fixture_id;

  select count(*)
  into v_assigned
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id
    and fra.position between 1 and fr.players_per_rink;

  if v_required > 0 and v_assigned < v_required and p_allow_incomplete = false then
    raise exception 'INCOMPLETE_TEAM:%:%', v_required, v_assigned;
  end if;

  update public.team_selections
  set
    status = 'published'::selection_status,
    published_by_member_profile_id = v_current_member
  where id = p_team_selection_id
    and fixture_id = p_fixture_id;
end;
$$;