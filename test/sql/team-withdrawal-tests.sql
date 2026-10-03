create temp table withdrawal_results(scenario text,passed boolean) on commit drop;
do $$
declare
 s uuid:='9e4386cc-e0cd-4582-ae9f-f80ef37c33bb'; f uuid:='0787fdcf-2e9f-432e-9215-6ea184a7e3b0';
 member uuid:='9b82f31d-b973-4640-bfb0-2ac58c790137';
 r1 uuid:='913ced30-4956-4166-bfa1-a9177d83567d'; r2 uuid:='c2d6ce71-9441-4c60-90c8-e2cad01dec6a';
 uid uuid; original jsonb; desired jsonb; members jsonb; assignments jsonb; ver bigint;
 result jsonb; n integer; nid uuid; message jsonb; mode text; rejected boolean;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must be disabled'; end if;
 select user_id into uid from member_profiles where id='42acb093-02d8-47cc-a43e-292bfa6cf17a';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 foreach mode in array array['unresolved','reassigned','reserve','removed','format_only'] loop
 begin
  select composition_version into ver from team_selections where id=s;
  select jsonb_agg(jsonb_build_object('id',id,'fixture_rink_no',fixture_rink_no,'format',format,'players_per_rink',players_per_rink,'home_rink_label',home_rink_label)) into original from fixture_rinks where fixture_id=f;
  select jsonb_agg(x) into desired from jsonb_array_elements(original) x where x->>'id'<>r2::text;
  select jsonb_agg(jsonb_build_object('member_profile_id',member_profile_id,'role',role,'is_selected',true)) into members from team_selection_members where team_selection_id=s and is_selected and role in ('player','reserve');
  select coalesce(jsonb_agg(jsonb_build_object('fixture_rink_id',fixture_rink_id,'position',position,'member_profile_id',member_profile_id)),'[]') into assignments from fixture_rink_assignments where fixture_id=f and fixture_rink_id<>r2;
  if mode='reassigned' then
   assignments:=assignments||jsonb_build_array(jsonb_build_object('fixture_rink_id',r1,'position',2,'member_profile_id',member));
  elsif mode='reserve' then
   select jsonb_agg(case when x->>'member_profile_id'=member::text then x||'{"role":"reserve"}' else x end) into members from jsonb_array_elements(members) x;
  elsif mode='removed' then
   select jsonb_agg(x) into members from jsonb_array_elements(members) x where x->>'member_profile_id'<>member::text;
  elsif mode='format_only' then
   select jsonb_agg(case when x->>'id'=r2::text then x||'{"format":"pairs","players_per_rink":2}' else x end) into desired from jsonb_array_elements(original)x;
   assignments:=assignments||jsonb_build_array(jsonb_build_object('fixture_rink_id',r2,'position',1,'member_profile_id',member));
  end if;
  select count(*) into n from notification_queue where fixture_id=f;
  set local role authenticated;
  if mode='unresolved' then
   rejected:=false;
   begin perform public.confirm_team_changes(s,ver,members,assignments,desired,original);
   exception when others then rejected:=sqlerrm like '%Resolve unpositioned%'; end;
   if not rejected then raise exception 'Unresolved save should fail'; end if;
   reset role;
   if (select composition_version from team_selections where id=s)<>ver then raise exception 'Failed save changed version'; end if;
  else
   result:=public.confirm_team_changes(s,ver,members,assignments,desired,original);
   reset role;
   if (result->>'composition_version')::bigint<>ver+1 then raise exception 'Version mismatch'; end if;
   if mode='format_only' then
    if (result->>'communications_queued')::integer<>0 then raise exception 'Format change notified'; end if;
   else
    if (result->>'communications_queued')::integer<>1 then raise exception 'Expected one communication: %',result; end if;
    if (select count(*) from notification_queue where fixture_id=f)<>n+1 then raise exception 'Duplicate event'; end if;
    select id,payload into nid,message from notification_queue where fixture_id=f and payload->>'change_kind'='team_withdrawn' and target_member_profile_id=member order by created_at desc limit 1;
    if nid is null or message->>'title'<>'Team withdrawn' or message->>'message' not like '%still going ahead%' then raise exception 'Missing withdrawal message'; end if;
    if mode='reassigned' and message->>'message' not like '%reassigned to Team 1%' then raise exception 'Missing reassignment'; end if;
    if mode='reserve' and message->>'message' not like '%now a reserve%' then raise exception 'Missing reserve'; end if;
    if mode='removed' and message->>'message' not like '%no longer required to play%' then raise exception 'Missing removal'; end if;
    if (message->>'team_sheet_required')::boolean is distinct from (mode<>'removed') then raise exception 'Wrong attachment requirement'; end if;
    set local role authenticated;
    result:=public.confirm_team_changes(s,ver,members,assignments,desired,original);
    reset role;
    if result->>'no_change'<>'true' or (select count(*) from notification_queue where fixture_id=f)<>n+1 then raise exception 'Retry duplicated message'; end if;
    perform set_config('app.notification_queue_ids',nid::text,true);
    perform public.process_notification_queue(1);
    if mode<>'removed' then
      if exists(select 1 from email_queue where fixture_id=f and member_profile_id=member and subject like 'Team withdrawn%' and created_at>=transaction_timestamp()) then raise exception 'Missing PDF should block email'; end if;
      update notification_queue set status='pending', payload=payload||jsonb_build_object(
        'attachments',jsonb_build_array(jsonb_set(
          (select payload->'attachments'->0 from notification_queue where id='441a45fd-f38d-4ee7-a6a9-b3e452b24f71'),
          '{compositionVersion}',to_jsonb(ver+1))),
        'team_sheet_composition_version',ver+1) where id=nid;
      perform public.process_notification_queue(1);
    end if;
    if not exists(select 1 from email_queue where fixture_id=f and member_profile_id=member and subject like 'Team withdrawn%' and created_at>=transaction_timestamp()) then raise exception 'Email missing'; end if;
   end if;
  end if;
  raise exception using errcode='ZX001',message='rollback successful scenario';
 exception when sqlstate 'ZX001' then null;
 end;
 insert into withdrawal_results values(mode,true);
 end loop;
end $$;
select * from withdrawal_results;
