-- Disable the new signing route; keep signature evidence and additive columns.
revoke all on function public.sign_shared_scorecard_on_device(uuid,uuid,bigint,jsonb,jsonb) from public,anon,authenticated;

