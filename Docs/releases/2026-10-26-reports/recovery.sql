-- Removes this reporting feature only; export any required counters first.
begin;
drop trigger if exists reporting_login on auth.users;
drop function if exists public.get_club_admin_report(uuid,date,date,int,int);
drop function if exists public.record_club_usage(uuid,uuid,text,text,text);
drop schema if exists app_reporting cascade;
commit;
