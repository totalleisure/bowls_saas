begin;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='audit_private'::regnamespace and proname='clarify_marker_volunteer_request')<>'fcc2785b84df5be212a9e562ccfe845d' then raise exception 'Unexpected clarify_marker_volunteer_request definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='audit_private'::regnamespace and proname='confirm_agreed_marker')<>'31acbf1c7a6239422780c139d7670056' then raise exception 'Unexpected confirm_agreed_marker definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='marker_reply_private'::regnamespace and proname='issue_request_buttons')<>'ee5c910c7c3aed6d4ab041b524030705' then raise exception 'Unexpected issue_request_buttons definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='marker_reply_private'::regnamespace and proname='action_block')<>'b8ac4f5309d24aaa528ae8c5ac031f8f' then raise exception 'Unexpected action_block definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='public'::regnamespace and proname='forward_marker_written_reply')<>'014ded44531e403ee565504cbe6d4673' then raise exception 'Unexpected forward_marker_written_reply definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='marker_reply_private'::regnamespace and proname='acknowledge_sent_forward')<>'a0f70c47de3398dc3c17748a1af2e5f5' then raise exception 'Unexpected acknowledge_sent_forward definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='public'::regnamespace and proname='record_marker_volunteer_response')<>'8fdaaaf3070cebc4effc441e33f92cac' then raise exception 'Unexpected record_marker_volunteer_response definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='public'::regnamespace and proname='marker_list_email_action')<>'aa0e8e36547ac7a3129bde512dca4bf9' then raise exception 'Unexpected marker_list_email_action definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='marker_reply_private'::regnamespace and proname='suppress_opted_out_request')<>'389a3ad654f3443e13bc19160b7525a2' then raise exception 'Unexpected suppress_opted_out_request definition';end if;end $$;
do $$ begin if (select md5(replace(pg_get_functiondef(oid),chr(13),'')) from pg_proc where pronamespace='marker_reply_private'::regnamespace and proname='queue_other_offer_thanks')<>'9fdc077798fc27de46e12d030bf515fd' then raise exception 'Unexpected queue_other_offer_thanks definition';end if;end $$;
CREATE OR REPLACE FUNCTION audit_private.clarify_marker_volunteer_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.fixtures; fr public.fixture_rinks; captain public.member_profiles; label text; type_name text; footer text; intro text;
begin
 intro:='This request is sent to several volunteers. You are only appointed when you receive a separate confirmation.';
 if tg_table_name='email_queue' then
  if new.event_type<>'marker_request_opened' then return new; end if;
  select * into strict f from public.fixtures where id=new.fixture_id;
  select name into type_name from public.competition_types where id=f.competition_type_id;
  label:=coalesce(nullif(btrim(f.team_name),''),nullif(btrim(type_name),''),'Club fixture');
  if nullif(btrim(type_name),'') is not null and lower(label)<>lower(btrim(type_name)) then label:=label||' - '||btrim(type_name); end if;
  select r.* into fr from public.fixture_rinks r join public.fixture_marker_requests q on q.fixture_rink_id=r.id
   where q.id=nullif(new.payload->>'marker_request_id','')::uuid and r.fixture_id=f.id;
  select * into captain from public.member_profiles where id=f.captain_member_profile_id;
  footer:=concat_ws(chr(10),'If you have any questions, please contact:',
   'Captain: '||coalesce(nullif(btrim(concat_ws(' ',captain.first_name,captain.last_name)),''),nullif(captain.display_name,''),'Fixture captain'),
   'Email: '||coalesce(nullif(btrim(captain.email_address),''),'Not recorded'),
   'Telephone: '||coalesce(nullif(btrim(captain.phone),''),'Not recorded'));
  new.subject:='Volunteer Marker Request: '||label;
  new.body:=concat_ws(chr(10),intro,'','Fixture: '||label,
   'Date: '||to_char(f.start_at at time zone 'Europe/London','FMDay DD Mon YYYY'),
   'Time: '||to_char(f.start_at at time zone 'Europe/London','HH24:MI')||' - '||to_char(coalesce(f.end_at,f.start_at+interval '4 hours') at time zone 'Europe/London','HH24:MI'),
   'Venue: '||(select name from public.venues where id=case when f.is_home then f.venue_id else f.opponent_venue_id end),
   case when nullif(btrim(f.opponent_name),'') is not null then 'Opponent: '||f.opponent_name end,
   case when fr.id is not null then 'Rink: '||coalesce(nullif(fr.home_rink_label,''),fr.fixture_rink_no::text) end);
  new.payload:=coalesce(new.payload,'{}'::jsonb)||jsonb_build_object('marker_request_layout',2,'marker_contact_footer',footer);
 else
  if new.type<>'marker_request_opened' then return new; end if;
  new.body:=intro||chr(10)||chr(10)||new.body;
  new.title:='Volunteer Marker Request';
 end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION audit_private.confirm_agreed_marker()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.fixtures; fr public.fixture_rinks; marker public.member_profiles; req public.fixture_marker_requests; msg text;
begin
 if new.status<>'fulfilled' or new.fulfilled_by_member_profile_id is null then return new;end if;
 if old.status='fulfilled' and old.fulfilled_by_member_profile_id is not distinct from new.fulfilled_by_member_profile_id then return new;end if;
 -- Deferred until the save has finished: only the final persisted named marker is appointed.
 select * into req from public.fixture_marker_requests where id=new.id;
 if not found or req.status<>'fulfilled' or req.fulfilled_by_member_profile_id is distinct from new.fulfilled_by_member_profile_id then return new;end if;
 select * into fr from public.fixture_rinks where id=req.fixture_rink_id;
 if not found then return new;end if;
 select * into f from public.fixtures where id=fr.fixture_id;
 if not found or f.cancelled_at is not null or f.archived_at is not null then return new;end if;
 if not exists(select 1 from public.fixture_rink_assignments where fixture_rink_id=fr.id and position=201 and member_profile_id=req.fulfilled_by_member_profile_id) then return new;end if;
 select * into strict marker from public.member_profiles where id=req.fulfilled_by_member_profile_id;
 msg:=concat_ws(chr(10),'MARKER APPOINTMENT CONFIRMED',
 coalesce(nullif(marker.display_name,''),trim(concat_ws(' ',marker.first_name,marker.last_name)))||' has been appointed as the marker for this fixture.',
 'This is the appointment confirmation, rather than a request for volunteers.', '',
 'Fixture: '||coalesce(nullif(f.team_name,''),nullif(f.opponent_name,''),'Club fixture'),
 'When: '||to_char(f.start_at at time zone 'Europe/London','FMDay DD Mon YYYY "at" HH24:MI'),
 'Venue: '||(select name from public.venues where id=case when f.is_home then f.venue_id else f.opponent_venue_id end),
 'Rink: '||coalesce(nullif(fr.home_rink_label,''),fr.fixture_rink_no::text), '',
 'The appointed marker should attend for the agreed fixture. If circumstances change, please contact the organiser promptly.',
 'Other volunteers have not been appointed by receiving the original request.');
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload,status)
 select distinct on(lower(btrim(mp.email_address))) mp.id,'marker_appointment_confirmed',lower(btrim(mp.email_address)),
 'Marker appointment confirmed: '||coalesce(nullif(f.team_name,''),'Club fixture'),msg,f.id,
 jsonb_build_object('marker_appointment_key',req.id::text||':'||marker.id::text,'marker_request_id',req.id,'fixture_rink_id',fr.id,'appointed_marker_id',marker.id,'club_id',f.club_id),'pending'
 from public.member_profiles mp
 where mp.id in(marker.id,req.requested_by_member_profile_id,f.captain_member_profile_id)
 and competition_private.email_recipient_allowed(mp.email_address)
 order by lower(btrim(mp.email_address)),mp.id on conflict do nothing;
 perform marker_reply_private.queue_other_offer_thanks(req.id,marker.id);
 -- Stop outstanding requests being sent after a marker has been appointed.
 update public.email_queue set status='cancelled' where event_type='marker_request_opened' and status='pending' and (payload->>'marker_request_id'=req.id::text or app_notification_id in(select id from public.app_notifications where fixture_id=f.id and data->>'marker_request_id'=req.id::text) or not exists(select 1 from public.fixture_marker_requests mr join public.fixture_rinks rr on rr.id=mr.fixture_rink_id where rr.fixture_id=f.id and mr.status='open'));
 update public.notification_queue set status='cancelled' where event_type='marker_request_opened' and status='pending' and payload->>'marker_request_id'=req.id::text;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION marker_reply_private.issue_request_buttons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare req public.fixture_marker_requests; f public.fixtures; code text;
begin
 if new.event_type<>'marker_request_opened' then return new;end if;
 if coalesce((select environment from public.competition_release_controls where id),'') not in ('staging','production') then raise exception 'Marker reply environment is not configured';end if;
 if not competition_private.email_recipient_allowed(new.recipient_email) then new.status:='cancelled';return new;end if;
 select * into req from public.fixture_marker_requests where id=nullif(new.payload->>'marker_request_id','')::uuid;
 if not found or req.status<>'open' then return new;end if;
 select fx.* into strict f from public.fixtures fx join public.fixture_rinks fr on fr.fixture_id=fx.id where fr.id=req.fixture_rink_id;
 if f.id is distinct from new.fixture_id then raise exception 'Marker request fixture mismatch';end if;
 code:='MRK-'||upper(encode(extensions.gen_random_bytes(32),'hex'));
 insert into marker_reply_private.tokens(request_id,member_id,source_email_id,recipient,code_hash,expires_at)
 values(req.id,new.member_profile_id,new.id,lower(btrim(new.recipient_email)),encode(extensions.digest(code,'sha256'),'hex'),least(f.start_at,now()+interval '30 days'));
 new.payload:=new.payload||jsonb_build_object('action_block',marker_reply_private.action_block(code));
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION marker_reply_private.action_block(p_code text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select jsonb_build_object('version',1,'action_type','marker_volunteer','response_code',p_code,
 'heading','Please respond',
 'instructions','Choose I CAN HELP, then send the prepared email from the address that received this request.',
 'actions',jsonb_build_array(jsonb_build_object('command','OFFER_TO_MARK','label','I CAN HELP')),
 'secondary_actions',jsonb_build_array(jsonb_build_object('command','LEAVE_MARKERS','label','Leave the Markers List')),
 'secondary_instructions','Stops future volunteer requests from this Club after confirmation. Marking appointments already agreed are unchanged.')
$function$
;
CREATE OR REPLACE FUNCTION public.forward_marker_written_reply(p_code text, p_sender text, p_message_id text, p_received_at timestamp with time zone, p_original_subject text, p_excerpt text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t marker_reply_private.tokens; req public.fixture_marker_requests; f public.fixtures; receiver public.member_profiles;
 inbound_id uuid; outbound uuid; msg text;
begin
 if coalesce((select environment from public.competition_release_controls where id),'') not in ('staging','production') then raise exception 'Marker reply environment is not configured';end if;
 select * into t from marker_reply_private.tokens where code_hash=encode(extensions.digest(upper(btrim(p_code)),'sha256'),'hex') for update;
 if not found or coalesce(t.recipient<>lower(btrim(p_sender)),true) or p_received_at is null or t.expires_at<now() or p_received_at<t.created_at or p_received_at>now()+interval '5 minutes' or nullif(p_message_id,'') is null then return jsonb_build_object('handled',false);end if;
 if not exists(select 1 from public.email_queue where id=t.source_email_id and status='sent' and subject=p_original_subject) then return jsonb_build_object('handled',false);end if;
 select * into strict req from public.fixture_marker_requests where id=t.request_id;
 select fx.* into strict f from public.fixtures fx join public.fixture_rinks fr on fr.fixture_id=fx.id where fr.id=req.fixture_rink_id;
 if req.status<>'open' or f.cancelled_at is not null or f.archived_at is not null then return jsonb_build_object('handled',true,'status','closed');end if;
 if not exists(select 1 from public.club_memberships where club_id=f.club_id and member_profile_id=t.member_id and is_active) then return jsonb_build_object('handled',false);end if;
 select * into receiver from public.member_profiles where id=coalesce(req.requested_by_member_profile_id,f.captain_member_profile_id);
 if not competition_private.email_recipient_allowed(receiver.email_address) then return jsonb_build_object('handled',true,'status','requester_not_test_recipient');end if;
 insert into marker_reply_private.inbound(token_id,message_id,kind,received_at) values(t.id,p_message_id,'written',p_received_at) on conflict do nothing returning id into inbound_id;
 if inbound_id is null then return jsonb_build_object('handled',true,'status','duplicate');end if;
 msg:=concat_ws(chr(10),'A volunteer replied directly to the marker request. This message has not appointed anyone.',
 'From: '||t.recipient,'Fixture: '||coalesce(f.team_name,'Club fixture'),
 'When: '||to_char(f.start_at at time zone 'Europe/London','DD Mon YYYY HH24:MI'),'',left(p_excerpt,4000),'',
 'Please agree the marker with the players and save the named marker in the App. A separate appointment confirmation will then be queued.');
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload)
 values(receiver.id,'marker_reply_forwarded',lower(btrim(receiver.email_address)),'Volunteer reply to marker request: '||coalesce(f.team_name,'Club fixture'),msg,f.id,
 jsonb_build_object('marker_reply_id',inbound_id,'marker_request_id',req.id,'marker_ack_recipient',t.recipient,'marker_ack_member',t.member_id,'marker_ack_actions',marker_reply_private.action_block(p_code))) returning id into outbound;
 update marker_reply_private.inbound set forward_email_id=outbound where id=inbound_id;
 return jsonb_build_object('handled',true,'status','forward_queued');
end $function$
;
CREATE OR REPLACE FUNCTION marker_reply_private.acknowledge_sent_forward()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare incoming marker_reply_private.inbound;
begin
 if new.event_type<>'marker_reply_forwarded' or new.status<>'sent' or old.status='sent' then return new;end if;
 select * into incoming from marker_reply_private.inbound where forward_email_id=new.id for update;
 if not found or incoming.acknowledged then return new;end if;
 if not competition_private.email_recipient_allowed(new.payload->>'marker_ack_recipient') then return new;end if;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload)
 values((new.payload->>'marker_ack_member')::uuid,'marker_reply_acknowledgement',new.payload->>'marker_ack_recipient','Your reply to the marker request',
 'Your message has been forwarded to the person requesting a marker. If you can help, please select I CAN HELP below and send the prepared email from this same address. Please wait for a separate appointment confirmation before attending as marker.',new.fixture_id,
 jsonb_build_object('action_block',marker_reply_private.action_block(new.payload->'marker_ack_actions'->>'response_code'),'marker_request_id',new.payload->>'marker_request_id','marker_reply_id',incoming.id));
 update marker_reply_private.inbound set acknowledged=true where id=incoming.id;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.record_marker_volunteer_response(p_code text, p_sender text, p_command text, p_message_id text, p_received_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare t marker_reply_private.tokens; req public.fixture_marker_requests; f public.fixtures; receiver public.member_profiles; incoming_id uuid;

begin

 if coalesce((select environment from public.competition_release_controls where id),'') not in ('staging','production') then raise exception 'Marker reply environment is not configured';end if;

 p_command:=case upper(btrim(p_command)) when 'OFFER_MARKER' then 'OFFER_TO_MARK' when 'UNABLE_MARKER' then 'UNABLE_TO_MARK' else upper(btrim(p_command)) end;
 if p_command not in('OFFER_TO_MARK','UNABLE_TO_MARK') then return jsonb_build_object('ok',false);end if;

 select * into t from marker_reply_private.tokens where code_hash=encode(extensions.digest(upper(btrim(p_code)),'sha256'),'hex') for update;

 if not found or coalesce(t.recipient<>lower(btrim(p_sender)),true) or p_received_at is null or t.expires_at<now() or p_received_at<t.created_at or p_received_at>now()+interval '5 minutes' or nullif(p_message_id,'') is null then return jsonb_build_object('ok',false);end if;

 if not exists(select 1 from public.email_queue where id=t.source_email_id and status='sent') then return jsonb_build_object('ok',false);end if;

 select * into strict req from public.fixture_marker_requests where id=t.request_id for update;

 select fx.* into strict f from public.fixtures fx join public.fixture_rinks fr on fr.fixture_id=fx.id where fr.id=req.fixture_rink_id;

 if req.status not in('open','fulfilled') or f.cancelled_at is not null or f.archived_at is not null then return jsonb_build_object('ok',false,'status','closed');end if;

 if not exists(select 1 from public.club_memberships where club_id=f.club_id and member_profile_id=t.member_id and is_active) then return jsonb_build_object('ok',false);end if;

 insert into marker_reply_private.inbound(token_id,message_id,kind,received_at) values(t.id,p_message_id,p_command,p_received_at) on conflict do nothing returning id into incoming_id;

 if incoming_id is null or t.latest_response=p_command then return jsonb_build_object('ok',true,'status','duplicate');end if;

 update marker_reply_private.tokens set latest_response=p_command where id=t.id;
 if req.status='fulfilled' then
  if p_command='OFFER_TO_MARK' then perform marker_reply_private.queue_other_offer_thanks(req.id,req.fulfilled_by_member_profile_id,t.member_id);end if;
  return jsonb_build_object('ok',true,'status','marker_already_arranged');
 end if;

 select * into receiver from public.member_profiles where id=coalesce(req.requested_by_member_profile_id,f.captain_member_profile_id);

 if competition_private.email_recipient_allowed(receiver.email_address) then

 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload)

 values(receiver.id,'marker_volunteer_response',lower(btrim(receiver.email_address)),'Marker response: '||coalesce(f.team_name,'Club fixture'),

 t.recipient||case when p_command='OFFER_TO_MARK' then ' has offered to mark. This is not an appointment. Please agree the marker and save their name in the App.' else ' is unable to help with this fixture. Their Markers List subscription has not changed.' end,f.id,jsonb_build_object('marker_request_id',req.id,'volunteer_member_id',t.member_id,'response',p_command));

 end if;

 if competition_private.email_recipient_allowed(t.recipient) then

 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload)

 values(t.member_id,'marker_response_receipt',t.recipient,'Your marker response has been recorded',

 case when p_command='OFFER_TO_MARK' then 'Your offer to mark has been recorded. You have NOT been appointed. Please wait for the separate appointment confirmation before attending as marker.' else 'Your Unable to help response has been recorded for this fixture only. You remain on the Markers List.' end,f.id,jsonb_build_object('marker_request_id',req.id,'response',p_command));end if;

 return jsonb_build_object('ok',true,'status','recorded');

end $function$
;
CREATE OR REPLACE FUNCTION public.marker_list_email_action(p_code text, p_sender text, p_command text, p_message_id text, p_received_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t marker_reply_private.tokens; ch marker_reply_private.leave_challenges; req public.fixture_marker_requests;
 club uuid; challenge_id uuid; token text; mail_id uuid; inbound_id uuid; club_name text; member uuid; receiver text;
begin
 if coalesce((select environment from public.competition_release_controls where id),'') not in ('staging','production') then raise exception 'Marker reply environment is not configured';end if;
 if p_received_at is null or p_received_at>now()+interval '5 minutes' or nullif(p_message_id,'') is null or nullif(btrim(p_sender),'') is null then return jsonb_build_object('ok',false);end if;
 if p_command='LEAVE_MARKERS' then
  select * into t from marker_reply_private.tokens where code_hash=encode(extensions.digest(upper(btrim(p_code)),'sha256'),'hex') for update;
  if not found or t.created_at<now()-interval '90 days' or p_received_at<t.created_at or coalesce(t.recipient<>lower(btrim(p_sender)),true) then return jsonb_build_object('ok',false);end if;
  if not exists(select 1 from public.email_queue where id=t.source_email_id and status='sent') then return jsonb_build_object('ok',false);end if;
  select * into req from public.fixture_marker_requests where id=t.request_id;
  select f.club_id into club from public.fixtures f join public.fixture_rinks fr on fr.fixture_id=f.id where fr.id=req.fixture_rink_id;
  if club is null or not competition_private.email_recipient_allowed(t.recipient) or not exists(select 1 from public.club_memberships where club_id=club and member_profile_id=t.member_id and is_active) then return jsonb_build_object('ok',false);end if;
  perform pg_advisory_xact_lock(hashtextextended(t.member_id::text||club::text,73016));
  insert into marker_reply_private.inbound(token_id,message_id,kind,received_at) values(t.id,p_message_id,p_command,p_received_at) on conflict do nothing returning id into inbound_id;
  if inbound_id is null then return jsonb_build_object('ok',true,'status','duplicate');end if;
  if exists(select 1 from marker_reply_private.leave_challenges where member_id=t.member_id and club_id=club and outcome is null and expires_at>now()) then return jsonb_build_object('ok',true,'status','confirmation_pending');end if;
  update marker_reply_private.leave_challenges set outcome='expired',decided_at=now() where member_id=t.member_id and club_id=club and outcome is null and expires_at<=now();
  token:='MLV-'||upper(encode(extensions.gen_random_bytes(32),'hex'));
  insert into marker_reply_private.leave_challenges(member_id,club_id,recipient,code_hash) values(t.member_id,club,t.recipient,encode(extensions.digest(token,'sha256'),'hex')) returning id into challenge_id;
  select name into club_name from public.clubs where id=club;
  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,payload)
  values(t.member_id,'marker_list_leave_confirmation',t.recipient,'Confirm leaving the Markers List',
  'Would you like to leave the Markers List for '||club_name||'? This stops future volunteer marker requests from this Club. It does NOT cancel or change marking appointments you have already agreed. If you cannot attend an agreed appointment, contact its organiser separately. No subscription change is made until you choose Confirm leave and send the prepared email. This confirmation expires in 24 hours.',
  jsonb_build_object('marker_leave_challenge',challenge_id,'club_id',club,'action_block',jsonb_build_object('version',1,'response_code',token,'heading','Confirm your Markers List preference','instructions','This affects future volunteer requests only. Agreed marking appointments remain unchanged.',
  'actions',jsonb_build_array(jsonb_build_object('command','CONFIRM_LEAVE_MARKERS','label','Confirm leave','style','negative'),jsonb_build_object('command','KEEP_MARKERS','label','Keep receiving requests'))))) returning id into mail_id;
  update marker_reply_private.leave_challenges set confirmation_email_id=mail_id where id=challenge_id;
  return jsonb_build_object('ok',true,'status','confirmation_queued');
 elsif p_command in('CONFIRM_LEAVE_MARKERS','KEEP_MARKERS') then
  select * into ch from marker_reply_private.leave_challenges where code_hash=encode(extensions.digest(upper(btrim(p_code)),'sha256'),'hex') for update;
  if not found or coalesce(ch.recipient<>lower(btrim(p_sender)),true) or ch.expires_at<now() or p_received_at<ch.created_at or ch.member_id is null or ch.club_id is null or not competition_private.email_recipient_allowed(ch.recipient) then return jsonb_build_object('ok',false);end if;
  if ch.outcome is not null then return jsonb_build_object('ok',true,'status','duplicate');end if;
  if not exists(select 1 from public.email_queue where id=ch.confirmation_email_id and status='sent') then return jsonb_build_object('ok',false);end if;
  if not exists(select 1 from public.club_memberships where club_id=ch.club_id and member_profile_id=ch.member_id and is_active) then return jsonb_build_object('ok',false);end if;
  if p_command='CONFIRM_LEAVE_MARKERS' then
   -- Only the configured marker task list(s), never other mailing lists or assignments.
   delete from public.mailing_list_members mlm using public.volunteer_tasks vt where vt.club_id=ch.club_id and vt.task_code='marker' and vt.mailing_list_id=mlm.mailing_list_id and mlm.member_profile_id=ch.member_id;
   update public.notification_queue n set status='cancelled' where n.event_type='marker_request_opened' and n.status='pending' and n.target_member_profile_id=ch.member_id and exists(select 1 from public.fixtures f where f.id=n.fixture_id and f.club_id=ch.club_id);
   update public.email_queue q set status='cancelled' where q.event_type='marker_request_opened' and q.status='pending' and q.member_profile_id=ch.member_id and exists(select 1 from public.fixtures f where f.id=q.fixture_id and f.club_id=ch.club_id);
  end if;
  update marker_reply_private.leave_challenges set outcome=case when p_command='CONFIRM_LEAVE_MARKERS' then 'left' else 'kept' end,decided_at=now(),decided_message_id=p_message_id where id=ch.id;
  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,payload)
  values(ch.member_id,'marker_list_preference_receipt',ch.recipient,'Your Markers List preference',
  case when p_command='CONFIRM_LEAVE_MARKERS' then 'You have left the Markers List for this Club. Future volunteer requests have been stopped. Marking appointments already agreed are unchanged. You can rejoin using Volunteer Lists in the App.' else 'No change has been made to your Markers List subscription. Marking appointments already agreed are unchanged.' end,jsonb_build_object('club_id',ch.club_id,'marker_leave_challenge',ch.id));
  return jsonb_build_object('ok',true,'status',case when p_command='CONFIRM_LEAVE_MARKERS' then 'left' else 'kept' end);
 end if;
 return jsonb_build_object('ok',false);
end $function$
;
CREATE OR REPLACE FUNCTION marker_reply_private.suppress_opted_out_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare club uuid;
begin
 if new.event_type<>'marker_request_opened' then return new;end if;
 select club_id into club from public.fixtures where id=new.fixture_id;
 if exists(select 1 from marker_reply_private.leave_challenges where member_id=new.member_profile_id and club_id=club and outcome='left')
 and not exists(select 1 from public.mailing_list_members mlm join public.volunteer_tasks vt on vt.mailing_list_id=mlm.mailing_list_id where vt.club_id=club and vt.task_code='marker' and mlm.member_profile_id=new.member_profile_id and mlm.is_active) then new.status:='cancelled';end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION marker_reply_private.queue_other_offer_thanks(p_request_id uuid, p_marker_id uuid, p_late_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare req public.fixture_marker_requests; fr public.fixture_rinks; f public.fixtures; label text; type_name text; msg text; late_msg text; marker_email text;
begin
 if coalesce((select environment from public.competition_release_controls where id),'') not in ('staging','production') then raise exception 'Marker reply environment is not configured';end if;
 select * into req from public.fixture_marker_requests where id=p_request_id;
 if not found or req.status<>'fulfilled' or req.fulfilled_by_member_profile_id is distinct from p_marker_id then return;end if;
 select * into fr from public.fixture_rinks where id=req.fixture_rink_id;
 select * into f from public.fixtures where id=fr.fixture_id;
 if f.id is null or f.cancelled_at is not null or f.archived_at is not null or not exists(select 1 from public.fixture_rink_assignments where fixture_rink_id=fr.id and position=201 and member_profile_id=p_marker_id) then return;end if;
 select lower(btrim(email_address)) into marker_email from public.member_profiles where id=p_marker_id;
 select name into type_name from public.competition_types where id=f.competition_type_id;
 label:=coalesce(nullif(btrim(f.team_name),''),nullif(btrim(type_name),''),'Club fixture');
 if nullif(btrim(type_name),'') is not null and lower(label)<>lower(btrim(type_name)) then label:=label||' - '||btrim(type_name);end if;
 msg:=concat_ws(chr(10),'Thank you very much for offering to mark this match.','','A marker has now been appointed, so you won’t need to attend as marker on this occasion. We greatly appreciate your offer and hope you’ll be able to help with a future match.','','Fixture: '||label,'Date: '||to_char(f.start_at at time zone 'Europe/London','FMDay DD Mon YYYY'),'Time: '||to_char(f.start_at at time zone 'Europe/London','HH24:MI')||' - '||to_char(coalesce(f.end_at,f.start_at+interval '4 hours') at time zone 'Europe/London','HH24:MI'),'Rink: '||coalesce(nullif(fr.home_rink_label,''),fr.fixture_rink_no::text));
 late_msg:=concat_ws(chr(10),'Thank you very much for offering to help.','','A marker has already been appointed for this match, so no further help is needed on this occasion. You won’t need to attend as marker, but your willingness to help is greatly appreciated.','','Fixture: '||label,'Date: '||to_char(f.start_at at time zone 'Europe/London','FMDay DD Mon YYYY'),'Time: '||to_char(f.start_at at time zone 'Europe/London','HH24:MI')||' - '||to_char(coalesce(f.end_at,f.start_at+interval '4 hours') at time zone 'Europe/London','HH24:MI'),'Rink: '||coalesce(nullif(fr.home_rink_label,''),fr.fixture_rink_no::text));
 -- Use the most recent actual response per member, across reminders/tokens.
 with latest as (
  select distinct on(t.member_id) t.member_id,t.latest_response kind
  from marker_reply_private.tokens t join lateral (
   select max(i.received_at) responded_at from marker_reply_private.inbound i where i.token_id=t.id
   and (i.kind in('OFFER_TO_MARK','OFFER_MARKER') and t.latest_response in('OFFER_TO_MARK','OFFER_MARKER')
     or i.kind in('UNABLE_TO_MARK','UNABLE_MARKER') and t.latest_response in('UNABLE_TO_MARK','UNABLE_MARKER'))
  ) response on response.responded_at is not null
  where t.request_id=req.id order by t.member_id,response.responded_at desc,t.id desc
 )
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,payload,status)
 select distinct on(lower(btrim(mp.email_address))) mp.id,'marker_other_offer_thanks',lower(btrim(mp.email_address)),
 case when mp.id=p_late_member_id then 'Thank you — a marker has already been arranged: ' else 'Thank you for offering to mark: ' end||label,case when mp.id=p_late_member_id then late_msg else msg end,f.id,
 jsonb_build_object('marker_request_id',req.id,'fixture_rink_id',fr.id,'appointed_marker_id',p_marker_id,'club_id',f.club_id),'pending'
 from latest l join public.member_profiles mp on mp.id=l.member_id
 where l.kind in('OFFER_TO_MARK','OFFER_MARKER') and mp.id<>p_marker_id
 and lower(btrim(mp.email_address)) is distinct from marker_email
 and competition_private.email_recipient_allowed(mp.email_address)
 and exists(select 1 from public.club_memberships cm where cm.club_id=f.club_id and cm.member_profile_id=mp.id and cm.is_active)
 order by lower(btrim(mp.email_address)),mp.id on conflict do nothing;
 -- A closure message replaces any still-unsent 'wait for appointment' receipt.
 update public.email_queue q set status='cancelled' where q.status='pending' and q.event_type in('marker_response_receipt','marker_volunteer_response')
 and q.payload->>'marker_request_id'=req.id::text
 and exists(select 1 from public.email_queue thanked where thanked.event_type='marker_other_offer_thanks' and thanked.payload->>'marker_request_id'=req.id::text
 and (thanked.member_profile_id=q.member_profile_id and q.event_type='marker_response_receipt' or thanked.member_profile_id::text=q.payload->>'volunteer_member_id' and q.event_type='marker_volunteer_response'));
end $function$
;
revoke all on function marker_reply_private.queue_other_offer_thanks(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create or replace function marker_reply_private.queue_other_offer_thanks(p_request_id uuid,p_marker_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin perform marker_reply_private.queue_other_offer_thanks(p_request_id,p_marker_id,null);end $$;
revoke all on function marker_reply_private.queue_other_offer_thanks(uuid,uuid) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
