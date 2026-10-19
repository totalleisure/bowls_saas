begin;
do $test$
declare
 f public.fixtures%rowtype;
 fixture uuid:=extensions.gen_random_uuid();
 member uuid:=extensions.gen_random_uuid();
 captain uuid:=extensions.gen_random_uuid();
 selection uuid:=extensions.gen_random_uuid();
 target uuid:=extensions.gen_random_uuid();
 rink uuid:=extensions.gen_random_uuid();
 queue uuid:=extensions.gen_random_uuid();
 action uuid:=extensions.gen_random_uuid();
 result jsonb;
 first_reply uuid;
 n integer;
 captain_user uuid;
 cmd text; member_role text; block jsonb;
 pool uuid:=extensions.gen_random_uuid();
 reserve_member uuid:=extensions.gen_random_uuid();
 replacement uuid; new_selection uuid;
 response_token text := 'RSP-'||repeat('A',48);
 token_hash text := encode(extensions.digest('RSP-'||repeat('A',48),'sha256'),'hex');
begin
 select * into f from public.fixtures where cancelled_at is null and archived_at is null order by created_at desc limit 1;
 if f.id is null then raise exception 'No fixture template'; end if;
 insert into auth.users(id,email) values(member,'selection-test@example.invalid'),(captain,'captain-test@example.invalid');
 select id into member from public.member_profiles where user_id=member;
 select id into captain from public.member_profiles where user_id=captain;
 update public.member_profiles set display_name='Synthetic reply member',email_address='selection-test@example.invalid' where id=member;
 update public.member_profiles set display_name='Synthetic captain',email_address='captain-test@example.invalid' where id=captain;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(f.club_id,member,'member',true),(f.club_id,captain,'admin',true);
 f.team_id:=null; f.is_home:=false; f.green_area_id:=null; f.requires_rsvp:=true;
 f.id:=fixture; f.start_at:=now()+interval '10 years'; f.end_at:=f.start_at+interval '2 hours';
 f.captain_member_profile_id:=captain; f.vice_captain_member_profile_id:=null;
 f.rescheduled_to_fixture_id:=null; f.rescheduled_from_fixture_id:=null;
 f.last_team_sheet_emailed_at:=null; f.last_team_sheet_emailed_by:=null;
 insert into public.fixtures select f.*;
 insert into public.team_selections(id,fixture_id,status,captain_member_profile_id) values(selection,fixture,'published',captain);
 insert into public.team_selection_members(id,team_selection_id,member_profile_id,role,acceptance,is_selected) values(target,selection,member,'player','pending',true);
 insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink) values(rink,fixture,1,'singles',1);
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(fixture,rink,member,1);

 -- Add an accepted reserve and an available, unselected pool member.
 insert into auth.users(id,email) values(pool,'pool-test@example.invalid'),(reserve_member,'reserve-test@example.invalid');
 select id into pool from public.member_profiles where user_id=pool;
 select id into reserve_member from public.member_profiles where user_id=reserve_member;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active)
 values(f.club_id,pool,'member',true),(f.club_id,reserve_member,'member',true);
 insert into public.team_selection_members(team_selection_id,member_profile_id,role,acceptance,is_selected)
 values(selection,reserve_member,'reserve','accepted',true),
       (selection,captain,'reserve','accepted',true),
       (selection,pool,'player','pending',false);
 update public.team_selection_members set acceptance='accepted' where id=target;
 insert into public.fixture_rsvps(fixture_id,member_profile_id,status)
 values(fixture,pool,'yes'),(fixture,member,'yes'),(fixture,reserve_member,'yes');
 update public.fixtures set cancelled_at=now() where id=fixture;
 select user_id into captain_user from public.member_profiles where id=captain;
 perform set_config('request.jwt.claim.sub',captain_user::text,true);
 replacement:=public.reschedule_cancelled_fixture_safe(fixture,f.start_at+interval '7 days',f.end_at+interval '7 days');
 select id into strict new_selection from public.team_selections where fixture_id=replacement;
 assert not exists(select 1 from public.fixture_rsvps where fixture_id=replacement),'Old availability copied to new date';
 assert (select count(*)=3 from public.team_selection_members where team_selection_id=new_selection and is_selected and acceptance='pending'),'Selection responses not reset';
 assert (select count(*)=3 from public.team_selection_members where team_selection_id=selection and is_selected and acceptance='accepted'),'Original responses changed';
 assert (select count(*)=4 from public.notification_queue where fixture_id=replacement),'Expected exactly one notification per recipient';
 assert (select count(*)=3 from public.notification_queue where fixture_id=replacement and event_type='fixture_rescheduled_selected'),'Selected player/reserve/captain need selection request';
 assert exists(select 1 from public.notification_queue where fixture_id=replacement and target_member_profile_id=pool and event_type='fixture_rescheduled_availability'),'Pool member needs availability';
 -- Respond to each carried-forward selection through the real email action API.
 for member in select member_profile_id from public.team_selection_members where team_selection_id=new_selection and is_selected loop
  select id into target from public.team_selection_members where team_selection_id=new_selection and member_profile_id=member;
  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
  values(member,'fixture_rescheduled_selected','selection-test@example.invalid','Rescheduled test','Test',replacement,new_selection) returning id into queue;
  select payload->'action_block' into block from public.email_queue where id=queue;
  assert jsonb_array_length(block->'actions')=2,'Missing selection actions';
  select id into strict action from public.email_action_requests where source_email_queue_id=queue;
  update public.email_queue set status='processing' where id=queue;
  assert public.issue_email_action_response_token(action,queue,token_hash),'Token issue failed';
  result:=public.apply_email_action_response(block->>'response_code','ACCEPT','selection-test@example.invalid',response_token,gen_random_uuid()::text,now());
  assert result->>'status'='processed',result::text;
  assert exists(select 1 from public.team_selection_members where id=target and acceptance='accepted'),'Acceptance missing';
 end loop;
 -- Pool member gives availability first. This must not accept a team place.
 insert into public.fixture_rsvps(fixture_id,member_profile_id,status) values(replacement,pool,'yes');
 assert exists(select 1 from public.team_selection_members where team_selection_id=new_selection and member_profile_id=pool and not is_selected and acceptance='pending'),'Availability accepted a place';
 -- Captain subsequently selects the member as a player in a new rink.
 update public.team_selection_members set is_selected=true where team_selection_id=new_selection and member_profile_id=pool;
 rink:=extensions.gen_random_uuid();
 insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink) values(rink,replacement,2,'singles',1);
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(replacement,rink,pool,1);
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id,attachments)
 values(pool,'team_published_player','pool-test@example.invalid','Selected test','Test',replacement,new_selection,
 jsonb_build_array(jsonb_build_object('contentType','application/pdf','contentBytes',encode(convert_to('%PDF synthetic rollback fixture','UTF8'),'base64'),'compositionVersion',(select composition_version from public.team_selections where id=new_selection)))) returning id into queue;
 select payload->'action_block' into block from public.email_queue where id=queue;
 assert jsonb_array_length(block->'actions')=2,'Later selection missing acceptance actions';
 select id into strict action from public.email_action_requests where source_email_queue_id=queue;
 update public.email_queue set status='processing' where id=queue;
 assert public.issue_email_action_response_token(action,queue,token_hash),'Later token failed';
 result:=public.apply_email_action_response(block->>'response_code','ACCEPT','pool-test@example.invalid',response_token,gen_random_uuid()::text,now());
 assert result->>'status'='processed',result::text;
 assert (select count(*)=4 from public.team_selection_members where team_selection_id=new_selection and is_selected and acceptance='accepted'),'Other acceptances changed';
end $test$;
select 'PASS: four reschedule response scenarios, selected captain, unchanged original responses' result;
rollback;
