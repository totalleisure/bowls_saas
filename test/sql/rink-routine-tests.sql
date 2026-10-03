begin;
set local statement_timeout='25s';
create temp table rink_access_results(test text,passed boolean) on commit drop;
grant insert,select on rink_access_results to authenticated,anon,service_role;
do $$
declare
 g uuid; f uuid; c uuid; other_c uuid:=gen_random_uuid(); rink uuid;
 users uuid[]:=array[]::uuid[]; profiles uuid[]:=array[]::uuid[]; u uuid; p uuid;
 i integer; n integer; denied boolean; op text; before_count integer; expected integer;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Disable cron'; end if;
 select fx.id,fx.green_area_id,ga.club_id into f,g,c from public.fixtures fx join public.green_areas ga on ga.id=fx.green_area_id limit 1;
 if f is null then raise exception 'Fixture with green required'; end if;
 insert into public.clubs(id,name) values(other_c,'ROLLBACK rink permissions');
 for i in 1..5 loop
  u:=gen_random_uuid(); users:=array_append(users,u);
  insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
  values(u,u::text||'@example.invalid','{"display_name":"Rink routine test"}','{}');
  select id into p from public.member_profiles where user_id=u;
  profiles:=array_append(profiles,p);
  insert into public.club_memberships(club_id,member_profile_id,role,is_active)
   values(case when i=4 then other_c else c end,p,case when i=2 then 'member'::public.club_role else 'admin'::public.club_role end,i<>3);
 end loop;
 insert into public.app_superusers(user_id) values(users[5]);
 insert into public.fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label)
 values(f,9998,'singles',1,'ROLLBACK-old') returning id into rink;
 for i in 1..5 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[i],'role','authenticated')::text,true);
  set local role authenticated;
  denied:=false; n:=0;
  begin n:=public.remap_green_rink_labels(g,array['ROLLBACK-old'],array['ROLLBACK-new']);
  exception when insufficient_privilege then denied:=true; end;
  insert into rink_access_results values('actor '||i||' remap permission',case when i in(1,5) then not denied and n=1 else denied end);
  denied:=false;
  begin perform public.queue_fixture_selected_notifications(f); exception when insufficient_privilege then denied:=true; end;
  insert into rink_access_results values('actor '||i||' legacy notification denied',denied);
  reset role;
  update public.fixture_rinks set home_rink_label='ROLLBACK-old' where id=rink;
 end loop;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 denied:=false;
 begin perform public.remap_green_rink_labels(g,array['ROLLBACK-old'],array['ROLLBACK-new']); exception when insufficient_privilege then denied:=true; end;
 insert into rink_access_results values('anonymous remap denied',denied);
 denied:=false;
 begin perform public.queue_fixture_selected_notifications(f); exception when insufficient_privilege then denied:=true; end;
 insert into rink_access_results values('anonymous queue denied',denied);
 reset role;
 select count(*) into before_count from public.notification_queue;
 select count(*) into expected from public.fixture_rink_assignments where fixture_id=f;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 set local role service_role;
 n:=public.remap_green_rink_labels(g,array['ROLLBACK-old'],array['ROLLBACK-server']);
 insert into rink_access_results values('server remap allowed',n=1);
 n:=public.queue_fixture_selected_notifications(f);
 insert into rink_access_results values('server legacy queue allowed',n=expected);
 insert into rink_access_results select 'server queue inserts match assignments',count(*)=before_count+expected from public.notification_queue;
 reset role;
 insert into rink_access_results values('cron still disabled',not exists(select 1 from cron.job where active));
 if exists(select 1 from rink_access_results where not passed) then raise exception 'Rink routine tests failed'; end if;
end $$;
select * from rink_access_results;
rollback;
