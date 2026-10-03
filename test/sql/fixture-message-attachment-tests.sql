begin;
set local statement_timeout='30s';
create temp table fixture_message_results(test text,passed boolean) on commit drop;
do $test$
declare
 f uuid:='0787fdcf-2e9f-432e-9215-6ea184a7e3b0'; s uuid:='9e4386cc-e0cd-4582-ae9f-f80ef37c33bb';
 actor uuid:='42acb093-02d8-47cc-a43e-292bfa6cf17a'; recipient uuid:='5e6a6ab9-3130-4488-8860-6af7cd3f2621';
 uid uuid; ver integer; nid uuid; v_payload jsonb; pdf jsonb; n integer; scenario text;
begin
 select user_id into uid from public.member_profiles where id=actor;
 select composition_version into ver from public.team_selections where id=s;
 pdf:=jsonb_build_object('name','test.pdf','contentType','application/pdf','contentBytes',encode(convert_to('%PDF-1.4 test','UTF8'),'base64'),'compositionVersion',ver);
 foreach scenario in array array['plain','current','missing','stale'] loop
  v_payload:=jsonb_build_object('title','Rollback fixture message','message','Test message','fixture_label','Test');
  if scenario<>'plain' then v_payload:=v_payload||jsonb_build_object('team_sheet_required',true); end if;
  if scenario='current' then v_payload:=v_payload||jsonb_build_object('attachments',jsonb_build_array(pdf)); end if;
  if scenario='stale' then v_payload:=v_payload||jsonb_build_object('attachments',jsonb_build_array(pdf||jsonb_build_object('compositionVersion',ver-1))); end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
  nid:=gen_random_uuid();
  -- Client grants intentionally exclude id; identify the generated queue row after insert.
  set local role authenticated;
  insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id,payload,status)
  values('fixture_message',actor,recipient,f,s,v_payload||jsonb_build_object('test_run',nid),'pending');
  reset role;
  select id into nid from public.notification_queue where payload->>'test_run'=nid::text;
  perform set_config('app.notification_queue_ids',nid::text,true);
  n:=public.process_notification_queue(1);
  insert into fixture_message_results values(scenario||' processing outcome',n=case when scenario in ('plain','current') then 1 else 0 end);
  if scenario in ('plain','current') then
   insert into fixture_message_results select scenario||' email attachment state',exists(select 1 from public.email_queue where fixture_id=f and member_profile_id=recipient and event_type='fixture_message' and created_at=now() and attachments=case when scenario='plain' then '[]'::jsonb else jsonb_build_array(pdf) end);
  else
   insert into fixture_message_results select scenario||' blocked',status='failed' and last_error='Required Team Sheet attachment is missing or stale.' from public.notification_queue where id=nid;
   set local role authenticated;
   perform public.attach_publication_team_sheet(f,s,ver,pdf);
   reset role;
   insert into fixture_message_results select scenario||' repaired to current PDF',status='pending' and payload->'attachments'=jsonb_build_array(pdf) from public.notification_queue where id=nid;
   n:=public.process_notification_queue(1);
   insert into fixture_message_results values(scenario||' retry succeeds',n=1);
  end if;
 end loop;
end;
$test$;
select * from fixture_message_results;
rollback;
