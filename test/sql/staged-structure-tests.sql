create temp table staged_results(test text,passed boolean) on commit drop;
grant all on staged_results to authenticated;
do $$
declare
 s uuid:='9e4386cc-e0cd-4582-ae9f-f80ef37c33bb';
 f uuid:='0787fdcf-2e9f-432e-9215-6ea184a7e3b0';
 sue uuid:='c296621d-2ccf-4c1d-8333-95ec75208413';
 r uuid:='913ced30-4956-4166-bfa1-a9177d83567d';
 uid uuid; original jsonb; desired jsonb; members jsonb; assignments jsonb;
 old_assignments jsonb; version bigint; result jsonb; n integer; rejected boolean; added uuid:=gen_random_uuid();
 nid uuid; processor integer; before_members jsonb;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Disable cron'; end if;
 select user_id into uid from public.member_profiles where id='42acb093-02d8-47cc-a43e-292bfa6cf17a';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 select composition_version into version from public.team_selections where id=s;
 select jsonb_agg(jsonb_build_object('id',id,'fixture_rink_no',fixture_rink_no,'format',format,
   'players_per_rink',players_per_rink,'home_rink_label',home_rink_label)) into original from public.fixture_rinks where fixture_id=f;
 select jsonb_agg(jsonb_build_object('member_profile_id',member_profile_id,'role',role,'is_selected',true))
   into members from public.team_selection_members where team_selection_id=s and is_selected and role in ('player','reserve');
 before_members:=members;
 select jsonb_agg(jsonb_build_object('fixture_rink_id',fixture_rink_id,'position',position,'member_profile_id',member_profile_id))
   into old_assignments from public.fixture_rink_assignments where fixture_id=f;
 select jsonb_agg(case when x->>'id'=r::text then x||'{"format":"pairs","players_per_rink":2}' else x end)
   into desired from jsonb_array_elements(original) x;
 select jsonb_agg(case when x->>'fixture_rink_id'=r::text and x->>'position'='3' then x||'{"position":2}' else x end)
   into assignments from jsonb_array_elements(old_assignments) x where x->>'member_profile_id'<>sue::text;
 select count(*) into n from public.notification_queue;
 set local role authenticated;
 rejected:=false;
 begin perform public.confirm_team_changes(s,version,members,assignments,desired,original);
 exception when others then rejected:=sqlerrm like '%Resolve unpositioned%'; end;
 insert into staged_results values('unresolved displaced player blocked',rejected);
 reset role;
 insert into staged_results select 'failed confirm leaves structure unchanged',players_per_rink=3 from public.fixture_rinks where id=r;
 insert into staged_results select 'failed confirm queues nothing',count(*)=n from public.notification_queue;
 select jsonb_agg(case when x->>'member_profile_id'=sue::text then x||'{"role":"reserve"}' else x end)
   into members from jsonb_array_elements(members) x;
 set local role authenticated;
 result:=public.confirm_team_changes(s,version,members,assignments,desired,original);
 reset role;
 insert into staged_results values('one version for combined reduction and reserve', (result->>'composition_version')::bigint=version+1);
 insert into staged_results select 'reduction saved',players_per_rink=2 and format='pairs' from public.fixture_rinks where id=r;
 insert into staged_results select 'skip retained at final position',member_profile_id='42acb093-02d8-47cc-a43e-292bfa6cf17a' from public.fixture_rink_assignments where fixture_rink_id=r and position=2;
 insert into staged_results select 'one final reserve event',count(*)=n+1 from public.notification_queue;
 select id into nid from public.notification_queue where fixture_id=f and event_type='team_published_reserve' and target_member_profile_id=sue order by created_at desc limit 1;
 insert into staged_results select 'reserve requires rebuilt sheet',payload->>'team_sheet_required'='true' and not(payload?'attachments') from public.notification_queue where id=nid;
 set local role authenticated;
 result:=public.confirm_team_changes(s,version,members,assignments,desired,original);
 reset role;
 insert into staged_results values('retry no duplicate',result->>'no_change'='true');
 insert into staged_results select 'retry queue stable',count(*)=n+1 from public.notification_queue;
 set local role authenticated;
 rejected:=false;
 begin perform public.confirm_team_changes(s,version,before_members,old_assignments,original,original);
 exception when others then rejected:=sqlerrm like '%TEAM_COMPOSITION_VERSION_CONFLICT%'; end;
 insert into staged_results values('stale editor rejected',rejected);
 reset role;
 original:=desired; version:=version+1;
 -- Adding then deleting a team participates in exactly the same transaction.
 desired:=original||jsonb_build_array(jsonb_build_object('id',added,'fixture_rink_no',3,'format','singles','players_per_rink',1,'home_rink_label',null));
 set local role authenticated;
 result:=public.confirm_team_changes(s,version,members,assignments,desired,original);
 reset role;
 insert into staged_results select 'new team created',count(*)=1 from public.fixture_rinks where id=added;
 insert into staged_results values('add increments once',(result->>'composition_version')::bigint=version+1);
 version:=version+1;
 set local role authenticated;
 result:=public.confirm_team_changes(s,version,members,assignments,original,desired);
 reset role;
 insert into staged_results select 'team delete committed',count(*)=0 from public.fixture_rinks where id=added;
 version:=version+1;
 -- Explicit removal receives a single final dropped message, not a reserve notice.
 select jsonb_agg(x) into members from jsonb_array_elements(members) x where x->>'member_profile_id'<>sue::text;
 set local role authenticated;
 result:=public.confirm_team_changes(s,version,members,assignments,original,original);
 reset role;
 insert into staged_results values('explicit drop queues one final event',result->>'dropped'='1' and result->>'communications_queued'='1');
 select id into nid from public.notification_queue where fixture_id=f and target_member_profile_id=sue
   and payload->>'change_kind'='removed_from_selection' order by created_at desc limit 1;
 perform set_config('app.notification_queue_ids',nid::text,true);
 processor:=public.process_notification_queue(1);
 insert into staged_results values('drop processing succeeds',processor=1);
 insert into staged_results select 'drop email queued',exists(select 1 from public.email_queue where fixture_id=f
   and member_profile_id=sue and event_type='fixture_message' and subject like 'Team selection changed%');
 insert into staged_results select 'outdated reserve notice cancelled',not exists(select 1 from public.notification_queue
   where fixture_id=f and target_member_profile_id=sue and event_type='team_published_reserve' and status='pending');
 version:=(result->>'composition_version')::bigint;
 select count(*) into n from public.notification_queue;
 -- A late capacity failure must roll back already-applied structure and membership work.
 select original||jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'fixture_rink_no',i,
   'format','singles','players_per_rink',1,'home_rink_label',null)) into desired from generate_series(3,7) i;
 set local role authenticated;
 rejected:=false;
 begin perform public.confirm_team_changes(s,version,members,assignments,desired,original);
 exception when others then rejected:=sqlerrm like '%Not enough rinks%'; end;
 insert into staged_results values('late capacity error rejects transaction',rejected);
 reset role;
 insert into staged_results select 'late error retains two teams',count(*)=2 from public.fixture_rinks where fixture_id=f;
 insert into staged_results select 'late error version unchanged',composition_version=version from public.team_selections where id=s;
 insert into staged_results select 'late error queues unchanged',count(*)=n from public.notification_queue;
 -- Physical edits from the older fixture-details screen do not bump version.
 update public.fixture_rinks set home_rink_label='R6' where id=r;
 set local role authenticated;
 rejected:=false;
 begin perform public.confirm_team_changes(s,version,members,assignments,original,original);
 exception when others then rejected:=sqlerrm like '%TEAM_COMPOSITION_VERSION_CONFLICT%'; end;
 insert into staged_results values('physical baseline conflict rejected',rejected);
 reset role;
 update public.fixture_rinks set home_rink_label=(select x->>'home_rink_label' from jsonb_array_elements(original) x where x->>'id'=r::text) where id=r;
 select jsonb_agg(case when x->>'id'=r::text then x||'{"home_rink_label":"R2"}' else x end)
   into desired from jsonb_array_elements(original) x;
 insert into public.green_rink_maintenance(club_id,green_area_id,rink_number,start_at,end_at,reason)
 select club_id,green_area_id,2,start_at,end_at,'ROLLBACK staged conflict' from public.fixtures where id=f;
 set local role authenticated;
 rejected:=false;
 begin perform public.confirm_team_changes(s,version,members,assignments,desired,original);
 exception when others then rejected:=sqlerrm like '%not available%'; end;
 insert into staged_results values('maintenance conflict rejected at confirm',rejected);
 reset role;
 -- Anonymous and ordinary-member callers must not gain new mutation powers.
 set local role anon;
 rejected:=false;
 begin perform public.confirm_team_changes(s,version,members,assignments,original,original);
 exception when insufficient_privilege then rejected:=true; end;
 reset role;
 insert into staged_results values('anonymous cannot execute',rejected);
 select user_id into uid from public.member_profiles where id='9b82f31d-b973-4640-bfb0-2ac58c790137';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 set local role authenticated;
 rejected:=false;
 begin perform public.confirm_team_changes(s,version,members,assignments,original,original);
 exception when others then rejected:=sqlerrm like '%permission%'; end;
 insert into staged_results values('ordinary member denied',rejected);
 reset role;
 if exists(select 1 from staged_results where not passed or passed is null) then
   raise exception 'Staged structure tests failed: %',(select jsonb_agg(test) from staged_results where not passed or passed is null);
 end if;
end $$;
select * from staged_results;
