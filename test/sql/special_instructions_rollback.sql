begin;
do $test$
declare f public.fixtures%rowtype; cm public.club_memberships%rowtype; uid uuid; old_notes text; sel uuid;
begin
 select f0.* into strict f from public.fixtures f0
 where exists(select 1 from public.club_memberships m join public.member_profiles p on p.id=m.member_profile_id
 where m.club_id=f0.club_id and p.user_id is not null and not exists(select 1 from public.app_superusers su where su.user_id=p.user_id)) limit 1;
 select m.* into strict cm from public.club_memberships m join public.member_profiles p on p.id=m.member_profile_id
 where m.club_id=f.club_id and p.user_id is not null and not exists(select 1 from public.app_superusers su where su.user_id=p.user_id) limit 1;
 select user_id into uid from public.member_profiles where id=cm.member_profile_id;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 perform set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
 update public.club_memberships set role='member',is_active=true where id=cm.id;
 update public.fixtures set captain_member_profile_id=cm.member_profile_id,vice_captain_member_profile_id=null where id=f.id;
 perform public.set_fixture_instructions(f.id,'Captain instructions',f.notes);
 perform public.set_fixture_instructions(f.id,'Captain changed','Captain instructions');
 begin
   perform public.set_fixture_instructions(f.id,'Overwrite','stale');
   raise exception 'FAIL stale accepted';
 exception when serialization_failure then null; end;
 update public.fixtures set captain_member_profile_id=null,vice_captain_member_profile_id=cm.member_profile_id where id=f.id;
 perform public.set_fixture_instructions(f.id,'Vice instructions','Captain changed');
 update public.fixtures set vice_captain_member_profile_id=null where id=f.id;
 begin
   perform public.set_fixture_instructions(f.id,'Denied','Vice instructions');
   raise exception 'FAIL ordinary member accepted';
 exception when insufficient_privilege then null; end;
 update public.club_memberships set role='admin' where id=cm.id;
 perform public.set_fixture_instructions(f.id,'Admin instructions','Vice instructions');
 begin
   perform public.publish_team_with_instructions(f.id,'00000000-0000-0000-0000-000000000000',true,'Must roll back','Admin instructions');
   raise exception 'FAIL invalid selection accepted';
 exception when others then
   if sqlerrm like 'FAIL%' then raise; end if;
 end;
 if (select notes from public.fixtures where id=f.id) <> 'Admin instructions' then raise exception 'FAIL publish did not roll back'; end if;
 update public.club_memberships set is_active=false where id=cm.id;
 begin
   perform public.set_fixture_instructions(f.id,'Denied','Admin instructions');
   raise exception 'FAIL inactive accepted';
 exception when insufficient_privilege then null; end;
end;
$test$;
rollback;
