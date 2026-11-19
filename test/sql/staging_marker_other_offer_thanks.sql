-- Synthetic users, membership and draw; every record is rolled back.
begin;
do $$
declare ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid; c uuid:=gen_random_uuid();
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); m uuid:=gen_random_uuid();
 club uuid; ft uuid; green uuid; f uuid; label text; settings jsonb; emails bigint; notices bigint; result jsonb; old_draw jsonb; v_rink uuid; setup_match uuid; old_event uuid; request_id uuid:=gen_random_uuid(); queue_id uuid; source_id uuid; forward_id uuid; code text; subject_text text; response jsonb; j int; v_token uuid; v_code text; v_source uuid; code_late text; expected_early int;
begin
 select cc.club_id,cc.fixture_type_id,cc.settings into strict club,ft,settings
 from public.club_competitions cc where cc.name='Mens Pairs' limit 1;
 select g.id into strict green from public.green_areas g join public.venues v on v.id=g.venue_id where v.club_id=club and v.is_home_venue limit 1;
 for i in 1..12 loop
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

 for i in 1..12 loop update public.member_profiles set email_address='marker-test-'||profiles[i]::text||'@example.invalid' where id=profiles[i];end loop;
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

 expected_early:=case when (select environment from public.competition_release_controls where id)='production' then 3 else 2 end;
 -- Existing token/fixture belongs to the marker ultimately appointed.
 response:=public.record_marker_volunteer_response(code,'wayne.sayers@telius.co.uk','OFFER_TO_MARK','<chosen-offer@test>',clock_timestamp());
 if response->>'status'<>'recorded' then raise exception 'Chosen marker offer failed';end if;
 for j in 7..12 loop
  update public.member_profiles set email_address=case j when 7 then 'wayne.sayers@icloud.com' when 8 then 'wayne.sayers@me.com' when 9 then 'wayne.streem@gmail.com' when 10 then 'wayne.s.sayers@gmail.com' when 11 then 'outside-test@example.invalid' else 'wayne.sayers@icloud.com' end where id=profiles[j];
  v_code:='MRK-'||upper(replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''));
  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload)
  select id,'marker_request_opened',email_address,'Synthetic offer request','Synthetic offer request',f,jsonb_build_object('marker_request_id',request_id) from public.member_profiles where id=profiles[j] returning id into v_source;
  if j=11 then
   -- A deliberately non-test recipient must never receive a courtesy email.
   insert into marker_reply_private.tokens(request_id,member_id,source_email_id,recipient,code_hash,expires_at,latest_response)
   values(request_id,profiles[j],v_source,'outside-test@example.invalid',encode(extensions.digest(v_code,'sha256'),'hex'),now()+interval '1 day','OFFER_TO_MARK') returning id into v_token;
   insert into marker_reply_private.inbound(token_id,message_id,kind,received_at) values(v_token,'<outside-offer@test>','OFFER_TO_MARK',clock_timestamp());
  else
   select payload->'action_block'->>'response_code' into v_code from public.email_queue where id=v_source;
   update public.email_queue set status='sent',sent_at=now() where id=v_source;
   if j=10 then code_late:=v_code;
   else
    response:=public.record_marker_volunteer_response(v_code,(select email_address from public.member_profiles where id=profiles[j]),'OFFER_TO_MARK','<offer-'||j||'@test>',clock_timestamp());
    if response->>'status'<>'recorded' then raise exception 'Volunteer offer failed: %',j;end if;
    if j=9 then response:=public.record_marker_volunteer_response(v_code,'wayne.streem@gmail.com','UNABLE_TO_MARK','<withdraw-offer@test>',clock_timestamp());end if;
   end if;
  end if;
 end loop;
 if exists(select 1 from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f) then raise exception 'Thanks sent before appointment';end if;
 perform marker_reply_private.queue_other_offer_thanks(request_id,profiles[6]);
 if exists(select 1 from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f) then raise exception 'Unconfirmed marker caused thanks';end if;
 perform public.set_competition_fixture_marker(f,v_rink,true,profiles[6],true,null);
 set constraints confirm_agreed_marker immediate;
 if (select count(*) from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f)<>expected_early then raise exception 'Expected eligible distinct other-offer addresses, got %',(select jsonb_agg(jsonb_build_object('recipient',recipient_email,'event',event_type)) from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f);end if;
 if exists(select 1 from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f and recipient_email not in('wayne.sayers@icloud.com','wayne.sayers@me.com') and not(expected_early=3 and recipient_email='outside-test@example.invalid')) then raise exception 'Chosen/withdrawn/nonresponding/non-test volunteer thanked';end if;
 if not exists(select 1 from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f and body like '%A marker has now been appointed%' and body like '%We greatly appreciate your offer%' and body like '%11:30 - 14:00%') then raise exception 'Polite closure/details missing';end if;
 if (select count(*) from public.email_queue where event_type='marker_appointment_confirmed' and fixture_id=f)<>2 then raise exception 'Appointment confirmation route changed';end if;
 -- Repeated saves/helper calls must not repeat the courtesy message.
 perform public.set_competition_fixture_marker(f,v_rink,true,profiles[6],true,profiles[6]);
 perform marker_reply_private.queue_other_offer_thanks(request_id,profiles[6]);
 if (select count(*) from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f)<>expected_early then raise exception 'Duplicate courtesy messages';end if;
 -- A late offer gets a clear closure without reopening the request or replacing the named marker.
 response:=public.record_marker_volunteer_response(code_late,'wayne.s.sayers@gmail.com','OFFER_TO_MARK','<late-offer@test>',clock_timestamp());
 if response->>'status'<>'marker_already_arranged' then raise exception 'Late offer not closed politely: %',response;end if;
 if not exists(select 1 from public.email_queue where fixture_id=f and event_type='marker_other_offer_thanks' and recipient_email='wayne.s.sayers@gmail.com' and body like '%Thank you very much for offering to help.%' and body like '%A marker has already been appointed for this match%' and body like '%your willingness to help is greatly appreciated%') then raise exception 'Approved late-offer wording missing';end if;
 if (select count(*) from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f)<>expected_early+1 then raise exception 'Late offer not thanked';end if;
 response:=public.record_marker_volunteer_response(code_late,'wayne.s.sayers@gmail.com','OFFER_TO_MARK','<late-offer@test>',clock_timestamp());
 if (select count(*) from public.email_queue where event_type='marker_other_offer_thanks' and fixture_id=f)<>expected_early+1 then raise exception 'Repeated late offer resent courtesy';end if;
 if not exists(select 1 from public.fixture_marker_requests where id=request_id and status='fulfilled' and fulfilled_by_member_profile_id=profiles[6]) or not exists(select 1 from public.fixture_rink_assignments where fixture_rink_id=v_rink and position=201 and member_profile_id=profiles[6]) then raise exception 'Offer changed appointment';end if;
 if has_function_privilege('authenticated','marker_reply_private.queue_other_offer_thanks(uuid,uuid)','execute') or has_function_privilege('service_role','marker_reply_private.queue_other_offer_thanks(uuid,uuid)','execute') then raise exception 'Private helper exposed';end if;
end $$;
rollback;
select 'PASS: one green action; other recorded offers thanked only after named appointment; chosen, withdrawn, silent and non-test recipients excluded; shared addresses/retries deduplicated; late offers handled; all synthetic changes rolled back' result;
