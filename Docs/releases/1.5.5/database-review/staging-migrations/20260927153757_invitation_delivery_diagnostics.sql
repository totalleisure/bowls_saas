-- Diagnostic metadata only. Existing access policies remain in force.
alter table public.member_invitation_attempts
  add column if not exists provider_status integer,
  add column if not exists provider_code text,
  add column if not exists provider_request_id text,
  add column if not exists retry_after_seconds integer;
