create or replace function public.retry_fixture_failed_emails(p_fixture_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_ids uuid[];
begin
  perform public.communications_require_superuser();

  update public.email_queue eq
  set status = 'pending', attempts = 0, last_error = null,
      processing_started_at = null, locked_at = null, locked_by = null
  where eq.fixture_id = p_fixture_id
    and eq.status = 'failed'
    and eq.sent_at is null
    and eq.last_error is distinct from
        'Required Team Sheet attachment is missing or stale.'
  ;

  select coalesce(array_agg(eq.id order by eq.created_at), array[]::uuid[])
  into v_ids
  from public.email_queue eq
  where eq.fixture_id = p_fixture_id and eq.status = 'pending';

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'email_queue_ids', to_jsonb(v_ids),
    'pending_count', cardinality(v_ids)
  );
end;
$function$;

revoke all on function public.retry_fixture_failed_emails(uuid)
from public, anon, authenticated;
grant execute on function public.retry_fixture_failed_emails(uuid)
to authenticated;
