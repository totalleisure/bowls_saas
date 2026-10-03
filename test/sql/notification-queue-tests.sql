begin;
set local statement_timeout='30s';
create temp table nq_results(test text,passed boolean) on commit drop;
grant insert,select on nq_results to authenticated,anon,service_role;
do $test$
declare
 users uuid[]:=array[]::uuid[]; profiles uuid[]:=array[]::uuid[];
 roles text[]:=array['admin','selector','member','member','member','guest'];
 c uuid; f uuid; s uuid; rink uuid; foreign_c uuid:=gen_random_uuid();
 u uuid; p uuid; i integer; denied boolean; evt text; q uuid; n integer; op text;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Disable cron before test'; end if;
 select ts.fixture_id,ts.id,fx.club_id into f,s,c from public.team_selections ts join public.fixtures fx on fx.id=ts.fixture_id limit 1;
 if f is null then raise exception 'Fixture setup required'; end if;
 insert into public.clubs(id,name) values(foreign_c,'ROLLBACK notification club');
 for i in 1..7 loop
  u:=gen_random_uuid(); users:=array_append(users,u);
  insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
   values(u,u::text||'@example.invalid','{"display_name":"Notification queue test"}','{}');
  select id into p from public.member_profiles where user_id=u;
  profiles:=array_append(profiles,p);
  insert into public.club_memberships(club_id,member_profile_id,role,is_active)
   values(case when i=7 then foreign_c else c end,p,coalesce(roles[i],'member')::public.club_role,true);
 end loop;
 update public.fixtures set captain_member_profile_id=profiles[3],vice_captain_member_profile_id=profiles[4] where id=f;
 insert into public.team_selection_members(team_selection_id,member_profile_id,role,acceptance)
 values(s,profiles[5],'player','pending');
 insert into public.fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink)
 values(f,9999,'singles',1) returning id into rink;
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position)
 values(f,rink,profiles[5],1);
 for i in 1..7 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[i],'role','authenticated')::text,true);
  set local role authenticated;
  foreach evt in array array['fixture_message','acceptance_reminder','fixture_selected'] loop
   denied:=false;
   begin
    insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id,payload,status)
    values(evt,profiles[i],profiles[5],f,s,'{}','pending');
   exception when insufficient_privilege then denied:=true; end;
   insert into nq_results values('actor '||i||' '||evt,denied = not(i<=4 or (i=5 and evt='fixture_selected')));
  end loop;
  reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
 set local role authenticated;
 insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,payload,status)
 values('guest_membership_approved',profiles[1],profiles[5],jsonb_build_object('club_id',c),'pending');
 insert into nq_results values('admin guest approval allowed',true);
 foreach op in array array[
  format('insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id) values(''fixture_message'',%L,%L,%L,%L)',profiles[2],profiles[5],f,s),
  format('insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id) values(''fixture_message'',%L,%L,%L,%L)',profiles[1],profiles[7],f,s),
  format('insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id) values(''fixture_message'',%L,%L,%L,%L)',profiles[1],profiles[5],f,gen_random_uuid()),
  format('insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,status) values(''fixture_message'',%L,%L,%L,''processed'')',profiles[1],profiles[5],f),
  format('insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id) values(''team_published_player'',%L,%L,%L)',profiles[1],profiles[5],f),
  'select count(*) from public.notification_queue',
  'update public.notification_queue set attempts=attempts where false',
  'delete from public.notification_queue where false'
 ] loop
  denied:=false;
  begin execute op; exception when insufficient_privilege then denied:=true; end;
  insert into nq_results values('forged/read/write denial '||left(op,110),denied);
 end loop;
 reset role;
 update public.club_memberships set is_active=false where club_id=c and member_profile_id=profiles[1];
 set local role authenticated;
 denied:=false;
 begin insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id)
 values('fixture_message',profiles[1],profiles[5],f,s); exception when insufficient_privilege then denied:=true; end;
 insert into nq_results values('inactive admin denied',denied);
 reset role;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 denied:=false;
 begin insert into public.notification_queue(event_type) values('fixture_message'); exception when insufficient_privilege then denied:=true; end;
 insert into nq_results values('anonymous insert denied',denied);
 reset role;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 set local role service_role;
 insert into public.notification_queue(event_type,status) values('rollback_test','failed') returning id into q;
 update public.notification_queue set attempts=1 where id=q;
 insert into nq_results select 'server CRUD',attempts=1 from public.notification_queue where id=q;
 delete from public.notification_queue where id=q;
 reset role;
 insert into nq_results values('client worker columns denied',not has_column_privilege('authenticated','public.notification_queue','recipient_email','INSERT') and not has_column_privilege('authenticated','public.notification_queue','attempts','INSERT'));
 insert into nq_results values('cron remains disabled',not exists(select 1 from cron.job where active));
 if exists(select 1 from nq_results where not passed) then raise exception 'Notification queue tests failed'; end if;
end $test$;
select * from nq_results order by test;
rollback;
