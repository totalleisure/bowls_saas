drop policy if exists "member captain can create preselect team selections"
on public.team_selections;
create policy "member captain can create preselect team selections"
on public.team_selections
for insert
to authenticated
with check (
  public.can_manage_fixture(fixture_id)
  and exists (
    select 1
    from public.fixtures f
    join public.competition_types ct on ct.id = f.competition_type_id
    where f.id = team_selections.fixture_id
      and ct.selection_mode = 'preselect'
      and ct.bookable_by_members = true
  )
);

drop policy if exists "member captain can insert preselect team selection members"
on public.team_selection_members;
create policy "member captain can insert preselect team selection members"
on public.team_selection_members
for insert
to authenticated
with check (
  exists (
    select 1
    from public.team_selections ts
    join public.fixtures f on f.id = ts.fixture_id
    join public.competition_types ct on ct.id = f.competition_type_id
    where ts.id = team_selection_members.team_selection_id
      and public.can_manage_fixture(f.id)
      and ct.selection_mode = 'preselect'
      and ct.bookable_by_members = true
  )
);

drop policy if exists "team_selection_members confirm own"
on public.team_selection_members;
create policy "team_selection_members confirm own"
on public.team_selection_members
for update
to authenticated
using (
  member_profile_id = public.my_member_profile_id()
  and exists (
    select 1
    from public.team_selections ts
    join public.fixtures f on f.id = ts.fixture_id
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = team_selection_members.member_profile_id
     and cm.is_active = true
     and lower(cm.role::text) <> 'guest'
    where ts.id = team_selection_members.team_selection_id
      and ts.status = 'published'::public.selection_status
  )
)
with check (
  member_profile_id = public.my_member_profile_id()
  and exists (
    select 1
    from public.team_selections ts
    join public.fixtures f on f.id = ts.fixture_id
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = team_selection_members.member_profile_id
     and cm.is_active = true
     and lower(cm.role::text) <> 'guest'
    where ts.id = team_selection_members.team_selection_id
      and ts.status = 'published'::public.selection_status
  )
);
