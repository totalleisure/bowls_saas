-- Run inside a transaction and roll back. Only synthetic member/fixtures.
do $$
declare
  club uuid; ft uuid; green uuid; label text; venue uuid;
  u uuid:=gen_random_uuid(); actor uuid; f uuid; started timestamptz:='2031-01-14 10:00Z';
  before_fixtures bigint; emails bigint; notices bigint; rejected boolean:=false;
begin
  select ct.club_id,ct.id into strict club,ft from public.competition_types ct
    where ct.is_active and ct.is_internal and ct.bookable_by_members and ct.uses_rinks
      and ct.team_selection_enabled and ct.selection_mode='preselect' limit 1;
  select ga.id,v.id into strict green,venue from public.green_areas ga join public.venues v on v.id=ga.venue_id
    where ga.club_id=club and v.is_home_venue and ga.rink_count>0 limit 1;
  select rink_label into strict label from public.get_green_rink_availability(green,started,started+interval '150 minutes')
    where not is_booked and free_capacity_rinks>0 limit 1;
  insert into auth.users(id,email,raw_user_meta_data) values(u,'member-booking-'||u||'@example.invalid',
    jsonb_build_object('first_name','Synthetic','last_name','Rink Booker'));
  select id into actor from public.member_profiles where user_id=u;
  if actor is null then insert into public.member_profiles(user_id,display_name,first_name,last_name)
    values(u,'Synthetic Rink Booker','Synthetic','Rink Booker') returning id into actor; end if;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,actor,'member',true);
  select count(*) into emails from public.email_queue;
  select count(*) into notices from public.notification_queue;
  perform set_config('request.jwt.claim.sub',u::text,true);
  execute 'set local role authenticated';
  f:=public.create_member_rink_booking(club,ft,green,started,label);
  if not exists(select 1 from public.fixtures where id=f and captain_member_profile_id=actor
    and rinks_required=1 and end_at-start_at=interval '150 minutes' and requires_rsvp=false)
    then raise exception 'Fixture not saved for member with expected duration/captain'; end if;
  if not exists(select 1 from public.fixture_rinks where fixture_id=f and home_rink_label=label)
    then raise exception 'Selected physical rink not saved'; end if;
  if not exists(select 1 from public.team_selections where fixture_id=f and status='published')
    then raise exception 'Preselect setup missing'; end if;
  if not exists(select 1 from public.fixture_rink_assignments where fixture_id=f
    and member_profile_id=actor and position=1) then raise exception 'Booking player missing'; end if;
  if not exists(select 1 from public.team_selection_members sm join public.team_selections ts
    on ts.id=sm.team_selection_id where ts.fixture_id=f and sm.member_profile_id=actor
    and sm.is_selected and sm.acceptance='accepted') then raise exception 'Booking member not accepted'; end if;
  begin
    perform public.create_member_rink_booking(club,ft,green,started,label);
  exception when others then
    if sqlerrm not like '%no longer available%' then raise; end if;
    rejected:=true;
  end;
  if not rejected then raise exception 'Duplicate physical booking allowed'; end if;
  -- Exact end/start boundary remains usable on the same rink.
  perform public.create_member_rink_booking(club,ft,green,started+interval '150 minutes',label);
  execute 'reset role';
  if (select count(*) from public.fixtures where created_by_user_id=u)<>2 then
    raise exception 'Failed booking left a partial fixture'; end if;
  if (select count(*) from public.email_queue)<>emails or (select count(*) from public.notification_queue)<>notices
    then raise exception 'Simple booking generated communications'; end if;
  update public.club_memberships set role='guest' where club_id=club and member_profile_id=actor;
  rejected:=false;
  begin perform public.create_member_rink_booking(club,ft,green,started+interval '1 day',label);
  exception when others then if sqlerrm not like '%non-guest%' then raise; end if; rejected:=true; end;
  if not rejected then raise exception 'Guest booking allowed'; end if;
  if has_function_privilege('anon','public.create_member_rink_booking(uuid,uuid,uuid,timestamptz,text)','execute')
    then raise exception 'Anonymous execution allowed'; end if;
end $$;
