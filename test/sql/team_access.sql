begin;
set local statement_timeout='30s';
create temp table team_results(test text, passed boolean) on commit drop;
grant select,insert on team_results to authenticated,anon;
do $test$
declare
 c uuid:=gen_random_uuid(); other_c uuid:=gen_random_uuid();
 users uuid[]:=array[]::uuid[]; profiles uuid[]:=array[]::uuid[];
 u uuid; p uuid; t uuid; other_t uuid; n integer; i integer; denied boolean;
 roles text[]:=array['admin','selector','member','member','member','member','member'];
 labels text[]:=array['admin','selector','captain','vice','manager','member','inactive captain'];
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must stay disabled'; end if;
 insert into public.clubs(id,name) values(c,'ROLLBACK team A'),(other_c,'ROLLBACK team B');
 for i in 1..7 loop
  u:=gen_random_uuid(); users:=array_append(users,u);
  insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
   values(u,u::text||'@example.invalid','{"display_name":"Team RLS test"}','{}');
  select id into p from public.member_profiles where user_id=u;
  profiles:=array_append(profiles,p);
  insert into public.club_memberships(club_id,member_profile_id,role,is_active)
   values(c,p,roles[i]::public.club_role,i<>7);
 end loop;
 insert into public.teams(club_id,name,captain_member_profile_id,vice_captain_member_profile_id,manager_member_profile_id)
 values(c,'Team A',profiles[3],profiles[4],profiles[5]) returning id into t;
 insert into public.teams(club_id,name) values(other_c,'Team B') returning id into other_t;
 for i in 1..7 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[i],'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.teams where id=t;
  insert into team_results values(labels[i]||' read',n=case when i=7 then 0 else 1 end);
  update public.teams set description=labels[i] where id=t;
  get diagnostics n=row_count;
  insert into team_results values(labels[i]||' edit',n=case when i<=5 then 1 else 0 end);
  select count(*) into n from public.teams where id=other_t;
  insert into team_results values(labels[i]||' foreign read denied',n=0);
  update public.teams set description='foreign' where id=other_t;
  get diagnostics n=row_count;
  insert into team_results values(labels[i]||' foreign update denied',n=0);
  denied:=false;
  begin
   insert into public.teams(club_id,name) values(c,'Created by '||labels[i]);
  exception when insufficient_privilege then denied:=true; end;
  insert into team_results values(labels[i]||' creation rule',denied=(i>2));
  reset role;
 end loop;
 -- Existing team-pool RPC remains operational for all five editing roles.
 for i in 1..5 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[i],'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.add_team_members_to_pool(t,array[profiles[6]]);
  insert into team_results values(labels[i]||' pool RPC',n=1);
  reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'role','authenticated')::text,true);
 set local role authenticated;
 denied:=false;
 begin
  insert into public.teams(club_id,name) values(other_c,'Forbidden');
 exception when insufficient_privilege then denied:=true; end;
 insert into team_results values('foreign insert denied',denied);
 denied:=false;
 begin
  update public.teams set club_id=other_c where id=t;
 exception when insufficient_privilege or check_violation then denied:=true; end;
 insert into team_results values('club reassignment denied',denied);
 delete from public.teams where id=other_t;
 get diagnostics n=row_count;
 insert into team_results values('foreign delete denied',n=0);
 -- A profile with no membership in the team club cannot be appointed.
 reset role;
 u:=gen_random_uuid();
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
 values(u,u::text||'@example.invalid','{"display_name":"Team RLS test"}','{}');
 select id into p from public.member_profiles where user_id=u;
 insert into public.club_memberships(club_id,member_profile_id) values(other_c,p);
 set local role authenticated;
 denied:=false;
 begin
  update public.teams set captain_member_profile_id=p where id=t;
 exception when check_violation then denied:=true; end;
 insert into team_results values('foreign official denied',denied);
 -- An official can hand over their role, preserving the existing editing UI.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[3],'role','authenticated')::text,true);
 update public.teams set captain_member_profile_id=profiles[6] where id=t;
 get diagnostics n=row_count;
 insert into team_results values('captain handover',n=1);
 update public.teams set description='former captain' where id=t;
 get diagnostics n=row_count;
 insert into team_results values('former captain edit denied',n=0);
 reset role;
 update public.club_memberships set is_active=false where club_id=c and member_profile_id=profiles[6];
 perform set_config('request.jwt.claims',jsonb_build_object('sub',users[6],'role','authenticated')::text,true);
 set local role authenticated;
 update public.teams set description='inactive captain' where id=t;
 get diagnostics n=row_count;
 insert into team_results values('deactivated actual captain denied',n=0);
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 select count(*) into n from public.teams where id in(t,other_t);
 insert into team_results values('anonymous read denied',n=0);
 update public.teams set description='anonymous' where id=t;
 get diagnostics n=row_count;
 insert into team_results values('anonymous update denied',n=0);
 denied:=false;
 begin
  insert into public.teams(club_id,name) values(c,'Anonymous');
 exception when insufficient_privilege then denied:=true; end;
 insert into team_results values('anonymous insert denied',denied);
 reset role;
 insert into team_results values('cron disabled',not exists(select 1 from cron.job where active));
 insert into team_results values('no client truncate',not has_table_privilege('anon','public.teams','TRUNCATE') and not has_table_privilege('authenticated','public.teams','TRUNCATE'));
end $test$;
select * from team_results order by test;
rollback;
