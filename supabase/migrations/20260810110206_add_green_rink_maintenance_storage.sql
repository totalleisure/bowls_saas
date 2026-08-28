create table public.green_rink_maintenance (
  id uuid primary key default gen_random_uuid(),
  maintenance_group_id uuid not null default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  green_area_id uuid not null references public.green_areas(id) on delete cascade,
  rink_number integer not null check (rink_number > 0),
  start_at timestamptz not null,
  end_at timestamptz not null,
  time_range tstzrange generated always as (tstzrange(start_at, end_at, '[)')) stored,
  reason text not null default 'Maintenance',
  notes text,
  status text not null default 'active' check (status in ('active', 'cancelled')),
  created_by_member_profile_id uuid references public.member_profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint green_rink_maintenance_valid_time check (end_at > start_at)
);

create index green_rink_maintenance_green_time_idx
  on public.green_rink_maintenance (green_area_id, start_at, end_at)
  where status = 'active';

create index green_rink_maintenance_group_idx
  on public.green_rink_maintenance (maintenance_group_id);

create or replace function public.validate_green_rink_maintenance()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_green public.green_areas%rowtype;
begin
  select *
  into v_green
  from public.green_areas
  where id = new.green_area_id;

  if not found then
    raise exception 'Green area was not found.';
  end if;

  new.club_id := v_green.club_id;

  if new.rink_number < 1 or new.rink_number > v_green.rink_count then
    raise exception 'Rink number % is not valid for this green.', new.rink_number;
  end if;

  if new.end_at <= new.start_at then
    raise exception 'Maintenance end time must be after the start time.';
  end if;

  if new.status = 'active' and exists (
    select 1
    from public.green_rink_maintenance m
    where m.green_area_id = new.green_area_id
      and m.rink_number = new.rink_number
      and m.status = 'active'
      and m.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and m.time_range && tstzrange(new.start_at, new.end_at, '[)')
  ) then
    raise exception 'This rink already has maintenance during part of the selected period.';
  end if;

  return new;
end;
$$;

create trigger trg_validate_green_rink_maintenance
before insert or update on public.green_rink_maintenance
for each row execute function public.validate_green_rink_maintenance();

alter table public.green_rink_maintenance enable row level security;

create policy green_rink_maintenance_select_club_members
on public.green_rink_maintenance
for select
to authenticated
using (
  exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = green_rink_maintenance.club_id
      and cm.member_profile_id = public.my_member_profile_id()
      and cm.is_active = true
  )
  or exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
);

create policy green_rink_maintenance_insert_admin
on public.green_rink_maintenance
for insert
to authenticated
with check (
  public.is_club_admin(club_id)
  or exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
);

create policy green_rink_maintenance_update_admin
on public.green_rink_maintenance
for update
to authenticated
using (
  public.is_club_admin(club_id)
  or exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
)
with check (
  public.is_club_admin(club_id)
  or exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
);

create policy green_rink_maintenance_delete_admin
on public.green_rink_maintenance
for delete
to authenticated
using (
  public.is_club_admin(club_id)
  or exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
);

revoke all on public.green_rink_maintenance from anon;
grant select, insert, update, delete on public.green_rink_maintenance to authenticated;
