create or replace function public.communications_fixture_status_v2(p_fixture_id uuid)
returns table(
  status text,
  next_action text,
  message text,
  progress integer,
  can_repair boolean,
  can_prepare boolean,
  can_send boolean,
  can_retry boolean,
  blocking_issues jsonb,
  diagnostics jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_base record;
  v_selection_id uuid;
  v_pending_notifications integer := 0;
  v_pending_sheet_failures integer := 0;
  v_pending_emails integer := 0;
  v_stale_failures integer := 0;
  v_app_expected integer := 0;
  v_app_actual integer := 0;
  v_email_expected integer := 0;
  v_email_actual integer := 0;
  v_email_sent integer := 0;
  v_email_failed integer := 0;
  v_sheet_expected integer := 0;
  v_sheet_actual integer := 0;
begin
  perform public.communications_require_superuser();

  select * into v_base from public.communications_fixture_status(p_fixture_id);

  if v_base.next_action = 'open_fixture' then
    return query select v_base.status, v_base.next_action, v_base.message,
      v_base.progress, false, false, false, false,
      v_base.blocking_issues, v_base.diagnostics;
    return;
  end if;

  select ts.id into v_selection_id
  from public.team_selections ts where ts.fixture_id = p_fixture_id
  order by ts.created_at desc limit 1;

  select
    coalesce(max(expected) filter (where item = 'App notifications created'),0),
    coalesce(max(actual) filter (where item = 'App notifications created'),0),
    coalesce(max(expected) filter (where item = 'Emails queued'),0),
    coalesce(max(actual) filter (where item = 'Emails queued'),0),
    coalesce(max(actual) filter (where item = 'Emails sent'),0),
    coalesce(max(actual) filter (where item = 'Emails failed'),0),
    coalesce(max(expected) filter (where item = 'Team sheets attached'),0),
    coalesce(max(actual) filter (where item = 'Team sheets attached'),0)
  into v_app_expected, v_app_actual, v_email_expected, v_email_actual,
       v_email_sent, v_email_failed, v_sheet_expected, v_sheet_actual
  from public.communications_health_check_v2(p_fixture_id);

  select count(*) into v_pending_notifications
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id and nq.team_selection_id = v_selection_id
    and nq.status = 'pending';
  select count(*) into v_pending_sheet_failures
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_selection_id
    and nq.status = 'pending'
    and nq.payload->>'team_sheet_required' = 'true'
    and not case
      when jsonb_typeof(coalesce(nq.payload->'attachments', '[]'::jsonb)) = 'array'
      then jsonb_array_length(coalesce(nq.payload->'attachments', '[]'::jsonb)) = 1
      and nq.payload->'attachments'->0->>'contentType' = 'application/pdf'
      and nullif(nq.payload->'attachments'->0->>'contentBytes', '') is not null
      and length(nq.payload->'attachments'->0->>'contentBytes') <= 2700000
      and nq.payload->'attachments'->0->>'contentBytes' like 'JVBERi%'
      and nq.payload->'attachments'->0->>'compositionVersion' = (
        select ts.composition_version::text
        from public.team_selections ts where ts.id = v_selection_id
      )
      else false
    end;
  select count(*) into v_pending_emails
  from public.email_queue eq
  where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_selection_id
    and eq.status = 'pending';
  select count(*) into v_stale_failures
  from public.email_queue eq
  where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_selection_id
    and eq.status = 'failed'
    and eq.last_error = 'Required Team Sheet attachment is missing or stale.';

  diagnostics := coalesce(v_base.diagnostics, '{}'::jsonb) || jsonb_build_object(
    'app_notifications_expected',v_app_expected,
    'app_notifications_actual',v_app_actual,
    'emails_expected',v_email_expected,
    'emails_actual',v_email_actual,
    'emails_sent',v_email_sent,
    'emails_failed',v_email_failed,
    'team_sheets_expected',v_sheet_expected,
    'team_sheets_actual',v_sheet_actual,
    'pending_fixture_notifications',v_pending_notifications,
    'pending_invalid_team_sheets',v_pending_sheet_failures,
    'pending_fixture_emails',v_pending_emails
  );
  blocking_issues := coalesce(v_base.blocking_issues, '[]'::jsonb);

  if v_stale_failures > 0 or v_pending_sheet_failures > 0 then
    return query select 'team_sheets_required'::text,
      'prepare_team_sheets'::text,
      'Current Team Sheet attachments must be prepared before sending.'::text,
      70, false, false, false, false, blocking_issues, diagnostics;
  elsif v_pending_notifications > 0 then
    return query select 'preparation_required'::text, 'prepare_messages'::text,
      'This fixture has pending notifications ready to prepare.'::text,
      65, false, true, false, false, blocking_issues, diagnostics;
  elsif v_app_actual < v_app_expected or v_email_actual < v_email_expected then
    return query select 'communications_repair_required'::text,
      'repair_communications'::text,
      'Current recipients are missing fixture communication records.'::text,
      55, true, false, false, false, blocking_issues, diagnostics;
  elsif v_sheet_actual < v_sheet_expected then
    return query select 'team_sheets_required'::text,
      'prepare_team_sheets'::text,
      'Current Team Sheet attachments must be prepared before sending.'::text,
      70, false, false, false, false, blocking_issues, diagnostics;
  elsif v_email_failed > 0 then
    return query select 'email_retry_required'::text, 'retry_failed_emails'::text,
      'Some fixture emails failed and can be retried safely.'::text,
      80, false, false, false, true, blocking_issues, diagnostics;
  elsif v_pending_emails > 0 or v_email_sent < v_email_expected then
    return query select 'ready_to_send'::text, 'send_emails'::text,
      'This fixture has prepared emails ready to send.'::text,
      90, false, false, true, false, blocking_issues, diagnostics;
  else
    return query select 'communications_complete'::text, 'complete'::text,
      'All expected fixture communications and Team Sheets are complete.'::text,
      100, false, false, false, false, blocking_issues, diagnostics;
  end if;
end;
$function$;

revoke all on function public.communications_fixture_status_v2(uuid)
from public, anon, authenticated;
grant execute on function public.communications_fixture_status_v2(uuid)
to authenticated;
