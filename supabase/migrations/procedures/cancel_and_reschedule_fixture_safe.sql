create or replace function public.cancel_and_reschedule_fixture_safe(
  p_fixture_id uuid,
  p_new_start_at timestamptz,
  p_new_end_at timestamptz,
  p_reason text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_replacement_fixture_id uuid;
begin
  perform public.cancel_fixture_safe(
    p_fixture_id => p_fixture_id,
    p_reason => p_reason
  );

  v_replacement_fixture_id := public.reschedule_cancelled_fixture_safe(
    p_fixture_id => p_fixture_id,
    p_new_start_at => p_new_start_at,
    p_new_end_at => p_new_end_at
  );

  return v_replacement_fixture_id;
end;
$function$;

revoke all on function public.cancel_and_reschedule_fixture_safe(
  uuid,
  timestamptz,
  timestamptz,
  text
) from public;

revoke all on function public.cancel_and_reschedule_fixture_safe(
  uuid,
  timestamptz,
  timestamptz,
  text
) from anon;

grant execute on function public.cancel_and_reschedule_fixture_safe(
  uuid,
  timestamptz,
  timestamptz,
  text
) to authenticated;

grant execute on function public.cancel_and_reschedule_fixture_safe(
  uuid,
  timestamptz,
  timestamptz,
  text
) to service_role;
