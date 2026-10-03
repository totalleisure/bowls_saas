-- Recipient-owned reads and read-state updates; delivery remains server-controlled.
alter table public.app_notifications enable row level security;
revoke all on public.app_notifications from public,anon,authenticated;
grant select on public.app_notifications to authenticated;
grant update(is_read,read_at) on public.app_notifications to authenticated;
create policy notifications_recipient_read on public.app_notifications
for select to authenticated
using (member_profile_id=(select public.my_member_profile_id()));
create policy notifications_recipient_read_state on public.app_notifications
for update to authenticated
using (member_profile_id=(select public.my_member_profile_id()))
with check (member_profile_id=(select public.my_member_profile_id()));
-- No client insert/delete policies. Existing service_role grants remain unchanged.
