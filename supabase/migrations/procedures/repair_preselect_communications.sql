create or replace function public.repair_preselect_communications(
  p_fixture_id uuid
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.reconcile_preselect_communications(p_fixture_id);
$$;

revoke all on function
  public.repair_preselect_communications(uuid)
from public;

grant execute on function
  public.repair_preselect_communications(uuid)
to authenticated;