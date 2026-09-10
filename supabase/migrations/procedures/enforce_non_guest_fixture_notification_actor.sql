create or replace function public.enforce_non_guest_fixture_notification_actor()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.uid() is not null
     and new.fixture_id is not null
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not exists (
       select 1
       from public.app_superusers su
       where su.user_id = auth.uid()
     )
     and not exists (
       select 1
       from public.fixtures f
       join public.club_memberships cm
         on cm.club_id = f.club_id
        and cm.member_profile_id = public.my_member_profile_id()
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
       where f.id = new.fixture_id
     ) then
    raise exception 'Guest members cannot create fixture communications.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function public.enforce_non_guest_fixture_notification_actor()
from public, anon, authenticated;

drop trigger if exists enforce_non_guest_fixture_notification_actor
on public.notification_queue;
create trigger enforce_non_guest_fixture_notification_actor
before insert
on public.notification_queue
for each row
execute function public.enforce_non_guest_fixture_notification_actor();
