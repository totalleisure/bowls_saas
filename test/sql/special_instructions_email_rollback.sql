begin;
-- Isolate this test batch; every change below is rolled back and no email sender runs.
update public.notification_queue set status='processed' where status='pending';
do $test$
declare f uuid; s uuid; m uuid; n uuid; found_body text;
begin
 select ts.fixture_id,ts.id,mp.id into strict f,s,m from public.team_selections ts
 join public.fixtures fx on fx.id=ts.fixture_id
 join public.club_memberships cm on cm.club_id=fx.club_id
 join public.member_profiles mp on mp.id=cm.member_profile_id
 where ts.status='published' and cm.is_active and mp.email_address is not null and btrim(mp.email_address)<>'' limit 1;
 insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id,payload,status)
 values('team_published_captain',m,m,f,s,jsonb_build_object('fixture_label','Instructions regression','special_instructions','Meet 09:30 <bring lunch>', 'attachments', jsonb_build_array(jsonb_build_object('name','test.pdf','contentType','application/pdf','contentBytes',encode(convert_to('%PDF-1.4 regression test only','UTF8'),'base64'),'compositionVersion',(select composition_version from public.team_selections where id=s)))), 'pending') returning id into n;
 update public.fixtures set notes='Changed after publication' where id=f;
 perform public.process_notification_queue(10);
 select body into found_body from public.email_queue where fixture_id=f and team_selection_id=s and body like '%Meet 09:30 <bring lunch>%' limit 1;
 if found_body is null or found_body not like '%Special instructions:%' then raise exception 'FAIL publication email: %', (select to_jsonb(q) - 'payload' - 'member_profile_id' - 'target_member_profile_id' from public.notification_queue q where id=n); end if;
end;
$test$;
rollback;
