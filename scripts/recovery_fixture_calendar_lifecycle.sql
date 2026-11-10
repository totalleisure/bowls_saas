-- Operator recovery only; not applied during release.
-- Pause new lifecycle dispatch while retaining identities and snapshots.
begin;
alter table public.fixtures disable trigger queue_fixture_calendar;
update public.email_queue set status='cancelled'
where event_type in ('fixture_calendar_updated','fixture_calendar_cancelled')
and status in ('pending','failed') and sent_at is null;
commit;
-- Optional worker rollback: deploy tmp/calendar-lifecycle/worker-before.json files,
-- preserving that environment's gateway settings and worker credentials.
-- Keep capture_fixture_calendar and capture_deleted_fixture_calendar enabled.
-- Resume: alter table public.fixtures enable trigger queue_fixture_calendar;
