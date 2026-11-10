-- Optional rollback: hide new server-backed setup access without deleting cards.
-- Run only if deliberately disabling fixture scorecard creation.
-- Existing offline/local cards remain usable; no fixture or result functions changed.
revoke execute on function public.fixture_scorecard_context(uuid) from authenticated;
revoke execute on function public.prepare_fixture_scorecard_setup(uuid,uuid,text,jsonb) from authenticated;
-- Re-enable after investigation:
-- grant execute on function public.fixture_scorecard_context(uuid) to authenticated;
-- grant execute on function public.prepare_fixture_scorecard_setup(uuid,uuid,text,jsonb) to authenticated;
