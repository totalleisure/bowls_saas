create or replace function public.can_manage_team_selection(p_fixture_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, public, auth
as $function$
  select public.can_manage_fixture(p_fixture_id)
      or exists (
        select 1
          from public.fixtures f
          join public.club_memberships cm
            on cm.club_id = f.club_id
           and cm.member_profile_id = public.my_member_profile_id()
         where f.id = p_fixture_id
           and cm.is_active = true
           and lower(cm.role::text) = 'captain'
      );
$function$;

revoke all on function public.can_manage_team_selection(uuid)
from public, anon;
grant execute on function public.can_manage_team_selection(uuid)
to authenticated, service_role;
