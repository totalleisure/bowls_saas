-- Revert member app source first; no existing definitions were amended.
drop function if exists public.create_member_rink_booking(uuid,uuid,uuid,timestamptz,text);
