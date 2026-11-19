-- Disable further replacements without deleting audit evidence, entries or deliveries.
revoke all on function public.replace_competition_entry_player(uuid,uuid,uuid,uuid[],text,numeric,integer,text) from public,anon,authenticated;
-- Retain the additive cancelled-delivery status: obsolete snapshots must not be resent.
-- Correct any already-applied amendment forward through a reviewed Admin action;
-- do not blindly restore historical player assignments after matches have been played.
