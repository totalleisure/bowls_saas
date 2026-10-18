begin;

do $test$
declare cid uuid; actor uuid; pid uuid:=gen_random_uuid(); uid uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); normal uuid:=gen_random_uuid();
begin
 select cm.club_id,mp.user_id into cid,actor from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.role='admin' and cm.is_active and mp.user_id is not null limit 1;
 if actor is null then raise exception 'No administrator test prerequisite'; end if;
 insert into public.member_profiles(id,first_name,last_name,display_name,phone,is_captain_managed) values(pid,'Rollback','Conversion','Rollback Conversion','07700000000',true);
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(cid,pid,'member',true);
 -- A user-controlled metadata claim must never link an existing profile.
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values(normal,normal::text||'@example.invalid','{}',jsonb_build_object('captain_managed_profile_id',pid));
 if not exists(select 1 from public.member_profiles where id=pid and user_id is null) then raise exception 'User metadata hijacked profile'; end if;
 if not exists(select 1 from public.member_profiles where user_id=normal and id<>pid) then raise exception 'Normal signup broken'; end if;
 begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values(outsider,outsider::text||'@example.invalid',jsonb_build_object('captain_managed_profile_id',pid,'enabled_by_admin',normal,'enabled_for_club',cid),'{}');
  raise exception 'Unauthorized conversion succeeded';
 exception when insufficient_privilege then null;
 end;
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values(uid,uid::text||'@example.invalid',jsonb_build_object('captain_managed_profile_id',pid,'enabled_by_admin',actor,'enabled_for_club',cid),'{}');
 if not exists(select 1 from public.member_profiles where id=pid and user_id=uid and not is_captain_managed and email_address=uid::text||'@example.invalid') then raise exception 'Conversion failed'; end if;
 if (select count(*) from public.member_profiles where user_id=uid)<>1 then raise exception 'Duplicate profile created'; end if;
 if not exists(select 1 from public.club_memberships where member_profile_id=pid and club_id=cid and is_active) then raise exception 'Membership lost'; end if;
 begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values(outsider,outsider::text||'@example.invalid',jsonb_build_object('captain_managed_profile_id',pid,'enabled_by_admin',actor,'enabled_for_club',cid),'{}');
  raise exception 'Already-linked conversion succeeded';
 exception when raise_exception then
  if sqlerrm='Already-linked conversion succeeded' then raise; end if;
 end;
end $test$;
select 'PASS: conversion, retained membership, ordinary signup, metadata spoof and unauthorized/already-linked rejection' as result;
rollback;
