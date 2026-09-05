create or replace function public.process_fixture_notification_queue(
  p_fixture_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_ids uuid[];
begin
  perform public.communications_require_superuser();

  select coalesce(array_agg(nq.id order by nq.created_at), array[]::uuid[])
  into v_ids
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id and nq.status = 'pending';

  if cardinality(v_ids) = 0 then return 0; end if;

  perform set_config(
    'app.notification_queue_ids',
    array_to_string(v_ids, ','),
    true
  );
  return public.process_notification_queue(cardinality(v_ids));
end;
$function$;

revoke all on function public.process_fixture_notification_queue(uuid)
from public, anon, authenticated;
grant execute on function public.process_fixture_notification_queue(uuid)
to authenticated;
