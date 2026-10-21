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
 cmd text; member_role text; block jsonb; protocol integer; event text; notification uuid; opponent uuid:=gen_random_uuid(); marker uuid:=gen_random_uuid(); attachment jsonb; wrong_sender text; message_id text;
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
 f.players_per_rink:=1; f.team_id:=null; f.is_home:=false; f.green_area_id:=null; f.id:=fixture; f.start_at:=now()+interval '10 years'; f.end_at:=f.start_at+interval '2 hours';
 f.captain_member_profile_id:=captain; f.vice_captain_member_profile_id:=null;
 f.rescheduled_to_fixture_id:=null; f.rescheduled_from_fixture_id:=null;
 f.last_team_sheet_emailed_at:=null; f.last_team_sheet_emailed_by:=null;
 insert into public.fixtures select f.*;

 insert into auth.users(id,email) values(opponent,'opponent-test@example.invalid'),(marker,'marker-test@example.invalid');
 select id into opponent from public.member_profiles where user_id=opponent;
 select id into marker from public.member_profiles where user_id=marker;
 update public.member_profiles set email_address='opponent-test@example.invalid' where id=opponent;
 update public.member_profiles set email_address='marker-test@example.invalid' where id=marker;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(f.club_id,opponent,'member',true),(f.club_id,marker,'member',true);
 insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink) values(rink,fixture,1,'singles',1);
 select user_id into captain_user from public.member_profiles where id=captain;
 perform set_config('request.jwt.claim.sub',captain_user::text,true);
 result:=public.save_preselect_fixture_state(fixture,jsonb_build_array(
  jsonb_build_object('fixture_rink_id',rink,'position',1,'member_profile_id',member),
  jsonb_build_object('fixture_rink_id',rink,'position',101,'member_profile_id',opponent),
  jsonb_build_object('fixture_rink_id',rink,'position',201,'member_profile_id',marker)));
 select id into strict selection from public.team_selections where fixture_id=fixture and status='published';
 assert (select count(*)=3 from public.team_selection_members where team_selection_id=selection and is_selected),'Auto-publish role count';
 assert (select count(distinct target_member_profile_id)=3 from public.notification_queue where fixture_id=fixture and event_type='fixture_selected'),'Preselect did not notify all three roles';
 -- Attach through the same API used after saving the auto-published team.
 select jsonb_build_object('name','test.pdf','contentType','application/pdf','contentBytes',encode(convert_to('%PDF synthetic rollback test','UTF8'),'base64'),'compositionVersion',composition_version) into attachment from public.team_selections where id=selection;
 perform public.attach_publication_team_sheet(fixture,selection,(attachment->>'compositionVersion')::int,attachment);
 perform set_config('app.notification_queue_ids',(select string_agg(id::text,',') from public.notification_queue where fixture_id=fixture),true);
 perform public.process_notification_queue(100);
 assert not exists(select 1 from public.notification_queue where fixture_id=fixture and status='failed'),'Preselect notification failed';
 assert (select count(*)=3 from public.email_action_requests where fixture_id=fixture and status='pending'),'Preselect missing actions';
 for target,member in select id,member_profile_id from public.team_selection_members where team_selection_id=selection and is_selected loop
  select e.id,e.payload->'action_block' into strict queue,block from public.email_queue e join public.email_action_requests a on a.source_email_queue_id=e.id where a.target_record_id=target and a.status='pending';
  select id into action from public.email_action_requests where source_email_queue_id=queue;
  update public.email_queue set status='processing' where id=queue;
  assert public.issue_email_action_response_token(action,queue,token_hash),'Token issue';
  result:=public.apply_email_action_response(block->>'response_code','ACCEPT',(select email_address from public.member_profiles where id=member),response_token,gen_random_uuid()::text,now());
  assert result->>'status'='processed',result::text;
 end loop;
 assert (select count(*)=3 from public.team_selection_members where team_selection_id=selection and acceptance='accepted'),'Preselect acceptances missing';
 -- Explicit publication also includes assigned markers and member opponents.
 perform public.queue_team_publication_communications(fixture,selection,false);
 assert (select count(distinct target_member_profile_id)=3 from public.notification_queue where fixture_id=fixture and event_type='team_published_player'),'Publication omits marker/opponent';
end $test$;
select 'PASS: actual Pre-select save auto-publishes, queues player/opponent/marker emails, attaches PDF, processes all three Accepts; explicit publication includes all three' result;
rollback;
