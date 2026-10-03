begin;
set local statement_timeout='30s';
create temp table schedule_results(test text,passed boolean) on commit drop;
grant insert,select on schedule_results to authenticated,anon,service_role;
do $test$
declare
 u uuid:=gen_random_uuid(); other_u uuid:=gen_random_uuid();
 c uuid:=gen_random_uuid(); other_c uuid:=gen_random_uuid();
 p uuid; other_p uuid; a uuid; b uuid; n integer; denied boolean; v text;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must remain disabled'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
 values(u,u::text||'@example.invalid','{"display_name":"Schedule RLS test"}','{}'),
 (other_u,other_u::text||'@example.invalid','{"display_name":"Schedule RLS test"}','{}');
 select id into p from public.member_profiles where user_id=u;
 select id into other_p from public.member_profiles where user_id=other_u;
 insert into public.clubs(id,name) values(c,'ROLLBACK schedule A'),(other_c,'ROLLBACK schedule B');
 insert into public.club_memberships(club_id,member_profile_id,role,is_active)
 values(c,p,'member',true),(other_c,other_p,'admin',true);
 set local role service_role;
 insert into public.club_schedule_items(club_id,title,item_type,activity_type,start_at,end_at,needs_rinks,rinks_required)
 values(c,'Schedule A','session','test','2030-01-01 12:00Z','2030-01-01 14:00Z',true,2) returning id into a;
 insert into public.club_schedule_items(club_id,title,item_type,activity_type,start_at,end_at,needs_rinks,rinks_required)
 values(other_c,'Schedule B','session','test','2030-01-01 12:00Z','2030-01-01 14:00Z',true,3) returning id into b;
 insert into schedule_results select 'server can create/read',count(*)=2 from public.club_schedule_items where id in(a,b);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 set local role authenticated;
 insert into schedule_results select 'member own table read',count(*)=1 from public.club_schedule_items where id=a;
 insert into schedule_results select 'foreign table hidden',count(*)=0 from public.club_schedule_items where id=b;
 insert into schedule_results select 'own diary view',count(*)=1 from public.club_diary_view where source_id=a;
 insert into schedule_results select 'foreign diary view hidden',count(*)=0 from public.club_diary_view where source_id=b;
 insert into schedule_results select 'own rink view',count(*)=2 from public.rink_usage_view where source_id=a;
 insert into schedule_results select 'foreign rink view hidden',count(*)=0 from public.rink_usage_view where source_id=b;
 denied:=false;
 begin insert into public.club_schedule_items(club_id,title,item_type,activity_type,start_at,end_at) values(c,'Forged','event','test','2030-01-01 12:00Z','2030-01-01 14:00Z'); exception when insufficient_privilege then denied:=true; end;
 insert into schedule_results values('client insert denied',denied);
 denied:=false;
 begin update public.club_schedule_items set title='Forged' where id=a; exception when insufficient_privilege then denied:=true; end;
 insert into schedule_results values('client update denied',denied);
 denied:=false;
 begin delete from public.club_schedule_items where id=a; exception when insufficient_privilege then denied:=true; end;
 insert into schedule_results values('client delete denied',denied);
 reset role;
 -- Being admin of a different club does not permit viewing this club's diary.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_u,'role','authenticated')::text,true);
 set local role authenticated;
 insert into schedule_results select 'foreign admin diary denied',count(*)=0 from public.club_diary_view where source_id=a;
 insert into schedule_results select 'admin own diary',count(*)=1 from public.club_diary_view where source_id=b;
 reset role;
 update public.club_memberships set is_active=false where club_id=other_c and member_profile_id=other_p;
 set local role authenticated;
 insert into schedule_results select 'inactive membership hidden',count(*)=0 from public.club_diary_view where source_id=b;
 reset role;
 -- Multi-club active membership can read both clubs.
 insert into public.club_memberships(club_id,member_profile_id,is_active) values(other_c,p,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 set local role authenticated;
 insert into schedule_results select 'multi-club read',count(*)=2 from public.club_diary_view where source_id in(a,b);
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 foreach v in array array['club_schedule_items','club_diary_view','rink_usage_view'] loop
  denied:=false;
  begin execute format('select count(*) from public.%I',v) into n; exception when insufficient_privilege then denied:=true; end;
  insert into schedule_results values('anonymous denied '||v,denied);
 end loop;
 reset role;
 set local role service_role;
 update public.club_schedule_items set title='Server updated' where id=a;
 get diagnostics n=row_count;
 insert into schedule_results values('server update retained',n=1);
 delete from public.club_schedule_items where id=a;
 get diagnostics n=row_count;
 insert into schedule_results values('server delete retained',n=1);
 reset role;
 insert into schedule_results values('no client truncate',not has_table_privilege('authenticated','public.club_schedule_items','TRUNCATE') and not has_table_privilege('anon','public.club_schedule_items','TRUNCATE'));
 insert into schedule_results values('cron disabled',not exists(select 1 from cron.job where active));
end $test$;
select * from schedule_results order by test;
rollback;
