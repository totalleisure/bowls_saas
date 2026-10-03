begin;
set local statement_timeout='25s';
create temp table recipient_results(test text, passed boolean) on commit drop;
grant insert,select on recipient_results to authenticated;
do $$
declare
 c uuid:=gen_random_uuid(); u uuid; ids uuid[]:='{}'; users uuid[]:='{}';
 ct uuid; mp uuid; f uuid; s uuid; r uuid; v uuid; n int; i int;
 old_start timestamptz:=now()+interval '20 days';
 old_end timestamptz:=now()+interval '20 days 2 hours';
begin
 if exists(select 1 from cron.job where active) then raise exception 'Disable cron before test'; end if;
 insert into public.clubs(id,name) values(c,'ROLLBACK move recipients');
 for i in 1..6 loop
   u:=gen_random_uuid(); users:=array_append(users,u);
   insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
   values(u,u::text||'@example.invalid','{"display_name":"Rollback move recipient"}','{}');
   select id into mp from public.member_profiles where user_id=u;
   ids:=array_append(ids,mp);
   insert into public.club_memberships(club_id,member_profile_id,role,is_active)
   values(c,mp,case when i=1 then 'admin'::public.club_role else 'member'::public.club_role end,true);
 end loop;
 insert into public.venues(club_id,name,is_home_venue) values(c,'Rollback move venue',false) returning id into v;
 insert into public.competition_types(club_id,name,is_internal,section,selection_mode,team_selection_enabled) values(c,'Rollback internal preselect',true,'mixed','preselect',true) returning id into ct;
 insert into public.fixtures(competition_type_id,club_id,start_at,end_at,is_home,venue_id,rinks_required,players_per_rink,captain_member_profile_id,vice_captain_member_profile_id)
 values(ct,c,old_start+interval '1 day',old_end+interval '1 day',false,v,1,4,ids[3],ids[1]) returning id into f;
 insert into public.team_selections(fixture_id,status) values(f,'published') returning id into s;
 insert into public.team_selection_members(team_selection_id,member_profile_id,role,is_selected) values
 (s,ids[1],'player',true),(s,ids[2],'reserve',true),(s,ids[3],'reserve',false),
 (s,ids[5],'player',false),(s,ids[6],'player',true);
 insert into public.fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink) values(f,1,'rinks',4) returning id into r;
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position)
 values(f,r,ids[1],1),(f,r,ids[4],201);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
 set local role authenticated;
 n:=public.queue_fixture_moved_notifications(f,old_start,old_end);
 insert into recipient_results values('five unique recipients across roles',n=5);
 n:=public.queue_fixture_moved_notifications(f,old_start,old_end);
 insert into recipient_results values('retry creates no duplicates',n=0);
 reset role;
 insert into recipient_results select 'assigned player and vice captain gets one',count(*)=1 from public.notification_queue where fixture_id=f and event_type='fixture_moved' and target_member_profile_id=ids[1];
 insert into recipient_results select 'selected reserve included',count(*)=1 from public.notification_queue where fixture_id=f and event_type='fixture_moved' and target_member_profile_id=ids[2];
 insert into recipient_results select 'captain included despite no longer selected',count(*)=1 from public.notification_queue where fixture_id=f and event_type='fixture_moved' and target_member_profile_id=ids[3];
 insert into recipient_results select 'assigned marker included',count(*)=1 from public.notification_queue where fixture_id=f and event_type='fixture_moved' and target_member_profile_id=ids[4];
 insert into recipient_results select 'dropped player excluded',count(*)=0 from public.notification_queue where fixture_id=f and event_type='fixture_moved' and target_member_profile_id=ids[5];
 insert into recipient_results select 'selected unpositioned player included',count(*)=1 from public.notification_queue where fixture_id=f and event_type='fixture_moved' and target_member_profile_id=ids[6];
 update public.team_selections set status='draft' where id=s;
 set local role authenticated;
 n:=public.queue_fixture_moved_notifications(f,old_start+interval '2 days',old_end+interval '2 days');
 insert into recipient_results values('unpublished roster adds no recipients beyond assignments and leaders',n=3);
 reset role;
 insert into recipient_results select 'messages use current new time',bool_and((payload->>'new_start_at')::timestamptz=old_start+interval '1 day') from public.notification_queue where fixture_id=f and event_type='fixture_moved';
 if exists(select 1 from recipient_results where not passed) then raise exception 'Recipient coverage checks failed'; end if;
end $$;
select * from recipient_results order by test;
rollback;
