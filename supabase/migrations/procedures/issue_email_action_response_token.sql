CREATE OR REPLACE FUNCTION public.issue_email_action_response_token(
  p_request_id uuid,
  p_email_queue_id uuid,
  p_response_token_hash text
)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_updated integer;
begin
  if p_request_id is null
     or p_email_queue_id is null
     or coalesce(p_response_token_hash, '') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  update public.email_action_requests ear
     set response_token_hash = p_response_token_hash,
         updated_at = now()
   where ear.id = p_request_id
     and ear.source_email_queue_id = p_email_queue_id
     and ear.response_protocol_version = 2
     and ear.response_token_hash is null
     and ear.status = 'pending'
     and exists (
       select 1
       from public.email_queue eq
       where eq.id = p_email_queue_id
         and eq.status = 'processing'
         and eq.sent_at is null
     );

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$function$;

revoke all
on function public.issue_email_action_response_token(uuid, uuid, text)
from public, anon, authenticated;

grant execute
on function public.issue_email_action_response_token(uuid, uuid, text)
to service_role;
