begin;
create temp table reply_test_preview(subject text,body text) on commit drop;
create temp table reply_test_results(test text,passed boolean) on commit drop;
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
begin
 -- Transaction rolls back every fixture, notification and queue entry before any worker can see them.
 select * into f from public.fixtures where cancelled_at is null and archived_at is null order by created_at desc limit 1;
 if f.id is null then raise exception 'No fixture template'; end if;
 insert into auth.users(id,email) values(member,'selection-test@example.invalid'),(captain,'captain-test@example.invalid');
 select id into member from public.member_profiles where user_id=member;
 select id into captain from public.member_profiles where user_id=captain;
 update public.member_profiles set display_name='Synthetic reply member',email_address='selection-test@example.invalid' where id=member;
 update public.member_profiles set display_name='Synthetic captain',email_address='captain-test@example.invalid' where id=captain;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(f.club_id,member,'member',true),(f.club_id,captain,'member',true);
 f.team_name:='TEST - Captain reply email';
 f.id:=fixture; f.start_at:=now()+interval '10 days'; f.end_at:=f.start_at+interval '2 hours';
 f.captain_member_profile_id:=captain; f.vice_captain_member_profile_id:=null;
 f.is_home:=false; f.green_area_id:=null; f.rescheduled_to_fixture_id:=null; f.rescheduled_from_fixture_id:=null;
 f.last_team_sheet_emailed_at:=null; f.last_team_sheet_emailed_by:=null;
 insert into public.fixtures select f.*;
 insert into public.team_selections(id,fixture_id,status,captain_member_profile_id) values(selection,fixture,'published',captain);
 insert into public.team_selection_members(id,team_selection_id,member_profile_id,role,acceptance,is_selected) values(target,selection,member,'player','pending',true);
 insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink) values(rink,fixture,1,'singles',1);
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(fixture,rink,member,1);
 insert into public.email_queue(id,member_profile_id,event_type,recipient_email,subject,body,payload,status,sent_at) values(queue,member,'synthetic_written_reply_test','selection-test@example.invalid','Synthetic selection','Synthetic','{}','sent',now()-interval '10 minutes');
 insert into public.email_action_requests(id,club_id,member_profile_id,recipient_email,action_type,target_record_id,fixture_id,team_selection_id,source_email_queue_id,allowed_actions,response_code_hash,expires_at,created_at)
 values(action,f.club_id,member,'selection-test@example.invalid','team_selection',target,fixture,selection,queue,array['ACCEPT','DECLINE'],encode(extensions.digest('BWL-000000000001','sha256'),'hex'),now()+interval '1 day',now()-interval '10 minutes');
 insert into public.email_written_reply_settings(mailbox,enabled,enabled_at,reminder_recipients) values('test@example.invalid',true,now()-interval '1 minute',array['selection-test@example.invalid'])
 on conflict(mailbox) do update set enabled=excluded.enabled,enabled_at=excluded.enabled_at,reminder_recipients=excluded.reminder_recipients;
 result:=public.claim_written_selection_reply('test@example.invalid','<old@test>','old',now()-interval '1 hour','BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('historical mail ignored',result->>'status'='ignored');
 result:=public.claim_written_selection_reply('test@example.invalid','<wrong@test>','wrong',now(),'BWL-000000000001','other@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('wrong sender cannot claim',result->>'status'='recipient_not_enabled');
 result:=public.claim_written_selection_reply('test@example.invalid','<support@test>','support',now(),'BWL-000000000001','selection-test@example.invalid','Support enquiry','Thanks');
 insert into reply_test_results values('support subject cannot claim',result->>'status'='selection_not_pending');
 set local role service_role;
 result:=public.claim_written_selection_reply('test@example.invalid','<one@test>','one',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks, I can play');
 reset role;
 insert into reply_test_results values('service worker records and claims reminder',result->>'status'='recorded' and result->>'send_reminder'='true');
 first_reply:=(result->>'reply_id')::uuid;
 insert into reply_test_results select 'captain receives visible notification',exists(select 1 from public.app_notifications where member_profile_id=captain and data->>'written_reply_id'=first_reply::text and body like '%Thanks, I can play%');

 insert into reply_test_results select 'captain email contains reply and fixture details',
   count(*)=1 and bool_and(recipient_email='captain-test@example.invalid'
     and body like '%Thanks, I can play%' and body like '%TEST - Captain reply email%'
     and body like '%When:%' and body like '%Venue:%'
     and body like '%still pending when this reply was processed%')
 from public.email_queue where event_type='selection_written_reply_review' and payload->>'written_reply_id'=first_reply::text;
 insert into reply_test_preview select subject,body from public.email_queue
 where event_type='selection_written_reply_review' and payload->>'written_reply_id'=first_reply::text;
 select user_id into captain_user from public.member_profiles where id=captain;
 perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',captain_user)::text,true);
 set local role authenticated;
 select count(*) into n from public.app_notifications where data->>'written_reply_id'=first_reply::text;
 reset role;
 insert into reply_test_results values('RLS captain sees exactly their own notification',n=1);
 perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select user_id from public.member_profiles where id=member))::text,true);
 set local role authenticated;
 select count(*) into n from public.app_notifications where data->>'written_reply_id'=first_reply::text;
 reset role;
 insert into reply_test_results values('RLS member cannot read organiser notification',n=0);
 perform set_config('request.jwt.claims','{}',true);
 result:=public.claim_written_selection_reply('test@example.invalid','<one@test>','moved-graph-id',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('same internet message deduplicates across Graph IDs',result->>'status'='duplicate');

 insert into reply_test_results select 'duplicate inbound message does not queue another captain email',count(*)=1
 from public.email_queue where event_type='selection_written_reply_review' and payload->>'written_reply_id'=first_reply::text;
 result:=public.claim_written_selection_reply('test@example.invalid','<two@test>','two',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Another written reply');
 insert into reply_test_results values('second written reply never resends reminder',result->>'status'='recorded' and result->>'send_reminder'='false');
 insert into reply_test_results select 'acceptance stays pending',acceptance='pending' and responded_at is null from public.team_selection_members where id=target;
 insert into reply_test_results select 'request stays pending',status='pending' and last_action is null from public.email_action_requests where id=action;
 insert into reply_test_results select 'only one durable reminder',count(*)=1 from public.email_written_reply_reminders where target_record_id=target;

 insert into reply_test_results select 'new written reply queues its own captain review email',count(*)=2
 from public.email_queue where event_type='selection_written_reply_review' and fixture_id=fixture;
 update public.fixtures set captain_member_profile_id=null,vice_captain_member_profile_id=captain where id=fixture;
 update public.team_selections set captain_member_profile_id=null where id=selection;
 result:=public.claim_written_selection_reply('test@example.invalid','<vice@test>','vice',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Please review BWL-000000000001');
 insert into reply_test_results select 'vice captain fallback and response credential redaction',count(*)=1 and bool_and(body like '%[response reference]%' and body not like '%BWL-000000000001%')
 from public.email_queue where event_type='selection_written_reply_review' and payload->>'written_reply_id'=result->>'reply_id'
 and member_profile_id=captain;
 -- General availability needs no per-address maintenance, but is Club-scoped.
 update public.email_written_reply_settings set sender_scope='active_members',reminder_recipients='{}' where mailbox='test@example.invalid';
 result:=public.claim_written_selection_reply('test@example.invalid','<active-member@test>','active-member',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Please review my reply');
 insert into reply_test_results values('active member is captured without allowlisting',result->>'status'='recorded');
 update public.club_memberships set is_active=false where club_id=f.club_id and member_profile_id=member;
 result:=public.claim_written_selection_reply('test@example.invalid','<inactive@test>','inactive',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('inactive member cannot use production scope',result->>'status'='recipient_not_enabled');
 update public.club_memberships set is_active=true,role='guest' where club_id=f.club_id and member_profile_id=member;
 result:=public.claim_written_selection_reply('test@example.invalid','<guest@test>','guest',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('guest cannot use production scope',result->>'status'='recipient_not_enabled');
 update public.club_memberships set role='member' where club_id=f.club_id and member_profile_id=member;
 update public.member_profiles set email_address='changed@example.invalid' where id=member;
 result:=public.claim_written_selection_reply('test@example.invalid','<stale-email@test>','stale-email',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('current member email must match original recipient',result->>'status'='recipient_not_enabled');
 update public.member_profiles set email_address='selection-test@example.invalid' where id=member;
 update public.team_selection_members set role='reserve' where id=target;
 delete from public.fixture_rink_assignments where fixture_id=fixture and member_profile_id=member;
 result:=public.claim_written_selection_reply('test@example.invalid','<reserve@test>','reserve',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Available as reserve');
 insert into reply_test_results values('published pending reserve does not need a rink assignment',result->>'status'='recorded');
 update public.team_selection_members set role='player' where id=target;
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(fixture,rink,member,1);
 update public.email_action_requests set response_protocol_version=2,response_token_hash=repeat('a',64) where id=action;
 result:=public.claim_written_selection_reply('test@example.invalid','<bad-token@test>','bad-token',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks',repeat('b',64));
 insert into reply_test_results values('production scope does not bypass response-token validation',result->>'status'='invalid_response_credentials');
 result:=public.claim_written_selection_reply('test@example.invalid','<good-token@test>','good-token',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks',repeat('a',64));
 insert into reply_test_results values('valid version-two written reply records safely',result->>'status'='recorded');
 update public.email_action_requests set response_protocol_version=1,response_token_hash=null where id=action;
 update public.email_written_reply_settings set enabled=false where mailbox='test@example.invalid';
 result:=public.claim_written_selection_reply('test@example.invalid','<disabled@test>','disabled',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('feature disable stops new captures',result->>'status'='ignored');
 update public.email_written_reply_settings set enabled=true where mailbox='test@example.invalid';
 insert into reply_test_results select 'production scope leaves acceptance pending',acceptance='pending' and responded_at is null from public.team_selection_members where id=target;
 insert into reply_test_results select 'production scope keeps the request pending',status='pending' and last_action is null from public.email_action_requests where id=action;
 update public.email_action_requests set expires_at=now()-interval '1 second' where id=action;
 result:=public.claim_written_selection_reply('test@example.invalid','<expired@test>','expired',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('expired request ignored',result->>'status'='no_current_request');
 update public.email_action_requests set expires_at=now()+interval '1 day',status='responded' where id=action;
 result:=public.claim_written_selection_reply('test@example.invalid','<responded@test>','responded',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('responded request ignored',result->>'status'='no_current_request');
 update public.email_action_requests set status='pending' where id=action;
 update public.team_selection_members set acceptance='accepted' where id=target;
 result:=public.claim_written_selection_reply('test@example.invalid','<accepted@test>','accepted',now(),'BWL-000000000001','selection-test@example.invalid','Synthetic selection','Thanks');
 insert into reply_test_results values('accepted selection ignored',result->>'status'='selection_not_pending');
 insert into reply_test_results values('anonymous cannot execute',not has_function_privilege('anon','public.claim_written_selection_reply(text,text,text,timestamptz,text,text,text,text,text)','EXECUTE'));
 insert into reply_test_results values('user cannot execute',not has_function_privilege('authenticated','public.claim_written_selection_reply(text,text,text,timestamptz,text,text,text,text,text)','EXECUTE'));
 insert into reply_test_results values('user cannot read audit mailbox records',not has_table_privilege('authenticated','public.email_written_replies','SELECT'));
 if exists(select 1 from reply_test_results where passed is distinct from true) then raise exception 'Written reply assertion failed'; end if;
end;
$test$;
select (select jsonb_agg(to_jsonb(t)) from reply_test_results t) tests,(select to_jsonb(p) from reply_test_preview p limit 1) preview;
rollback;
