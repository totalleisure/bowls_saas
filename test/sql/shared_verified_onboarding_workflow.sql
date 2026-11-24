begin;
do $test$
declare secretary public.member_profiles%rowtype; existing public.member_profiles%rowtype;
 rid uuid:=gen_random_uuid(); req uuid:=gen_random_uuid(); c uuid; direct_club uuid;
 payload jsonb; place jsonb; result jsonb; previous_memberships jsonb; contacts jsonb;
 users_before bigint; email_before bigint; lists_before bigint; i integer;
begin
 select p.* into strict secretary from public.member_profiles p join auth.users a on a.id=p.user_id
 where lower(p.email_address)<>'wayne@totalleisure.com' and not a.is_anonymous and a.email_confirmed_at is not null
 and p.first_name is not null and p.last_name is not null limit 1;
 select p.* into strict existing from public.member_profiles p join auth.users a on a.id=p.user_id
 where p.id<>secretary.id and lower(p.email_address)<>'wayne@totalleisure.com' and not a.is_anonymous
 and p.first_name is not null and p.last_name is not null
 and (select count(*) from public.member_profiles q where lower(btrim(q.email_address))=lower(btrim(p.email_address)))=1
 and exists(select 1 from public.club_memberships cm where cm.member_profile_id=p.id) limit 1;
 select jsonb_agg(to_jsonb(cm) order by cm.id) into previous_memberships from public.club_memberships cm where member_profile_id=existing.id;
 select count(*) into users_before from auth.users;
 select count(*) into email_before from public.email_queue;
 place:=jsonb_build_object('placeId','rollback_'||rid,'name','Verified rollback club '||rid,'addressLine1','1 Test Green','addressLine2','','townCity','Test Town','postcode',left(rid::text,8));
 insert into club_setup_private.registrations(id,place,email,first_name,last_name,phone,authority,verified_at)
 values(rid,place,lower(btrim(secretary.email_address)),secretary.first_name,secretary.last_name,'07700123456',true,now());
 contacts:=jsonb_build_array(jsonb_build_object('first_name',existing.first_name,'last_name',existing.last_name,'email',existing.email_address));
 for i in 1..6 loop
  contacts:=contacts||jsonb_build_array(jsonb_build_object('first_name','Rollback','last_name','Member '||i,'email','rollback-'||rid||'-'||i||'@example.invalid'));
 end loop;
 payload:=jsonb_build_object('registration_id',rid,'name',place->>'name','venue_name',place->>'name','address_line1','1 Test Green','address_line2','','town_city','Test Town','postcode',place->>'postcode','google_place_id',place->>'placeId','green_name','Main green','discipline','indoor','rink_count',6,'start_time','09:00','end_time','22:00','activities','["rollups","drives","aggregates","friendlies","leagues","internal","nationals","coaching","practice","trials","bookings","committee","social","meals","fundraising","agm","other"]'::jsonb,'members',contacts);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',secretary.user_id,'role','authenticated')::text,true);
 perform set_config('role','authenticated',true);
 assert public.my_staging_club_registration() is not null,'Verified secretary cannot enter setup';
 result:=public.create_staging_club_onboarding(req,payload); c:=(result->>'club_id')::uuid;
 assert (public.create_staging_club_onboarding(req,payload)->>'reused')::boolean,'Retry duplicated club';
 perform set_config('role','postgres',true);
 assert (select count(*) from public.competition_types where club_id=c)=17,'Fixture choices lost';
 assert not exists(select 1 from public.competition_types t join club_setup_private.onboarding_participation_defaults() d on lower(d.fixture_name)=lower(t.name) where t.club_id=c and (t.selection_mode is distinct from d.participation_mode or not t.team_selection_enabled or t.lock_participation)),'Fresh club participation mapping incorrect';
 assert (select count(*) from public.competition_types where club_id=c and bookable_by_members and default_rinks_required=1 and default_players_per_rink=1 and default_format='singles' and not lock_participation and selection_mode='preselect')=4,'Member booking defaults incorrect';
 assert (select count(*) from public.club_memberships where club_id=c and is_active)=2,'Only Secretary and platform owner should be active';
 assert exists(select 1 from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id where cm.club_id=c and p.id=secretary.id and cm.role='admin' and cm.is_active),'Secretary admin missing';
 assert exists(select 1 from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id where cm.club_id=c and lower(p.email_address)='wayne@totalleisure.com' and cm.role='admin' and cm.is_active),'Wayne admin missing';
 assert exists(select 1 from public.club_memberships where club_id=c and member_profile_id=existing.id and role='member' and not is_active),'Recognition did not create inactive Member';
 assert (select count(*) from public.club_onboarding_pending_members where club_id=c)=7,'Seven contacts not saved';
 assert (select count(*) from public.mailing_lists where club_id=c)=12,'Mailing list defaults missing';
 assert (select jsonb_agg(to_jsonb(cm) order by cm.id) from public.club_memberships cm where member_profile_id=existing.id and club_id<>c)=previous_memberships,'Other memberships changed';
 assert (select count(*) from public.email_queue)=email_before,'Setup queued invitations';
 assert (select count(*) from auth.users)=users_before,'Setup created Auth accounts';
 assert (select consumed_at is not null and club_id=c from club_setup_private.registrations where id=rid),'Verification not consumed';
 assert not has_function_privilege('anon','public.create_staging_club_onboarding(uuid,jsonb)','execute'),'Anonymous creation exposed';
 assert not has_function_privilege('authenticated','public.staging_registration_service(text,jsonb)','execute'),'Client can bypass verification';
 insert into public.clubs(name) values('Direct creation rollback '||rid) returning id into direct_club;
 assert exists(select 1 from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id where cm.club_id=direct_club and lower(p.email_address)='wayne@totalleisure.com' and cm.role='admin' and cm.is_active),'Other club creation path missed Wayne';
end $test$;
rollback;
select 'PASS: verified non-Wayne Secretary, two admins, 7 inactive contacts, Member recognition, 17 types, 12 lists, no mail/Auth, duplicate retry and all-creation owner admin; rolled back' result;

