-- Current client consumes schedules through diary/rink views; server workflows manage rows.
alter table public.club_schedule_items enable row level security;
revoke all on public.club_schedule_items from public,anon,authenticated;
grant select on public.club_schedule_items to authenticated;
create policy schedule_read_active_club on public.club_schedule_items
for select to authenticated
using (club_id in (select public.my_active_club_ids()));
-- Prevent the views from bypassing the table's and fixtures' access rules.
alter view public.club_diary_view set (security_invoker=true);
alter view public.rink_usage_view set (security_invoker=true);
