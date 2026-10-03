-- Shared master records are global; club-specific links remain in venues.
alter table public.venue_master enable row level security;
revoke all on public.venue_master from public,anon,authenticated;
grant select,insert,update,delete on public.venue_master to authenticated;
create policy venue_master_shared_read on public.venue_master for select to authenticated using ((select auth.uid()) is not null);
create policy venue_master_superuser_insert on public.venue_master for insert to authenticated with check ((select public.is_app_superuser()));
create policy venue_master_superuser_update on public.venue_master for update to authenticated using ((select public.is_app_superuser())) with check ((select public.is_app_superuser()));
create policy venue_master_superuser_delete on public.venue_master for delete to authenticated using ((select public.is_app_superuser()));
-- Preserve superuser inspection while applying club membership to ordinary callers.
create policy venues_superuser_read on public.venues for select to authenticated using ((select public.is_app_superuser()));
alter view public.venues_with_details set (security_invoker=true);
