-- Raw queue contents are restricted to superuser administration and server workers.
alter table public.email_queue enable row level security;
revoke all on public.email_queue from public, anon, authenticated;
grant select on public.email_queue to authenticated;
create policy email_queue_superuser_read on public.email_queue
for select to authenticated using ((select public.is_app_superuser()));
