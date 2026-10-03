-- Device registrations belong to the authenticated identity, not a caller-supplied profile.
alter table public.user_push_tokens enable row level security;
revoke all on public.user_push_tokens from public,anon,authenticated;
grant select,insert,update,delete on public.user_push_tokens to authenticated;
create policy push_tokens_owner on public.user_push_tokens
for all to authenticated
using (user_id=(select auth.uid()))
with check (user_id=(select auth.uid()) and
 (member_profile_id is null or member_profile_id=(select public.my_member_profile_id())));
create index user_push_tokens_owner_idx on public.user_push_tokens(user_id);
-- Existing server-role access is retained; this migration does not send notifications.
