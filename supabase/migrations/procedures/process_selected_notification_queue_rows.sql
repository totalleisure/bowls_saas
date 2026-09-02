create or replace function public.process_selected_notification_queue_rows(
  p_queue_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_requested_count integer;
  v_pending_count integer;
begin
  select count(distinct queue_id)
  into v_requested_count
  from unnest(coalesce(p_queue_ids, array[]::uuid[])) queue_id;

  if v_requested_count = 0 then
    raise exception 'At least one notification queue ID is required.';
  end if;

  select count(*)
  into v_pending_count
  from public.notification_queue nq
  where nq.id = any(p_queue_ids)
    and nq.status = 'pending';

  if v_pending_count <> v_requested_count then
    raise exception 'Every requested notification queue row must exist and be pending.';
  end if;

  perform set_config(
    'app.notification_queue_ids',
    array_to_string(
      array(
        select distinct queue_id::text
        from unnest(p_queue_ids) queue_id
        order by queue_id::text
      ),
      ','
    ),
    true
  );

  return public.process_notification_queue(v_requested_count);
end;
$function$;

revoke all on function public.process_selected_notification_queue_rows(uuid[])
from public, anon, authenticated;

grant execute on function public.process_selected_notification_queue_rows(uuid[])
to service_role;
