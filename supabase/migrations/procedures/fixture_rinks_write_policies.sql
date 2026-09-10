alter table public.fixture_rinks enable row level security;

drop policy if exists "fixture_rinks select (club members)"
on public.fixture_rinks;
create policy "fixture_rinks select (club members)"
on public.fixture_rinks
for select
to authenticated
using (
  exists (
    select 1
    from public.fixtures f
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = public.my_member_profile_id()
     and cm.is_active = true
    where f.id = fixture_rinks.fixture_id
  )
  or exists (
    select 1 from public.app_superusers su where su.user_id = auth.uid()
  )
);

drop policy if exists "fixture_rinks insert (fixture managers)"
on public.fixture_rinks;
create policy "fixture_rinks insert (fixture managers)"
on public.fixture_rinks
for insert
to authenticated
with check (public.can_manage_fixture(fixture_id));

drop policy if exists "fixture_rinks update (fixture managers)"
on public.fixture_rinks;
create policy "fixture_rinks update (fixture managers)"
on public.fixture_rinks
for update
to authenticated
using (public.can_manage_fixture(fixture_id))
with check (public.can_manage_fixture(fixture_id));

drop policy if exists "fixture_rinks delete (fixture managers)"
on public.fixture_rinks;
create policy "fixture_rinks delete (fixture managers)"
on public.fixture_rinks
for delete
to authenticated
using (public.can_manage_fixture(fixture_id));
