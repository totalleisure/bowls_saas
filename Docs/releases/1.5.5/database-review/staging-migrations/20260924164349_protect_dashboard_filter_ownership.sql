-- Dashboard filters are private to the signed-in owner; club_id remains the app's per-club key.
alter table public.user_club_dashboard_filters enable row level security;
create policy dashboard_filters_owner on public.user_club_dashboard_filters
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
