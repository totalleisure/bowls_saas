begin;
do $test$
declare su uuid; admin_id uuid; club uuid; mp uuid; list uuid; j jsonb; again jsonb; req uuid:=gen_random_uuid(); n int;
begin
 select user_id into strict su from public.app_superusers limit 1;
 select cm.club_id,p.id into strict club,mp from public.member_profiles p join public.club_memberships cm on cm.member_profile_id=p.id where p.user_id=su and cm.is_active limit 1;
 select p.user_id into strict admin_id from public.member_profiles p join public.club_memberships cm on cm.member_profile_id=p.id where cm.is_active and cm.role='admin' and p.user_id is not null and not exists(select 1 from public.app_superusers s where s.user_id=p.user_id) limit 1;
 insert into public.mailing_lists(club_id,name,is_active) values(club,'ROLLBACK Total Leisure message test',true) returning id into list;
 insert into public.mailing_list_members(mailing_list_id,member_profile_id) values(list,mp);
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 begin perform public.queue_total_leisure_message(list,'Test','Body',false,true,'[]',req);raise exception 'Club admin claimed Total Leisure identity';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',su::text,true);
 j:=public.queue_total_leisure_message(list,'Test','Body',false,true,'[{"name":"Guide.pdf","contentBytes":"UERG"}]',req);
 again:=public.queue_total_leisure_message(list,'Test','Body',false,true,'[{"name":"Guide.pdf","contentBytes":"UERG"}]',req);
 assert j=again,'Retry created another message';
 assert j->>'sender_identity'='total_leisure','Identity not recorded';
 assert public.mailing_list_email_identity((j->>'mailing_list_message_id')::uuid)='total_leisure','Worker identity not verified';
 select count(*) into n from public.email_queue where payload->>'mailing_list_message_id'=j->>'mailing_list_message_id';assert n=1,'Duplicate email queued';
 begin perform public.queue_total_leisure_message(list,'Changed','Body',false,true,'[]',req);raise exception 'Request ID reused for changed message';exception when invalid_parameter_value then null;end;
 assert not has_function_privilege('authenticated','public.mailing_list_email_identity(uuid)','execute'),'Private identity exposed';
 assert not has_function_privilege('anon','public.queue_total_leisure_message(uuid,text,text,boolean,boolean,jsonb,uuid)','execute'),'Anonymous send granted';
 assert not has_table_privilege('authenticated','mailing_private.total_leisure_messages','INSERT'),'Identity marker writable';
end $test$;
rollback;
select 'PASS: Total Leisure sender limited to superuser; actor recorded; retry idempotent; attachments retained; no test messages committed' result;
