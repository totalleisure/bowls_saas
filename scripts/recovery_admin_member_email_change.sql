-- Pause this admin feature without changing any member/account/audit records.
revoke execute on function public.begin_admin_member_email_change(uuid,uuid,uuid,text,text) from service_role;
-- Resume after review:
-- grant execute on function public.begin_admin_member_email_change(uuid,uuid,uuid,text,text) to service_role;
