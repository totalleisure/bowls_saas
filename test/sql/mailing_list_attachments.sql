begin;
set local statement_timeout = '30s';
do $test$
declare
 actor uuid; member uuid; club uuid; list uuid; j jsonb; item jsonb;
 files jsonb := '[{"name":"Guide.pdf","contentBytes":"UERG"},{"name":"Times.csv","contentBytes":"YSxi"}]';
 before_count integer; rejected boolean; cases integer:=0;
begin
 select mp.user_id,mp.id,cm.club_id into actor,member,club
 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
 where cm.role='admin' and cm.is_active and mp.user_id is not null
 and nullif(btrim(mp.email_address),'') is not null limit 1;
 if actor is null then raise exception 'No test administrator available'; end if;
 insert into public.mailing_lists(club_id,name,is_active) values(club,'ROLLBACK attachment verification',true) returning id into list;
 insert into public.mailing_list_members(mailing_list_id,member_profile_id,is_active) values(list,member,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 set local role authenticated;
 j:=public.queue_mailing_list_message_with_attachments(list,'Attachment test','Test',true,true,files);
 reset role;
 if (j->>'emails_queued')::integer<>1 then raise exception 'Recipient count mismatch'; end if;
 if not exists(select 1 from public.email_queue where payload->>'mailing_list_message_id'=j->>'mailing_list_message_id'
 and jsonb_array_length(attachments)=2
 and attachments->0->>'name'='Guide.pdf'
 and decode(attachments->1->>'contentBytes','base64')=convert_to('a,b','UTF8')) then raise exception 'Attachments missing or corrupt'; end if;
 select count(*) into before_count from public.mailing_list_messages where mailing_list_id=list;
 for item in select value from jsonb_array_elements(jsonb_build_array(
   'null'::jsonb, '{}'::jsonb,
   '[{"name":"bad","contentBytes":"not base64!"}]'::jsonb,
   '[{"name":"empty","contentBytes":""}]'::jsonb,
   '[{"name":"../bad","contentBytes":"YQ=="}]'::jsonb,
   '[{"name":"same","contentBytes":"YQ=="},{"name":"SAME","contentBytes":"Yg=="}]'::jsonb,
   jsonb_build_array(jsonb_build_object('name','big','contentBytes',repeat('YWFh',699051))),
   (select jsonb_agg(jsonb_build_object('name',i::text,'contentBytes','YQ==')) from generate_series(1,11) i)
 )) loop
   rejected:=false;
   begin
     set local role authenticated;
     perform public.queue_mailing_list_message_with_attachments(list,'Bad','Test',true,true,item);
   exception when others then rejected:=true;
   end;
   reset role;
   if not rejected then raise exception 'Invalid attachments accepted: case %',cases; end if;
   cases:=cases+1;
 end loop;
 rejected:=false;
 begin
   set local role authenticated;
   perform public.queue_mailing_list_message_with_attachments(list,'App only','Test',true,false,files);
 exception when others then rejected:=true; end;
 reset role;
 if not rejected then raise exception 'App only attachments accepted'; end if;
 if (select count(*) from public.mailing_list_messages where mailing_list_id=list)<>before_count then
   raise exception 'Invalid request left partial messages'; end if;
 -- A signed-in user with no club/admin privileges must not be able to queue.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
 rejected:=false;
 begin
   set local role authenticated;
   perform public.queue_mailing_list_message_with_attachments(list,'Unauthorized','Test',true,true,files);
 exception when others then rejected:=true; end;
 reset role;
 if not rejected then raise exception 'Unauthorized send accepted'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 set local role authenticated;
 j:=public.queue_mailing_list_message_with_attachments(list,'No files','Test',false,true,'[]');
 reset role;
 if not exists(select 1 from public.email_queue where payload->>'mailing_list_message_id'=j->>'mailing_list_message_id' and attachments='[]'::jsonb) then
   raise exception 'No-attachment regression'; end if;
 if has_function_privilege('anon','public.queue_mailing_list_message_with_attachments(uuid,text,text,boolean,boolean,jsonb)','execute')
 or has_function_privilege('anon','mailing_private.queue_with_attachments(uuid,text,text,boolean,boolean,jsonb)','execute') then
   raise exception 'Anonymous execution allowed'; end if;
end;
$test$;
select 'PASS: attachments, byte content, input rejection, permissions, atomic rollback, legacy behavior' result;
rollback;
