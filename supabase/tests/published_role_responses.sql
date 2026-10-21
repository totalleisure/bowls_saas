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
 cmd text; member_role text; block jsonb; protocol integer; event text; notification uuid; wrong_sender text; message_id text;
 response_token text := 'RSP-'||repeat('A',48);
 token_hash text := encode(extensions.digest('RSP-'||repeat('A',48),'sha256'),'hex');
begin
 select fx.* into f from public.fixtures fx join public.competition_types ct on ct.id=fx.competition_type_id where fx.cancelled_at is null and fx.archived_at is null and ct.is_internal and ct.selection_mode='preselect' order by fx.created_at desc limit 1;
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


 for member_role in select unnest(array['player','reserve','marker','opponent']) loop
  update public.team_selection_members set role=member_role::public.selection_member_role where id=target;
  delete from public.fixture_rink_assignments where fixture_id=fixture and member_profile_id=member;
  if member_role<>'reserve' then
   insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position)
   values(fixture,rink,member,case member_role when 'marker' then 201 when 'opponent' then 101 else 1 end);
  end if;
  foreach event in array array['fixture_selected','team_published_player','team_published_reserve','acceptance_reminder','fixture_rescheduled_selected'] loop
   foreach cmd in array array['ACCEPT','DECLINE'] loop
    update public.team_selection_members set acceptance='pending',responded_at=null,is_selected=true where id=target;
    insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id,payload,status)
    values(event,captain,member,fixture,selection,jsonb_build_object('fixture_label','Synthetic role test','fixture_date',f.start_at,'start_at',f.start_at,'old_start_at',f.start_at-interval '7 days','new_start_at',f.start_at,'attachments',jsonb_build_array(jsonb_build_object('name','test.pdf','contentType','application/pdf','contentBytes',encode(convert_to('%PDF synthetic rollback test','UTF8'),'base64'),'compositionVersion',(select composition_version from public.team_selections where id=selection)))),'pending')
    returning id into notification;
    perform set_config('app.notification_queue_ids',notification::text,true);
    perform public.process_notification_queue(1); select last_error into wrong_sender from public.notification_queue where id=notification; assert wrong_sender is null,coalesce(wrong_sender,'Notification processing failed');
    select id,payload->'action_block' into queue,block from public.email_queue where fixture_id=fixture and member_profile_id=member and event_type=event order by created_at desc,id desc limit 1;
    -- Resolve the newly created action, rather than relying on timestamp ordering within this transaction.
    select e.id,e.payload->'action_block' into strict queue,block from public.email_queue e
    join public.email_action_requests ar on ar.source_email_queue_id=e.id
    where ar.target_record_id=target and ar.status='pending';
    assert block is not null and jsonb_array_length(block->'actions')=2,'Missing actions for '||member_role||'/'||event;
    select id into strict action from public.email_action_requests where source_email_queue_id=queue;
    update public.email_queue set status='processing' where id=queue;
    assert public.issue_email_action_response_token(action,queue,token_hash),'Token issue failed';
    result:=public.apply_email_action_response(block->>'response_code',cmd,'wrong@example.invalid',response_token,gen_random_uuid()::text,now());
    assert result->>'status'='sender_mismatch',result::text;
    assert exists(select 1 from public.team_selection_members where id=target and acceptance='pending'),'Wrong sender changed selection';
    result:=public.apply_email_action_response(block->>'response_code',cmd,'selection-test@example.invalid','RSP-invalid',gen_random_uuid()::text,now());
    assert result->>'status'='invalid_token',result::text;
    result:=public.apply_email_action_response(block->>'response_code',cmd,'selection-test@example.invalid',response_token,gen_random_uuid()::text,now());
    assert result->>'status'='processed',result::text;
    assert exists(select 1 from public.team_selection_members where id=target and acceptance::text=case cmd when 'ACCEPT' then 'accepted' else 'declined' end),'Wrong assignment response';
    result:=public.apply_email_action_response(block->>'response_code',cmd,'selection-test@example.invalid',response_token,gen_random_uuid()::text,now());
    assert result->>'status'='already_responded',result::text;
   end loop;
  end loop;
  -- Removed and cancelled assignments are ineligible for every role.
  update public.team_selection_members set is_selected=false where id=target;
  assert public.published_assignment_response_type(target) is null,'Removed assignment eligible';
  update public.team_selection_members set is_selected=true where id=target;
  update public.fixtures set cancelled_at=now() where id=fixture;
  assert public.published_assignment_response_type(target) is null,'Cancelled assignment eligible';
  update public.fixtures set cancelled_at=null where id=fixture;
 end loop;
end $test$;
select 'PASS: 40 role/event/action cases through notification queue; wrong sender, invalid token, replay, removal and cancellation' result;
rollback;
