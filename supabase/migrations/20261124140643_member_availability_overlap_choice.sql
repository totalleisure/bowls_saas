-- The same stage rules as Dashboard/details, including a published reschedule.
create function public.my_fixture_availability_stage(p_fixture uuid)
returns boolean language sql stable security invoker set search_path='' as $stage$
 select auth.uid() is not null and exists(
  select 1 from public.fixtures f join public.member_profiles mp on mp.id=public.my_member_profile_id()
  join public.club_memberships cm on cm.member_profile_id=mp.id and cm.club_id=f.club_id
  where f.id=p_fixture and f.cancelled_at is null and f.rescheduled_to_fixture_id is null
   and cm.is_active and cm.role::text<>'guest'
   and (lower(coalesce(f.section::text,'open')) in ('','open','mixed') or
    (lower(f.section::text) in ('mens','men','male') and lower(mp.sex_at_birth::text) in ('male','m')) or
    (lower(f.section::text) in ('ladies','women','female') and lower(mp.sex_at_birth::text) in ('female','f')))
   and (f.rescheduled_from_fixture_id is not null or not exists(
    select 1 from public.team_selections ts where ts.fixture_id=f.id and ts.status::text='published'))
   and not exists(select 1 from public.team_selections ts join public.team_selection_members sm on sm.team_selection_id=ts.id
    where ts.fixture_id=f.id and ts.status::text='published' and sm.member_profile_id=mp.id and sm.is_selected)
 );
$stage$;
revoke all on function public.my_fixture_availability_stage(uuid) from public,anon;
grant execute on function public.my_fixture_availability_stage(uuid) to authenticated;

-- Availability only: never change team selections or acceptance records.
create function public.set_my_fixture_availability(p_fixture uuid, p_status text, p_confirmation text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 member_id uuid; target public.fixtures%rowtype; target_end timestamptz;
 target_uses_rinks boolean; peers jsonb := '[]'; conflicts jsonb; token text; chosen jsonb; changes jsonb := '[]'; peer record;
begin
 if auth.uid() is null then raise exception 'Sign in to respond' using errcode='42501'; end if;
 member_id := public.my_member_profile_id();
 if member_id is null or p_status not in ('yes','no','maybe') or p_status is null then raise exception 'Invalid availability response'; end if;
 perform pg_advisory_xact_lock(hashtextextended('member-availability:'||member_id,0));
 select * into target from public.fixtures where id=p_fixture;
 if not found or target.cancelled_at is not null or not exists(
  select 1 from public.club_memberships cm where cm.club_id=target.club_id and cm.member_profile_id=member_id and cm.is_active and cm.role::text<>'guest'
 ) then raise exception 'Active club membership is required' using errcode='42501'; end if;
 if not public.my_fixture_availability_stage(p_fixture) then raise exception 'Availability is closed for this fixture. Please refresh and use the selection response if you have been selected.' using errcode='23514'; end if;
 select jsonb_build_object('fixture_id',target.id,'club',c.name,'type',t.name,'venue',v.name,'is_home',target.is_home,'start_at',target.start_at,'end_at',target.end_at) into chosen from public.clubs c left join public.competition_types t on t.id=target.competition_type_id left join public.venues v on v.id=target.venue_id where c.id=target.club_id;
 select coalesce(t.uses_rinks,true), coalesce(target.end_at,target.start_at+make_interval(mins=>coalesce(t.default_duration_minutes,120)))
 into target_uses_rinks,target_end from public.competition_types t where t.id=target.competition_type_id;
 target_end := coalesce(target_end,target.start_at+interval '2 hours');
 if p_status='yes' and coalesce(target_uses_rinks,true) then
  select coalesce(jsonb_agg(jsonb_build_object('fixture_id',f.id,'club',c.name,'type',t.name,'venue',v.name,'is_home',f.is_home,
    'start_at',f.start_at,'end_at',coalesce(f.end_at,f.start_at+make_interval(mins=>coalesce(t.default_duration_minutes,120))),'status',r.status) order by f.start_at,f.id),'[]')
  into peers
  from public.fixtures f join public.clubs c on c.id=f.club_id
  join public.competition_types t on t.id=f.competition_type_id
  left join public.venues v on v.id=f.venue_id
  left join public.fixture_rsvps r on r.fixture_id=f.id and r.member_profile_id=member_id
  where f.id<>p_fixture and public.my_fixture_availability_stage(f.id) and coalesce(t.uses_rinks,true)
    and (f.requires_rsvp or r.id is not null)
    and f.start_at<target_end and coalesce(f.end_at,f.start_at+make_interval(mins=>coalesce(t.default_duration_minutes,120)))>target.start_at
    and exists(select 1 from public.club_memberships cm where cm.club_id=f.club_id and cm.member_profile_id=member_id and cm.is_active and cm.role::text<>'guest')
    and (lower(coalesce(f.section::text,'open')) in ('','open','mixed') or exists(
      select 1 from public.member_profiles mp where mp.id=member_id and
       ((lower(f.section::text) in ('mens','men','male') and lower(mp.sex_at_birth::text) in ('male','m')) or
        (lower(f.section::text) in ('ladies','women','female') and lower(mp.sex_at_birth::text) in ('female','f')))));
  select coalesce(jsonb_agg(x order by x->>'fixture_id'),'[]') into conflicts
    from jsonb_array_elements(peers) x where x->>'status'='yes';
  token := md5(jsonb_build_object('member',member_id,'chosen',chosen,'conflicts',conflicts)::text);
  if jsonb_array_length(conflicts)>0 and token is distinct from p_confirmation then
   return jsonb_build_object('saved',false,'conflicts',conflicts,'chosen',chosen,'confirmation',token);
  end if;
  for peer in select x from jsonb_array_elements(peers) x loop
   insert into public.fixture_rsvps(fixture_id,member_profile_id,status,responded_at)
   values((peer.x->>'fixture_id')::uuid,member_id,'no',now())
   on conflict(fixture_id,member_profile_id) do update set status='no',responded_at=excluded.responded_at where fixture_rsvps.status<>'no';
   changes := changes || jsonb_build_array(jsonb_build_object('fixture_id',peer.x->>'fixture_id','status','no'));
  end loop;
 end if;
 insert into public.fixture_rsvps(fixture_id,member_profile_id,status,responded_at)
 values(p_fixture,member_id,p_status::public.rsvp_status,now())
 on conflict(fixture_id,member_profile_id) do update set status=excluded.status,responded_at=excluded.responded_at;
 return jsonb_build_object('saved',true,'changes',changes||jsonb_build_array(jsonb_build_object('fixture_id',p_fixture,'status',p_status)));
end $$;
revoke all on function public.set_my_fixture_availability(uuid,text,text) from public,anon;
grant execute on function public.set_my_fixture_availability(uuid,text,text) to authenticated;

-- Old clients must not silently create two Available responses either.
create function club_setup_private.guard_overlapping_availability()
returns trigger language plpgsql security invoker set search_path='' as $$
declare target public.fixtures%rowtype; target_end timestamptz; uses_rinks boolean;
begin
 if new.status::text<>'yes' or new.member_profile_id is distinct from public.my_member_profile_id() then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended('member-availability:'||new.member_profile_id,0));
 select * into target from public.fixtures where id=new.fixture_id;
 select coalesce(t.uses_rinks,true),coalesce(target.end_at,target.start_at+make_interval(mins=>coalesce(t.default_duration_minutes,120)))
 into uses_rinks,target_end from public.competition_types t where t.id=target.competition_type_id;
 if not public.my_fixture_availability_stage(new.fixture_id) or not coalesce(uses_rinks,true) then return new; end if;
 if exists(select 1 from public.fixture_rsvps r join public.fixtures f on f.id=r.fixture_id
  join public.competition_types t on t.id=f.competition_type_id
  where r.member_profile_id=new.member_profile_id and r.status::text='yes' and f.id<>new.fixture_id
   and public.my_fixture_availability_stage(f.id) and coalesce(t.uses_rinks,true)
   and f.start_at<coalesce(target_end,target.start_at+interval '2 hours')
   and coalesce(f.end_at,f.start_at+make_interval(mins=>coalesce(t.default_duration_minutes,120)))>target.start_at
   and exists(select 1 from public.club_memberships cm where cm.club_id=f.club_id and cm.member_profile_id=new.member_profile_id and cm.is_active and cm.role::text<>'guest'))
 then raise exception 'You are already available for an overlapping fixture. Refresh the app and choose which match to keep.' using errcode='23514'; end if;
 return new;
end $$;
revoke all on function club_setup_private.guard_overlapping_availability() from public,anon,authenticated,service_role;
create trigger zz_guard_overlapping_availability before insert or update of status on public.fixture_rsvps
for each row execute function club_setup_private.guard_overlapping_availability();
