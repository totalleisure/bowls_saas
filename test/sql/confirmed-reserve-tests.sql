begin;
set local statement_timeout='25s';
create temp table reserve_results(test text,passed boolean) on commit drop;
do $test$
declare
 f uuid := '0787fdcf-2e9f-432e-9215-6ea184a7e3b0';
 s uuid := '9e4386cc-e0cd-4582-ae9f-f80ef37c33bb';
 m uuid := '5e6a6ab9-3130-4488-8860-6af7cd3f2621';
 actor uuid;
 r uuid;
 ver integer;
 members jsonb;
 assignments jsonb;
 result jsonb;
 nid uuid;
 attachment jsonb;
 n integer;
 before_count integer;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must be inactive'; end if;
 select user_id into actor from public.member_profiles where id='42acb093-02d8-47cc-a43e-292bfa6cf17a';
 select id into r from public.fixture_rinks where fixture_id=f and fixture_rink_no=2;
 select composition_version into ver from public.team_selections where id=s;
 -- Restore just this player's pre-change state inside this rolled-back test.
 update public.team_selection_members set role='player' where team_selection_id=s and member_profile_id=m;
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(f,r,m,2);
 select jsonb_agg(jsonb_build_object('member_profile_id',member_profile_id,'role',case when member_profile_id=m then 'reserve' else role::text end,'is_selected',true))
 into members from public.team_selection_members where team_selection_id=s and is_selected and role in ('player','reserve');
 select coalesce(jsonb_agg(jsonb_build_object('fixture_rink_id',fixture_rink_id,'member_profile_id',member_profile_id,'position',position)),'[]') into assignments
 from public.fixture_rink_assignments where fixture_id=f and member_profile_id<>m and position<100;
 select count(*) into before_count from public.notification_queue;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 set local role authenticated;
 result := public.confirm_team_changes(s,ver,members,assignments);
 reset role;
 insert into reserve_results values('one reserve communication reported',(result->>'communications_queued')::integer=1);
 insert into reserve_results select 'one event only, no dropped-player event',count(*)=before_count+1 from public.notification_queue;
 select id into nid from public.notification_queue where team_selection_id=s and target_member_profile_id=m and event_type='team_published_reserve' order by created_at desc limit 1;
 insert into reserve_results values('reserve event exists',nid is not null);
 insert into reserve_results select 'reserve message requires new PDF',payload->>'team_sheet_required'='true' and not(payload ? 'attachments') from public.notification_queue where id=nid;
 insert into reserve_results select 'final reserve has no player position',role='reserve' and not exists(select 1 from public.fixture_rink_assignments where fixture_id=f and member_profile_id=m) from public.team_selection_members where team_selection_id=s and member_profile_id=m;
 set local role authenticated;
 result := public.confirm_team_changes(s,ver+1,members,assignments);
 reset role;
 insert into reserve_results values('identical retry is no-op',result->>'no_change'='true');
 insert into reserve_results select 'retry does not duplicate',count(*)=before_count+1 from public.notification_queue;
 perform set_config('app.notification_queue_ids',nid::text,true);
 n:=public.process_notification_queue(1);
 insert into reserve_results values('missing PDF blocks processing',n=0);
 insert into reserve_results select 'blocked with attachment error',status='failed' and last_error='Required Team Sheet attachment is missing or stale.' from public.notification_queue where id=nid;
 attachment:=jsonb_build_object('name','rollback-test.pdf','contentType','application/pdf','contentBytes',encode(convert_to('%PDF-1.4 rollback test','UTF8'),'base64'),'compositionVersion',ver+1);
 set local role authenticated;
 perform public.attach_publication_team_sheet(f,s,ver+1,attachment);
 reset role;
 insert into reserve_results select 'attachment repairs failed reserve event',status='pending' and payload->>'team_sheet_composition_version'=(ver+1)::text from public.notification_queue where id=nid;
 n:=public.process_notification_queue(1);
 insert into reserve_results values('processor creates communication after PDF',n=1);
 insert into reserve_results select 'in-app reserve message generated',exists(select 1 from public.app_notifications where fixture_id=f and member_profile_id=m and type='team_published_reserve' and body like 'You have been selected as a reserve%' and created_at=now());
 insert into reserve_results select 'email includes current PDF',exists(select 1 from public.email_queue where fixture_id=f and member_profile_id=m and event_type='team_published_reserve' and attachments=jsonb_build_array(attachment) and created_at=now());
 n:=public.process_notification_queue(1);
 insert into reserve_results values('processor retry does not reprocess',n=0);
end;
$test$;
select * from reserve_results;
rollback;
