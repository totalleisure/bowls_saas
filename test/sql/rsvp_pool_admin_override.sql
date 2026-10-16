begin;
do $test$
declare v_fixture_id uuid; club uuid; actor uuid; target uuid; member_actor uuid; selector_actor uuid; row_id uuid; after_id uuid; answer text;
begin
 select f.id,f.club_id,mp.user_id into strict v_fixture_id,club,actor
 from public.fixtures f join public.competition_types ct on ct.id=f.competition_type_id
 join public.club_memberships cm on cm.club_id=f.club_id join public.member_profiles mp on mp.id=cm.member_profile_id
 where ct.selection_mode='rsvp' and ct.uses_rinks and f.team_id is null and f.cancelled_at is null
 and f.archived_at is null and cm.is_active and cm.role::text='admin' and mp.user_id is not null limit 1;
 select mp.id,mp.user_id into strict target,member_actor from public.member_profiles mp
 join public.club_memberships cm on cm.member_profile_id=mp.id where cm.club_id=club and cm.is_active
 and cm.role::text='member' and mp.user_id is not null
 and not exists(select 1 from public.app_superusers s where s.user_id=mp.user_id) limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 insert into public.fixture_rsvps(fixture_id,member_profile_id,status) values(v_fixture_id,target,'no')
 on conflict(fixture_id,member_profile_id) do update set status='no' returning id into row_id;
 begin
   perform public.add_fixture_members_to_pool(v_fixture_id,array[target],false);
   raise exception 'Expected override confirmation rejection' using errcode='XX000';
 exception when raise_exception then null; end;
 perform public.add_fixture_members_to_pool(v_fixture_id,array[target],true);
 select id,status::text into after_id,answer from public.fixture_rsvps r where r.fixture_id=v_fixture_id and member_profile_id=target;
 assert after_id=row_id and answer='maybe', 'Override must update same row';
 perform public.add_fixture_members_to_pool(v_fixture_id,array[target],false);
 update public.fixture_rsvps r set status='yes' where r.fixture_id=v_fixture_id and member_profile_id=target;
 perform public.add_fixture_members_to_pool(v_fixture_id,array[target],true);
 select status::text into answer from public.fixture_rsvps r where r.fixture_id=v_fixture_id and member_profile_id=target;
 assert answer='yes','Available must not be downgraded';
 select mp.user_id into selector_actor from public.member_profiles mp join public.club_memberships cm
 on cm.member_profile_id=mp.id where cm.club_id=club and cm.is_active and cm.role::text='selector'
 and not exists(select 1 from public.app_superusers s where s.user_id=mp.user_id) limit 1;
 if selector_actor is not null then
   perform set_config('request.jwt.claims',jsonb_build_object('sub',selector_actor,'role','authenticated')::text,true);
   begin
    perform public.add_fixture_members_to_pool(v_fixture_id,array[target],true);
    raise exception 'Selector override allowed' using errcode='XX000';
   exception when insufficient_privilege then null; end;
 end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',member_actor,'role','authenticated')::text,true);
 begin
  perform public.add_fixture_members_to_pool(v_fixture_id,array[target],true);
  raise exception 'Member override allowed' using errcode='XX000';
 exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{}',true);
 begin
  perform public.add_fixture_members_to_pool(v_fixture_id,array[target],true);
  raise exception 'Anonymous override allowed' using errcode='XX000';
 exception when insufficient_privilege then null; end;
end;
$test$;
rollback;
