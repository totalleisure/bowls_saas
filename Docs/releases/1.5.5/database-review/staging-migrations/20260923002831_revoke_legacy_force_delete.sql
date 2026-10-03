-- This obsolete overload always raises an upgrade error. It is no longer used
-- and must not remain exposed through the Data API.
revoke all on function public.admin_force_delete_fixture(uuid,text)
  from public,anon,authenticated,service_role;
