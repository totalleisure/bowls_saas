create or replace function public.communications_require_superuser()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_superusers su where su.user_id = auth.uid()
  ) then
    raise exception 'Superuser access required.';
  end if;
end;
$function$;

revoke all on function public.communications_require_superuser()
from public, anon, authenticated;
