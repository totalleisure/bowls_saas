begin;
do $test$
declare a record; m record; r jsonb; n bigint; e uuid := gen_random_uuid(); original_login timestamptz;
begin
  select cm.club_id,mp.user_id into strict a from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
    where cm.is_active and cm.role='admin' and mp.user_id is not null limit 1;
  select cm.club_id,mp.user_id,mp.id into strict m from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
    where cm.is_active and cm.role='member' and mp.user_id is not null and not exists(select 1 from public.app_superusers s where s.user_id=mp.user_id) limit 1;
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.get_club_admin_report(a.club_id,current_date-29,current_date); raise exception 'Anonymous report allowed'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',m.user_id::text,true);
  begin perform public.get_club_admin_report(m.club_id,current_date-29,current_date); raise exception 'Member report allowed'; exception when insufficient_privilege then null; end;
  begin perform public.record_club_usage(gen_random_uuid(),gen_random_uuid(),'screen_view','Month View','Windows'); raise exception 'Cross Club usage allowed'; exception when insufficient_privilege then null; end;
  begin perform public.record_club_usage(m.club_id,gen_random_uuid(),'login','Month View','Windows'); raise exception 'Forged login allowed'; exception when invalid_parameter_value then null; end;
  begin perform public.record_club_usage(m.club_id,gen_random_uuid(),'screen_view','Arbitrary typed text','Windows'); raise exception 'Arbitrary screen allowed'; exception when invalid_parameter_value then null; end;
  select count(*) into n from app_reporting.events where user_id=m.user_id;
  perform public.record_club_usage(m.club_id,e,'screen_view','Month View','Windows');
  perform public.record_club_usage(m.club_id,e,'screen_view','Month View','Windows');
  assert (select count(*) from app_reporting.events where user_id=m.user_id)=n+1,'Duplicate event counted twice';
  select last_sign_in_at into original_login from auth.users where id=m.user_id;
  update auth.users set last_sign_in_at=clock_timestamp() where id=m.user_id;
  assert (select count(*) from app_reporting.events where user_id=m.user_id and kind='login')>=1,'Login not captured';
  select count(*) into n from app_reporting.events where user_id=m.user_id and kind='login';
  update auth.users set last_sign_in_at=last_sign_in_at where id=m.user_id;
  assert (select count(*) from app_reporting.events where user_id=m.user_id and kind='login')=n,'Same sign-in counted again';
  perform set_config('request.jwt.claim.sub',a.user_id::text,true);
  r:=public.get_club_admin_report(a.club_id,current_date-29,current_date,0,1);
  assert jsonb_array_length(r->'members')=1,'Page size ignored';
  assert (r->>'total_members')::int=(select count(*) from public.club_memberships where club_id=a.club_id),'Member total incorrect';
  assert (r->'summary'->>'active_members')::int=(select count(*) from public.club_memberships where club_id=a.club_id and is_active),'Active total incorrect';
  assert (r->'members'->0 ? 'surname') and (r->'members'->0 ? 'member_type'),'Missing export fields';
  begin perform public.get_club_admin_report(a.club_id,current_date,current_date-1); raise exception 'Invalid dates allowed'; exception when invalid_parameter_value then null; end;
  if not public.is_app_superuser() then
    begin perform public.get_club_admin_report(gen_random_uuid(),current_date-29,current_date); raise exception 'Cross Club admin allowed'; exception when insufficient_privilege then null; end;
  end if;
  assert not has_function_privilege('anon','public.get_club_admin_report(uuid,date,date,int,int)','execute'),'Anonymous execute granted';
  assert not has_function_privilege('anon','public.record_club_usage(uuid,uuid,text,text,text)','execute'),'Anonymous recorder granted';
  assert not has_schema_privilege('authenticated','app_reporting','usage'),'Private events exposed';
end $test$;
rollback;
select 'PASS: reporting authorization, Club isolation, paging, totals, event validation, deduplication and login capture; all test writes rolled back' result;
