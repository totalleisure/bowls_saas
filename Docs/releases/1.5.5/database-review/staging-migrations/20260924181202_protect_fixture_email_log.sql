-- Delivery evidence is server-managed; the current app uses authorized summary RPCs.
alter table public.fixture_email_log enable row level security;
revoke all on public.fixture_email_log from public,anon,authenticated;
-- Existing service_role privileges and guarded postgres-owned RPCs remain intact.
