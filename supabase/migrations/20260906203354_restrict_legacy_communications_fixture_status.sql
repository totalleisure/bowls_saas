revoke all on function public.communications_fixture_status_legacy(uuid)
from public, anon, authenticated;

grant execute on function public.communications_fixture_status_legacy(uuid)
to service_role;
