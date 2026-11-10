-- Emergency pause: preserve shared documents, scorer uploads, agreements and
-- result guards. Run only if new claims need pausing during investigation.
begin;
revoke execute on function public.claim_shared_scorecard(uuid,uuid,text,uuid,jsonb) from authenticated;
commit;
-- Resume after review:
-- grant execute on function public.claim_shared_scorecard(uuid,uuid,text,uuid,jsonb) to authenticated;
-- Do not drop the result guard while any shared match is active.
