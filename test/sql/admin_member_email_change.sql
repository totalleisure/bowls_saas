-- Caller owns the transaction. Every account, membership and audit row rolls back.
do $$
declare club uuid; second_club uuid; ids uuid[]:='{}'; profiles uuid[]:='{}'; u uuid; mp uuid;
 old_email text; new_email text; data jsonb; change uuid; rejected boolean; password_before text;
begin
 select id into strict club from public.clubs limit 1;
 select id into second_club from public.clubs where id<>club limit 1;
 for i in 1..3 loop
  u:=gen_random_uuid();
  insert into auth.users(id,email,email_confirmed_at,encrypted_password,raw_user_meta_data)
   values(u,'email-test-'||u||'@example.invalid',now(),'unchanged-synthetic-password-hash',jsonb_build_object('first_name','Synthetic','last_name','Email Test '||i));
  select id into mp from public.member_profiles where user_id=u;
  if mp is null then insert into public.member_profiles(user_id,display_name) values(u,'Synthetic Email Test') returning id into mp;end if;
  update public.member_profiles set email_address='email-test-'||u||'@example.invalid' where id=mp;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active)
   values(club,mp,case when i=1 then 'admin'::public.club_role else 'member'::public.club_role end,true);
  ids:=array_append(ids,u);profiles:=array_append(profiles,mp);
 end loop;
 old_email:='email-test-'||ids[2]||'@example.invalid';new_email:='email-new-'||ids[2]||'@example.invalid';
 rejected:=false;
 begin perform public.begin_admin_member_email_change(ids[3],club,profiles[2],old_email,new_email);
 exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Ordinary member authorized';end if;
 update public.club_memberships set role='selector' where club_id=club and member_profile_id=profiles[3];
 rejected:=false;
 begin perform public.begin_admin_member_email_change(ids[3],club,profiles[2],old_email,new_email);
 exception when insufficient_privilege then rejected:=true;end;
 if not rejected then raise exception 'Selector authorized';end if;
 rejected:=false;
 begin perform public.begin_admin_member_email_change(ids[1],club,profiles[2],'stale@example.invalid',new_email);
 exception when serialization_failure then rejected:=true;end;
 if not rejected then raise exception 'Stale address authorized';end if;
 rejected:=false;
 begin perform public.begin_admin_member_email_change(ids[1],club,profiles[2],old_email,'email-test-'||ids[3]||'@example.invalid');
 exception when unique_violation then rejected:=true;end;
 if not rejected then raise exception 'Duplicate address authorized';end if;
 if second_club is not null then
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(second_club,profiles[2],'admin',true);
  rejected:=false;
  begin perform public.begin_admin_member_email_change(ids[1],club,profiles[2],old_email,new_email);
  exception when insufficient_privilege then rejected:=true;end;
  if not rejected then raise exception 'Other club admin takeover allowed';end if;
  update public.club_memberships set is_active=false where club_id=second_club and member_profile_id=profiles[2];
 end if;
 data:=public.begin_admin_member_email_change(ids[1],club,profiles[2],old_email,new_email);change:=(data->>'change_id')::uuid;
 rejected:=false;
 begin perform public.begin_admin_member_email_change(ids[1],club,profiles[2],old_email,new_email);
 exception when object_not_in_prerequisite_state then rejected:=true;end;
 if not rejected then raise exception 'Concurrent change authorized';end if;
 -- Simulate Auth's committed email update solely to exercise the live sync
 -- trigger. The Edge handler separately tests the supported Admin API call.
 update auth.users set email=new_email where id=ids[2];
 execute 'set local role service_role';
 data:=public.finish_admin_member_email_change(change);
 if (data->>'changed')::boolean is not true then raise exception 'Verified update not successful';end if;
 perform public.finish_admin_member_email_change(change);
 execute 'reset role';
 if not exists(select 1 from public.member_profiles where id=profiles[2] and user_id=ids[2] and email_address=new_email)
 then raise exception 'Profile identity/email not preserved';end if;
 if not exists(select 1 from auth.users where id=ids[2] and email=new_email and encrypted_password='unchanged-synthetic-password-hash')
 then raise exception 'Login/password not preserved';end if;
 if (select count(*) from public.audit_journal where origin='admin_email_change' and record_id=profiles[2]::text and actor_user_id=ids[1] and outcome='completed')<>1
 then raise exception 'Admin audit missing or duplicated';end if;
 data:=public.begin_admin_member_email_change(ids[1],club,profiles[2],new_email,'not-applied-'||ids[2]||'@example.invalid');
 data:=public.finish_admin_member_email_change((data->>'change_id')::uuid);
 if (data->>'changed')::boolean then raise exception 'Unapplied change reported success';end if;
 if has_function_privilege('authenticated','public.begin_admin_member_email_change(uuid,uuid,uuid,text,text)','execute')
 or has_function_privilege('anon','public.finish_admin_member_email_change(uuid)','execute') then raise exception 'Public mutation RPC leaked';end if;
 execute 'set local role authenticated';
 begin perform public.begin_admin_member_email_change(ids[1],club,profiles[2],new_email,old_email);
  raise exception 'Browser called service RPC';exception when insufficient_privilege then null;end;
 execute 'reset role';
end $$;
