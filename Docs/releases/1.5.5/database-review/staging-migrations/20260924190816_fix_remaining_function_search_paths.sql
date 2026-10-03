-- Fix only the twelve application functions flagged by the advisor.
alter function public.add_member_to_club_by_email(uuid,text,club_role) set search_path = pg_catalog, public, pg_temp;
alter function public.green_area_must_be_home_venue() set search_path = pg_catalog, public, pg_temp;
alter function public.handle_new_user() set search_path = pg_catalog, public, pg_temp;
alter function public.is_fixture_captain(uuid) set search_path = pg_catalog, public, pg_temp;
alter function public.set_fixture_time_range() set search_path = pg_catalog, public, pg_temp;
alter function public.set_rsvp_member_profile() set search_path = pg_catalog, public, pg_temp;
alter function public.set_updated_at() set search_path = pg_catalog, public, pg_temp;
alter function public.touch_updated_at() set search_path = pg_catalog, public, pg_temp;
alter function public.validate_fixture_links() set search_path = pg_catalog, public, pg_temp;
alter function public.validate_fixture_rink() set search_path = pg_catalog, public, pg_temp;
alter function public.validate_fixture_rink_assignment() set search_path = pg_catalog, public, pg_temp;
alter function audit_private.immutable() set search_path = pg_catalog, pg_temp;
