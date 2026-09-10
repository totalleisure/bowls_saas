create or replace function public.can_manage_fixture(p_fixture_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
  select
    coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or exists (
      select 1
      from public.app_superusers su
      where su.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.fixtures f
      join public.club_memberships cm
        on cm.club_id = f.club_id
       and cm.member_profile_id = public.my_member_profile_id()
       and cm.is_active = true
       and lower(cm.role::text) <> 'guest'
      where f.id = p_fixture_id
        and (
          lower(cm.role::text) in ('admin', 'selector')
          or f.captain_member_profile_id = cm.member_profile_id
          or f.vice_captain_member_profile_id = cm.member_profile_id
        )
    );
$function$;

revoke all on function public.can_manage_fixture(uuid)
from public, anon;
grant execute on function public.can_manage_fixture(uuid)
to authenticated, service_role;
