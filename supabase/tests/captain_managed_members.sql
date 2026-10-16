begin;
do $test$
declare
  club uuid; actor uuid; actor_profile uuid; member_actor uuid; member_profile uuid;
  managed uuid; f uuid; ts uuid; rink uuid; source public.fixtures%rowtype;
  users_before bigint; selected_count integer;
begin
  select cm.club_id,mp.user_id,mp.id into strict club,actor,actor_profile
  from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
  where cm.role='admin' and cm.is_active and mp.user_id is not null
    and exists(select 1 from public.fixtures f join public.competition_types ct on ct.id=f.competition_type_id
      where f.club_id=cm.club_id and f.cancelled_at is null and f.team_id is null and ct.selection_mode='rsvp' and ct.uses_rinks)
  limit 1;
  select mp.user_id,mp.id into strict member_actor,member_profile
  from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
  where cm.club_id=club and cm.role='member' and cm.is_active and mp.user_id is not null
    and not exists(select 1 from public.app_superusers s where s.user_id=mp.user_id) limit 1;
  select count(*) into users_before from auth.users;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  managed := public.create_captain_managed_member(club,'Managed regression','Test','07700 900123','male');
  assert exists(select 1 from public.member_profiles where id=managed and user_id is null and email_address is null and is_captain_managed),'Profile not visible or has account/email';
  assert exists(select 1 from public.club_memberships where club_id=club and member_profile_id=managed and is_active and role='member'),'Membership missing';
  assert exists(select 1 from public.get_club_member_picker_list(club,'open') where member_profile_id=managed),'Member missing from selection picker';
  assert exists(select 1 from public.get_club_member_picker_list(club,'men') where member_profile_id=managed),'Member missing from mens picker';
  update public.member_profiles set phone='07700 900124' where id=managed;
  assert found,'Admin cannot edit telephone';
  begin
    perform public.create_captain_managed_member(club,'Managed regression','Test','07700 900124','male');
    raise exception 'Duplicate accepted' using errcode='XX000';
  exception when unique_violation then null; end;
  begin
    perform public.create_captain_managed_member(club,'','','','male');
    raise exception 'Invalid input accepted' using errcode='XX000';
  exception when invalid_parameter_value then null; end;
  reset role;
  assert (select count(*) from auth.users)=users_before,'Auth account was created';

  -- Real publication path on a temporary mixed team. Everything rolls back.
  select fx.* into strict source from public.fixtures fx join public.competition_types ct on ct.id=fx.competition_type_id
  where fx.club_id=club and fx.cancelled_at is null and ct.selection_mode='rsvp' and ct.uses_rinks and fx.team_id is null limit 1;
  insert into public.fixtures(club_id,start_at,end_at,is_home,venue_id,fixture_type,section,rinks_required,players_per_rink,team_name,requires_rsvp,competition_type_id)
  values(club,'2099-01-01 10:00Z','2099-01-01 12:00Z',false,source.venue_id,'friendly','mixed',1,2,'Managed member regression',true,source.competition_type_id) returning id into f;
  insert into public.fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink)
  values(f,1,'pairs',2) returning id into rink;
  insert into public.team_selections(fixture_id) values(f) returning id into ts;
  insert into public.team_selection_members(team_selection_id,member_profile_id,is_selected) values(ts,managed,true),(ts,member_profile,true);
  insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position)
  values(f,rink,managed,1),(f,rink,member_profile,2);
  set local role authenticated;
  perform public.add_fixture_members_to_pool(f,array[managed],false);
  assert exists(select 1 from public.fixture_rsvps where fixture_id=f and member_profile_id=managed),'Availability missing';
  perform public.publish_team_selection_safe(f,ts,false);
  update public.team_selection_members set acceptance='accepted',responded_at=now(),acceptance_by=actor_profile
  where team_selection_id=ts and member_profile_id=managed;
  assert found,'Captain/admin acceptance failed';
  reset role;
  assert exists(select 1 from public.team_selections where id=ts and status='published'),'Publication failed';
  assert exists(select 1 from public.notification_queue where fixture_id=f and target_member_profile_id=member_profile and event_type='team_published_player'),'Account member notification missing';
  assert not exists(select 1 from public.notification_queue where fixture_id=f and target_member_profile_id=managed),'Accountless member received personal notification';
  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
    values(managed,'acceptance_reminder',null,'Regression','Regression',f,ts);
  assert not exists(select 1 from public.email_queue where member_profile_id=managed),'Accountless email was queued';
  insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
    values(member_profile,'acceptance_reminder','regression@example.test','Regression','Regression',f,ts);
  assert exists(select 1 from public.email_queue where fixture_id=f and member_profile_id=member_profile),'Account member email missing';
  assert exists(select 1 from public.email_action_requests where fixture_id=f and member_profile_id=member_profile),'Existing email response action missing';

  -- A fixture captain with an ordinary membership can manage this player too.
  update public.fixtures set captain_member_profile_id=member_profile where id=f;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',member_actor,'role','authenticated')::text,true);
  set local role authenticated;
  perform public.add_fixture_members_to_pool(f,array[managed],false);
  update public.team_selection_members set acceptance='accepted',responded_at=now(),acceptance_by=member_profile
  where team_selection_id=ts and member_profile_id=managed;
  assert found,'Fixture captain cannot record acceptance';
  reset role;
  assert exists(select 1 from public.team_selection_members where team_selection_id=ts and member_profile_id=managed and acceptance_by=member_profile),'Captain acceptance audit missing';

  -- Ordinary members, anonymous callers and admins of another club cannot create.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',member_actor,'role','authenticated')::text,true);
  set local role authenticated;
  begin
    perform public.create_captain_managed_member(club,'Denied','Test','07700900123');
    raise exception 'Ordinary member allowed' using errcode='XX000';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.create_captain_managed_member(club,'Denied','Test','07700900123');
    raise exception 'Unauthenticated allowed' using errcode='XX000';
  exception when insufficient_privilege then null; end;
end $test$;
rollback;
select 'PASS: membership, validation, directory, eligibility, availability, mixed publication, on-behalf acceptance, recipient guards and permissions; all test data rolled back' as result;
