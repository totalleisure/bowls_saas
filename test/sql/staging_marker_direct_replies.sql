-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; result jsonb; old_draw jsonb; v_rink uuid; setup_match uuid; old_event uuid; request_id uuid:=gen_random_uuid(); queue_id uuid; source_id uuid; forward_id uuid; code text; subject_text text; response jsonb;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..6 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,raw_user_meta_data) values(u,'competition-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Player '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Player '||i,'Synthetic','Player '||i) returning id into mp; end if;
  update public.member_profiles set first_name='Synthetic',last_name='Player '||i where id=mp;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,mp,case when i=5 then 'admin'::public.club_role else 'member'::public.club_role end,true);
  ids:=array_append(ids,u); profiles:=array_append(profiles,mp);
 end loop;
 insert into public.club_competitions(id,club_id,name,season,status,settings,created_by,fixture_type_id) values(c,club,'Synthetic Admin arrangement verification','test','draft',settings||'{"handicap_mode":"team_difference"}',ids[5],ft);
 insert into public.competition_entries(id,competition_id,name) values(a,c,'Synthetic Player 1 / Synthetic Player 2'),(b,c,'Synthetic Player 3 / Synthetic Player 4');
 for i in 1..4 loop insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c,case when i<=2 then a else b end,profiles[i]); end loop;
 update public.competition_entry_members set individual_handicap=case when entry_id=a then 12 else 5 end where competition_id=c;
 update public.competition_entries set payment_status='paid',entry_order=7 where id=a;
 insert into public.competition_rounds(id,competition_id,round_number,name) values(r,c,1,'Final');
 insert into public.competition_draw_matches(id,competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id) values(m,c,r,1,'entry','entry',a,b);
 -- Simulate only the newly created synthetic identity, never a real member.
 perform set_config('request.jwt.claim.sub',ids[5]::text,true);
 if not competition_private.can_manage(club) then raise exception 'Synthetic organiser requires Admin rights'; end if;

 for i in 1..6 loop update public.member_profiles set email_address='marker-test-'||profiles[i]::text||'@example.invalid' where id=profiles[i];end loop;
 insert into public.app_superusers(user_id) values(ids[5]);
 update public.club_competitions set status='published' where id=c;
 select rink_label into strict label from public.get_green_rink_availability(green,'2030-07-02 10:00Z','2030-07-02 12:30Z') where not is_booked and free_capacity_rinks>=1 limit 1;
 f:=public.arrange_competition_match(m,green,'2030-07-02 10:00Z','2030-07-02 12:30Z',array[label]);
 update public.member_profiles set email_address='wayne@totalleisure.com' where id=profiles[5];
 update public.member_profiles set email_address='wayne.sayers@telius.co.uk' where id=profiles[6];
 select id into strict v_rink from public.fixture_rinks where fixture_id=f limit 1;
 update public.fixture_rinks set marker_required=true where id=v_rink;
 insert into public.fixture_marker_requests(id,fixture_rink_id,status,requested_by_member_profile_id) values(request_id,v_rink,'open',profiles[5]);
 update public.fixtures set team_name='Marker layout test',start_at='2030-07-02 10:30Z',end_at='2030-07-02 13:00Z' where id=f;
 update public.member_profiles set phone='07710 325696' where id=profiles[5];
 insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,fixture_id,payload,status)
 values('marker_request_opened',profiles[5],profiles[6],f,jsonb_build_object('marker_request_id',request_id,'fixture_rink_id',v_rink,'fixture_label','Synthetic marker test','start_at','2030-07-02 10:00Z'),'pending') returning id into queue_id;
 perform public.process_selected_notification_queue_rows(array[queue_id]);
 select id,payload->'action_block'->>'response_code',subject into strict source_id,code,subject_text from public.email_queue where fixture_id=f and event_type='marker_request_opened' and status='pending';
 if not exists(select 1 from public.email_queue where id=source_id
  and subject like 'Volunteer Marker Request: Marker layout test - %'
  and body like '%Fixture: Marker layout test - %' and body like '%Time: 11:30 - 14:00%'
  and body not like '%A volunteer marker is required%' and body not like '%REQUEST FOR VOLUNTEERS%' and body not like '%Captain:%'
  and payload->>'marker_contact_footer' like '%If you have any questions, please contact:%'
  and payload->>'marker_contact_footer' like '%07710 325696%'
  and payload->'action_block'->'actions'->0->>'command'='OFFER_TO_MARK'
  and jsonb_array_length(payload->'action_block'->'actions')=1) then raise exception 'New marker layout/commands incorrect'; end if;
 if code !~ '^MRK-[A-F0-9]{64}$' then raise exception 'No marker response credential';end if;
 if not exists(select 1 from marker_reply_private.tokens where source_email_id=source_id) then raise exception 'Missing request correlation';end if;
 update public.email_queue set status='sent',sent_at=now() where id=source_id;
 response:=public.forward_marker_written_reply(code,'wrong@example.test','<bad@test>',now(),subject_text,'Can I help?');
 if (response->>'handled')::boolean then raise exception 'Wrong sender forwarded';end if;
 response:=public.forward_marker_written_reply(code,'wayne.sayers@telius.co.uk','<plain@test>',now(),subject_text,'Can I help with the marking?');
 if response->>'status'<>'forward_queued' then raise exception 'Forward not queued: %',response;end if;
 select id into strict forward_id from public.email_queue where fixture_id=f and event_type='marker_reply_forwarded';
 if exists(select 1 from public.email_queue where fixture_id=f and event_type='marker_reply_acknowledgement') then raise exception 'Claimed forwarded before send';end if;
 response:=public.forward_marker_written_reply(code,'wayne.sayers@telius.co.uk','<plain@test>',now(),subject_text,'Can I help with the marking?');
 if response->>'status'<>'duplicate' then raise exception 'Repeated reply forwarded twice';end if;
 update public.email_queue set status='failed' where id=forward_id;
 if exists(select 1 from public.email_queue where fixture_id=f and event_type='marker_reply_acknowledgement') then raise exception 'Failed forward acknowledged';end if;
 update public.email_queue set status='sent',sent_at=now() where id=forward_id;
 update public.email_queue set status='sent' where id=forward_id;
 if (select count(*) from public.email_queue where fixture_id=f and event_type='marker_reply_acknowledgement' and body like '%has been forwarded%' and payload->'action_block'->'actions'->0->>'label'='I CAN HELP' and jsonb_array_length(payload->'action_block'->'actions')=1)<>1 then raise exception 'Acknowledgement/buttons incorrect';end if;
 response:=public.record_marker_volunteer_response(code,'wrong@example.test','OFFER_TO_MARK','<bad-action@test>',now());
 if (response->>'ok')::boolean then raise exception 'Wrong sender response accepted';end if;
 response:=public.record_marker_volunteer_response(code,'wayne.sayers@telius.co.uk','OFFER_MARKER','<offer@test>',now());
 if response->>'status'<>'recorded' then raise exception 'Offer not recorded: %',response;end if;
 response:=public.record_marker_volunteer_response(code,'wayne.sayers@telius.co.uk','OFFER_TO_MARK','<offer@test>',now());
 if response->>'status'<>'duplicate' then raise exception 'Duplicate offer repeated';end if;
 response:=public.record_marker_volunteer_response(code,'wayne.sayers@telius.co.uk','UNABLE_MARKER','<unable@test>',now());
 if response->>'status'<>'recorded' then raise exception 'Decline not recorded';end if;
 if exists(select 1 from public.fixture_rink_assignments where fixture_rink_id=v_rink and position=201) or not exists(select 1 from public.fixture_marker_requests where id=request_id and status='open') then raise exception 'An offer appointed a marker';end if;
 if not exists(select 1 from marker_reply_private.tokens where source_email_id=source_id and latest_response='UNABLE_TO_MARK') then raise exception 'Latest response missing';end if;
 perform public.admin_force_delete_fixture(f,'Synthetic marker deletion compatibility','DELETE FIXTURE');
 if exists(select 1 from public.fixtures where id=f) then raise exception 'Marker audit blocked fixture deletion';end if;
 if not exists(select 1 from marker_reply_private.tokens tt where tt.code_hash=encode(extensions.digest(code,'sha256'),'hex') and tt.source_email_id is null and tt.request_id is null) then raise exception 'Marker reply history not retained';end if;
 if has_function_privilege('authenticated','public.forward_marker_written_reply(text,text,text,timestamptz,text,text)','execute') or has_function_privilege('anon','public.record_marker_volunteer_response(text,text,text,text,timestamptz)','execute') then raise exception 'Worker RPC exposed';end if;
end $$;
rollback;
select 'PASS: real request renderer buttons, token/sender binding, durable forward, acknowledgement only after sent, duplicate/failed-forward handling, offer/decline without appointment; all rolled back' result;


