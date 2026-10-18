begin;
do $test$
declare fid uuid; sid uuid; mid uuid; actor uuid; queues bigint; unchanged text;
begin
 select f.id,s.id,m.member_profile_id into fid,sid,mid
 from public.fixtures f join public.competition_types ct on ct.id=f.competition_type_id
 join public.team_selections s on s.fixture_id=f.id join public.team_selection_members m on m.team_selection_id=s.id
 where f.team_id is null and ct.selection_mode='rsvp' and ct.uses_rinks and f.cancelled_at is null and f.archived_at is null
 and m.acceptance='declined' and not m.is_selected
 and exists(select 1 from public.club_memberships cm where cm.club_id=f.club_id and cm.member_profile_id=m.member_profile_id and cm.is_active and cm.role::text<>'guest')
 and not exists(select 1 from public.fixture_rink_assignments a join public.fixture_rinks r on r.id=a.fixture_rink_id where r.fixture_id=f.id and a.member_profile_id=m.member_profile_id)
 limit 1;
 if fid is null then raise exception 'No removed declined RSVP player available for rollback test'; end if;
 select user_id into actor from public.app_superusers limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 select count(*) into queues from public.notification_queue;
 select md5(coalesce(string_agg(to_jsonb(m)::text,',' order by m.id),'')) into unchanged from public.team_selection_members m where m.team_selection_id=sid and m.member_profile_id<>mid;
 begin
  perform public.add_fixture_members_to_pool_reviewed(fid,array[mid],true,false);
  raise exception 'Unconfirmed re-add succeeded';
 exception when raise_exception then
  if sqlerrm not like '%previously declined%' then raise; end if;
 end;
 if not exists(select 1 from public.team_selection_members where team_selection_id=sid and member_profile_id=mid and acceptance='declined' and not is_selected) then raise exception 'Refused operation altered player'; end if;
 perform public.add_fixture_members_to_pool_reviewed(fid,array[mid],true,true);
 if not exists(select 1 from public.team_selection_members where team_selection_id=sid and member_profile_id=mid and acceptance='pending' and not is_selected and responded_at is null and acceptance_by is null) then raise exception 'Player did not return unselected/pending'; end if;
 if not exists(select 1 from public.fixture_rsvps where fixture_id=fid and member_profile_id=mid and status::text in ('yes','maybe')) then raise exception 'Player missing from available pool'; end if;
 if (select count(*) from public.notification_queue)<>queues then raise exception 'Re-add sent an unwanted notification'; end if;
 if (select md5(coalesce(string_agg(to_jsonb(m)::text,',' order by m.id),'')) from public.team_selection_members m where m.team_selection_id=sid and m.member_profile_id<>mid)<>unchanged then raise exception 'Another response changed'; end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin
  perform public.add_fixture_members_to_pool_reviewed(fid,array[mid],false,true);
  raise exception 'Unauthorized operation succeeded';
 exception when insufficient_privilege then null;
 end;
end $test$;
select 'PASS: explicit confirmation, durable available pool, unselected/pending response, unchanged teammates, no notifications and permission checks' result;
rollback;
