begin;

do $test$
declare cid uuid; actor uuid; pid uuid:=gen_random_uuid(); uid uuid:=gen_random_uuid(); placeholder uuid;
begin
 select cm.club_id,p.user_id into cid,actor from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id where cm.is_active and cm.role='admin' and p.user_id is not null limit 1;
 insert into public.member_profiles(id,first_name,last_name,display_name,phone,is_captain_managed) values(pid,'Delayed','Test','Delayed Test','07700000000',true);
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(cid,pid,'member',true);
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data) values(uid,uid::text||'@example.invalid','{}','{}');
 select id into placeholder from public.member_profiles where user_id=uid;
 if placeholder=pid or placeholder is null then raise exception 'Delay not reproduced'; end if;
 -- Even a mistakenly linked placeholder must not lose its history.
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(cid,placeholder,'member',true);
 begin
   update auth.users set raw_app_meta_data=jsonb_build_object('captain_managed_profile_id',pid,'enabled_by_admin',actor,'enabled_for_club',cid) where id=uid;
   raise exception 'Referenced placeholder was removed';
 exception when raise_exception then if sqlerrm not like '%has history%' then raise; end if; end;
 delete from public.club_memberships where member_profile_id=placeholder;
 update auth.users set raw_app_meta_data=jsonb_build_object('captain_managed_profile_id',pid,'enabled_by_admin',actor,'enabled_for_club',cid) where id=uid;
 if not exists(select 1 from public.member_profiles where id=pid and user_id=uid and not is_captain_managed) then raise exception 'Delayed link failed'; end if;
 if exists(select 1 from public.member_profiles where id=placeholder) then raise exception 'Empty duplicate remains'; end if;
 if (select count(*) from public.club_memberships where member_profile_id=pid and is_active)<>1 then raise exception 'Membership not retained'; end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 execute 'set local role authenticated';
 if public.my_member_profile_id() is distinct from pid then raise exception 'Signed-in profile lookup failed'; end if;
 if not exists(select 1 from public.club_memberships where member_profile_id=public.my_member_profile_id() and is_active) then raise exception 'Signed-in membership inaccessible'; end if;
 execute 'reset role';
end $test$;
select 'PASS: delayed metadata links existing member; reference protection and signed-in membership access verified' result;
rollback;
