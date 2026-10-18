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
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(f.club_id,member,'member',true),(f.club_id,captain,'member',true);
 f.id:=fixture; f.start_at:=now()+interval '10 years'; f.end_at:=f.start_at+interval '2 hours';
 f.captain_member_profile_id:=captain; f.vice_captain_member_profile_id:=null;
 f.rescheduled_to_fixture_id:=null; f.rescheduled_from_fixture_id:=null;
 f.last_team_sheet_emailed_at:=null; f.last_team_sheet_emailed_by:=null;
 insert into public.fixtures select f.*;
 insert into public.team_selections(id,fixture_id,status,captain_member_profile_id) values(selection,fixture,'published',captain);
 insert into public.team_selection_members(id,team_selection_id,member_profile_id,role,acceptance,is_selected) values(target,selection,member,'player','pending',true);
 insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink) values(rink,fixture,1,'singles',1);
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(fixture,rink,member,1);

 for member_role in select unnest(array['player','reserve']) loop
  update public.team_selection_members set role=case when member_role='player' then 'player'::public.selection_member_role else 'reserve'::public.selection_member_role end where id=target;
  for cmd in select unnest(array['ACCEPT','DECLINE']) loop
   update public.team_selection_members set acceptance='pending',responded_at=null where id=target;
   queue:=extensions.gen_random_uuid();
   insert into public.email_queue(id,member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
   values(queue,member,'fixture_rescheduled_selected','selection-test@example.invalid','Rescheduled test','Test',fixture,selection);
   select payload->'action_block' into block from public.email_queue where id=queue;
   assert block->>'version'='2' and jsonb_array_length(block->'actions')=2,'Missing secure response buttons';
   select id into strict action from public.email_action_requests where source_email_queue_id=queue and fixture_id=fixture and target_record_id=target;
   update public.email_queue set status='processing' where id=queue;
   assert public.issue_email_action_response_token(action,queue,token_hash),'Token issue failed';
   result:=public.apply_email_action_response(block->>'response_code',cmd,'selection-test@example.invalid',response_token,gen_random_uuid()::text,now());
   assert result->>'status'='processed',result::text;
   assert exists(select 1 from public.team_selection_members where id=target and acceptance::text=case when cmd='ACCEPT' then 'accepted' else 'declined' end),'Wrong response target';
  end loop;
 end loop;
 update public.fixtures set cancelled_at=now() where id=fixture;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
 values(member,'fixture_rescheduled_selected','selection-test@example.invalid','Cancelled test','Test',fixture,selection) returning id into queue;
 assert not exists(select 1 from public.email_action_requests where source_email_queue_id=queue),'Cancelled fixture received actions';
end $test$;
select 'PASS: rescheduled player and reserve Accept/Decline target replacement; cancelled target refused' result;
rollback;
