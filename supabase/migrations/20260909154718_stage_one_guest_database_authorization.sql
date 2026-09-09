-- Stage 1: protect direct table mutation boundaries while preserving reads and
-- the existing SECURITY DEFINER fixture-management RPC paths.

alter table public.fixture_rink_assignments enable row level security;

revoke all on table public.fixture_rink_assignments from anon;
revoke all on table public.fixture_rink_assignments from authenticated;
grant select on table public.fixture_rink_assignments to authenticated;
grant all on table public.fixture_rink_assignments to service_role;

drop policy if exists "fixture_rink_assignments select (club members)"
  on public.fixture_rink_assignments;

create policy "fixture_rink_assignments select (club members)"
on public.fixture_rink_assignments
for select
to authenticated
using (
  public.is_app_superuser()
  or exists (
    select 1
    from public.fixtures f
    join public.club_memberships cm
      on cm.club_id = f.club_id
    where f.id = fixture_rink_assignments.fixture_id
      and cm.member_profile_id = public.my_member_profile_id()
      and cm.is_active = true
  )
);

drop policy if exists "members can create member bookable fixtures"
  on public.fixtures;

create policy "members can create member bookable fixtures"
on public.fixtures
for insert
to authenticated
with check (
  club_id in (
    select cm.club_id
    from public.club_memberships cm
    where cm.member_profile_id = public.my_member_profile_id()
      and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
  )
  and captain_member_profile_id = public.my_member_profile_id()
  and competition_type_id in (
    select ct.id
    from public.competition_types ct
    where ct.club_id = fixtures.club_id
      and ct.bookable_by_members = true
      and ct.is_active = true
  )
);

drop policy if exists "rsvps insert as admin or superuser"
  on public.fixture_rsvps;

create policy "rsvps insert as admin or superuser"
on public.fixture_rsvps
for insert
to authenticated
with check (
  exists (
    select 1
    from public.fixtures f
    where f.id = fixture_rsvps.fixture_id
      and (
        exists (
          select 1
          from public.app_superusers su
          where su.user_id = auth.uid()
        )
        or exists (
          select 1
          from public.member_profiles actor_mp
          join public.club_memberships actor_cm
            on actor_cm.member_profile_id = actor_mp.id
          where actor_mp.user_id = auth.uid()
            and actor_cm.club_id = f.club_id
            and actor_cm.role = 'admin'::public.club_role
            and actor_cm.is_active = true
        )
      )
      and exists (
        select 1
        from public.club_memberships target_cm
        where target_cm.club_id = f.club_id
          and target_cm.member_profile_id = fixture_rsvps.member_profile_id
          and target_cm.is_active = true
          and lower(target_cm.role::text) <> 'guest'
      )
  )
);

drop policy if exists "rsvps write own"
  on public.fixture_rsvps;

create policy "rsvps write own"
on public.fixture_rsvps
for insert
to authenticated
with check (
  member_profile_id = public.my_member_profile_id()
  and exists (
    select 1
    from public.fixtures f
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = fixture_rsvps.member_profile_id
    where f.id = fixture_rsvps.fixture_id
      and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
  )
);

drop policy if exists "rsvps update own"
  on public.fixture_rsvps;

create policy "rsvps update own"
on public.fixture_rsvps
for update
to authenticated
using (
  member_profile_id = public.my_member_profile_id()
  and exists (
    select 1
    from public.fixtures f
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = fixture_rsvps.member_profile_id
    where f.id = fixture_rsvps.fixture_id
      and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
  )
)
with check (
  member_profile_id = public.my_member_profile_id()
  and exists (
    select 1
    from public.fixtures f
    join public.club_memberships cm
      on cm.club_id = f.club_id
     and cm.member_profile_id = fixture_rsvps.member_profile_id
    where f.id = fixture_rsvps.fixture_id
      and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
  )
);
