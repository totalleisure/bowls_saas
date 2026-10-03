begin;
set local statement_timeout='20s';
create temp table invite_results(test text,passed boolean,detail text) on commit drop;
grant insert,select on invite_results to authenticated,anon,service_role;
do $test$
declare
 u uuid:=gen_random_uuid(); other_u uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 v_token uuid:=gen_random_uuid(); canceled uuid:=gen_random_uuid(); n integer;
 p uuid; denied boolean; success boolean; err text;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must stay disabled'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
 values(u,u::text||'@example.invalid','{"display_name":"Invite RLS test"}','{}'),
 (other_u,other_u::text||'@example.invalid','{"display_name":"Invite RLS test"}','{}');
 select id into p from public.member_profiles where user_id=u;
 insert into public.clubs(id,name) values(c,'ROLLBACK invite test');
 set local role service_role;
 insert into public.club_invites(club_id,email,role,token) values(c,upper(u::text||'@example.invalid'),'member',v_token);
 insert into public.club_invites(club_id,email,role,token,status) values(c,u::text||'@example.invalid','member',canceled,'cancelled');
 insert into invite_results select 'server creation',count(*)=2,null from public.club_invites where club_id=c;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_u,'role','authenticated')::text,true);
 set local role authenticated;
 denied:=false;
 begin
  select count(*) into n from public.club_invites;
 exception when insufficient_privilege then denied:=true; end;
 insert into invite_results values('client cannot list tokens',denied,null);
 err:=null;
 begin perform public.accept_invite(v_token); exception when others then err:=sqlerrm; end;
 insert into invite_results values('wrong email rejected',err='Invite email does not match logged-in user',err);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 err:=null;
 begin perform public.accept_invite(gen_random_uuid()); exception when others then err:=sqlerrm; end;
 insert into invite_results values('invalid token rejected',err='Invalid invite token',err);
 err:=null;
 begin perform public.accept_invite(canceled); exception when others then err:=sqlerrm; end;
 insert into invite_results values('cancelled token rejected',err='Invite already used or not pending',err);
 denied:=false;
 begin insert into public.club_invites(club_id,email,role) values(c,u::text||'@example.invalid','admin'); exception when insufficient_privilege then denied:=true; end;
 insert into invite_results values('client cannot forge invitation',denied,null);
 denied:=false;
 begin update public.club_invites set role='admin' where club_id=c; exception when insufficient_privilege then denied:=true; end;
 insert into invite_results values('client cannot elevate invitation role',denied,null);
 denied:=false;
 begin delete from public.club_invites where club_id=c; exception when insufficient_privilege then denied:=true; end;
 insert into invite_results values('client cannot delete invitation',denied,null);
 err:=null; success:=false;
 begin success:=public.accept_invite(v_token); exception when others then err:=sqlerrm; end;
 insert into invite_results values('intended recipient redemption',success,err);
 err:=null;
 begin perform public.accept_invite(v_token); exception when others then err:=sqlerrm; end;
 insert into invite_results values('replay rejected',err='Invite already used or not pending',err);
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 denied:=false;
 begin perform public.accept_invite(v_token); exception when insufficient_privilege then denied:=true; end;
 insert into invite_results values('anonymous redemption denied',denied,null);
 denied:=false;
 begin select count(*) into n from public.club_invites; exception when insufficient_privilege then denied:=true; end;
 insert into invite_results values('anonymous token read denied',denied,null);
 reset role;
 insert into invite_results select 'membership created with intended role',count(*)=1,null from public.club_memberships where club_id=c and member_profile_id=p and role='member';
 insert into invite_results select 'redemption recorded',count(*)=1,null from public.club_invites where club_id=c and club_invites.token=v_token and used_by=u and used_at is not null and status='used';
 insert into invite_results values('no client truncate',not has_table_privilege('anon','public.club_invites','TRUNCATE') and not has_table_privilege('authenticated','public.club_invites','TRUNCATE'),null);
 insert into invite_results values('cron disabled',not exists(select 1 from cron.job where active),null);
end $test$;
select * from invite_results order by test;
rollback;
