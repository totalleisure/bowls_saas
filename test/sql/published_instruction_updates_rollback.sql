begin;
do $test$
declare f public.fixtures%rowtype; cm public.club_memberships%rowtype;
  uid uuid; request_id uuid:=gen_random_uuid(); n integer; before_count integer; ids text;
begin
  select fx.* into strict f from public.fixtures fx
    where fx.cancelled_at is null and exists(select 1 from public.team_selections ts where ts.fixture_id=fx.id and ts.status='published')
    and exists(select 1 from public.club_memberships m join public.member_profiles p on p.id=m.member_profile_id
      where m.club_id=fx.club_id and p.user_id is not null
      and not exists(select 1 from public.app_superusers su where su.user_id=p.user_id)) limit 1;
  select m.* into strict cm from public.club_memberships m join public.member_profiles p on p.id=m.member_profile_id
    where m.club_id=f.club_id and p.user_id is not null and p.email_address is not null
    and not exists(select 1 from public.app_superusers su where su.user_id=p.user_id) limit 1;
  select user_id into uid from public.member_profiles where id=cm.member_profile_id;
  perform set_config('request.jwt.claim.sub',uid::text,true);
  perform set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
  update public.club_memberships set role='member',is_active=true where id=cm.id;
  update public.fixtures set captain_member_profile_id=cm.member_profile_id,vice_captain_member_profile_id=cm.member_profile_id where id=f.id;
  select count(*) into before_count from public.notification_queue where fixture_id=f.id;
  perform public.set_fixture_instructions(f.id,'Saved quietly',f.notes);
  if (select count(*) from public.notification_queue where fixture_id=f.id)<>before_count then raise exception 'Save queued a message'; end if;
  n:=public.send_fixture_instructions_update(f.id,'New <instructions>','Saved quietly',request_id);
  if n<1 then raise exception 'No recipients'; end if;
  if (select count(*) from public.notification_queue where payload->>'instructions_update_request'=request_id::text and target_member_profile_id=cm.member_profile_id)<>1 then raise exception 'Captain received duplicate'; end if;
  if public.send_fixture_instructions_update(f.id,'New <instructions>','Saved quietly',request_id)<>n then raise exception 'Retry not idempotent'; end if;
  if (select count(*) from public.notification_queue where payload->>'instructions_update_request'=request_id::text)<>n then raise exception 'Duplicate send'; end if;
  select string_agg(id::text,',') into ids from public.notification_queue where payload->>'instructions_update_request'=request_id::text;
  perform set_config('app.notification_queue_ids',ids,true);
  perform public.process_notification_queue(1000);
  if exists(select 1 from public.notification_queue where payload->>'instructions_update_request'=request_id::text and status<>'sent') then raise exception 'Processor failed'; end if;
  if not exists(select 1 from public.email_queue where fixture_id=f.id and member_profile_id=cm.member_profile_id
    and body like '%New <instructions>%' and subject like 'Special Instructions Update%' and attachments='[]'::jsonb) then raise exception 'Update email missing'; end if;
  begin
    perform public.send_fixture_instructions_update(f.id,'Overwrite','stale',gen_random_uuid());
    raise exception 'FAIL stale edit permitted';
  exception when serialization_failure then null; end;
  perform public.send_fixture_instructions_update(f.id,'','New <instructions>',gen_random_uuid());
  if not exists(select 1 from public.notification_queue where fixture_id=f.id and payload->>'message'='The special instructions for this fixture have been removed.') then raise exception 'Removal notice missing'; end if;
  update public.fixtures set captain_member_profile_id=null,vice_captain_member_profile_id=null where id=f.id;
  begin
    perform public.send_fixture_instructions_update(f.id,'Denied',null,gen_random_uuid());
    raise exception 'FAIL ordinary member can send';
  exception when insufficient_privilege then null; end;
  update public.club_memberships set role='admin' where id=cm.id;
  update public.fixtures set cancelled_at=now() where id=f.id;
  begin
    perform public.send_fixture_instructions_update(f.id,'Denied',null,gen_random_uuid());
    raise exception 'FAIL cancelled fixture accepted';
  exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
end;
$test$;
rollback;
