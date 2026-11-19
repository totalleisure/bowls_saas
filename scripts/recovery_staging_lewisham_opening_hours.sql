begin;
DROP TRIGGER IF EXISTS b_enforce_lewisham_rink_opening_hours ON public.fixtures;
DROP TRIGGER IF EXISTS b_enforce_lewisham_rink_opening_hours ON public.fixture_rinks;
DROP FUNCTION IF EXISTS public.enforce_lewisham_rink_opening_hours();
commit;
-- Staging recovery only: restores the pre-alignment state. Production already had this protection.
