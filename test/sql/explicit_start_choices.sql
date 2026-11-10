begin;
do $test$
declare m record; a record; event_id uuid:=gen_random_uuid(); r jsonb; n bigint;
begin
 select cm.club_id,mp.user_id,mp.id member_profile_id into strict m from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.is_active and cm.role='member' and mp.user_id is not null and not exists(select 1 from public.app_superusers s where s.user_id=mp.user_id) limit 1;
 select mp.user_id into strict a from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.club_id=m.club_id and cm.role='admin' and cm.is_active and mp.user_id is not null limit 1;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.record_club_start_choice(m.club_id,event_id,'month'); raise exception 'Anonymous allowed'; exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',m.user_id::text,true);
 begin perform public.record_club_start_choice(gen_random_uuid(),event_id,'month'); raise exception 'Cross Club allowed'; exception when insufficient_privilege then null;end;
 begin perform public.record_club_start_choice(m.club_id,event_id,'automatic'); raise exception 'Invalid view allowed'; exception when invalid_parameter_value then null;end;
 perform public.record_club_start_choice(m.club_id,event_id,'month');
 perform public.record_club_start_choice(m.club_id,event_id,'month');
 select count(*) into n from app_reporting.start_choices where start_choices.id=event_id; assert n=1,'Duplicate event';
 begin perform public.get_club_admin_report(m.club_id,current_date,current_date); raise exception 'Member can read report'; exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 r:=public.get_club_admin_report(m.club_id,current_date,current_date);
 assert exists(select 1 from jsonb_array_elements(r->'members') x where x->>'member_profile_id'=m.member_profile_id::text and x->>'explicit_start_view'='month' and x->>'start_view_status'='Explicit choice'),'Choice absent from report';
 perform set_config('request.jwt.claim.sub',m.user_id::text,true);
 perform pg_sleep(0.001);
 perform public.record_club_start_choice(m.club_id,gen_random_uuid(),null);
 perform set_config('request.jwt.claim.sub',a.user_id::text,true);
 r:=public.get_club_admin_report(m.club_id,current_date,current_date);
 assert exists(select 1 from jsonb_array_elements(r->'members') x where x->>'member_profile_id'=m.member_profile_id::text and x->>'explicit_start_view' is null and x->>'start_view_status'='Cleared'),'Cleared not reported';
 assert not has_function_privilege('anon','public.record_club_start_choice(uuid,uuid,text)','execute'),'Anonymous grant';
 assert not has_table_privilege('authenticated','app_reporting.start_choices','select'),'Private choices exposed';
end $test$;
select 'PASS: choice authorization, validation, deduplication, reporting and clearing; all test changes rolled back' result;
rollback;