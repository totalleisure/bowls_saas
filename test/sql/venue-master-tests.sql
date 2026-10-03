begin;
set local statement_timeout='25s';
create temp table venue_results(test text,passed boolean) on commit drop;
grant insert,select on venue_results to authenticated,anon,service_role;
do $test$
declare
 c uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); su uuid:=gen_random_uuid();
 pa uuid; pb uuid; master uuid; spare uuid; va uuid; vb uuid; home uuid; local_venue uuid;
 n integer; denied boolean; op text;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Disable cron'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data) values
 (a,a::text||'@example.invalid','{"display_name":"Venue A"}','{}'),
 (b,b::text||'@example.invalid','{"display_name":"Venue B"}','{}'),
 (su,su::text||'@example.invalid','{"display_name":"Venue superuser"}','{}');
 select id into pa from public.member_profiles where user_id=a;
 select id into pb from public.member_profiles where user_id=b;
 insert into public.clubs(id,name) values(c,'ROLLBACK venue A'),(d,'ROLLBACK venue B');
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(c,pa,'admin',true),(d,pb,'admin',true);
 insert into public.app_superusers(user_id) values(su);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',su,'role','authenticated')::text,true);
 set local role authenticated;
 insert into public.venue_master(name,town_city) values('Shared rollback venue','Shared town') returning id into master;
 insert into public.venue_master(name) values('Disposable rollback venue') returning id into spare;
 update public.venue_master set contact_name='Shared contact' where id=master;
 insert into venue_results select 'superuser create and edit',contact_name='Shared contact' from public.venue_master where id=master;
 delete from public.venue_master where id=spare;
 get diagnostics n=row_count;
 insert into venue_results values('superuser delete spare',n=1);
 home:=public.create_club_venue(c,'Home link',true,p_venue_master_id=>master);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 set local role authenticated;
 va:=public.create_club_venue(c,'Opponent A',false,p_venue_master_id=>master);
 local_venue:=public.create_club_venue_full(c,'Current UI venue',false);
 insert into venue_results select 'current UI creation RPC works',count(*)=1 from public.venues where id=local_venue;
 insert into venue_results select 'club A shared master readable',count(*)=1 from public.venue_master where id=master;
 insert into venue_results select 'club A view uses shared details',town_city='Shared town' and contact_name='Shared contact' from public.venues_with_details where id=va;
 denied:=false;
 begin perform public.create_club_venue(d,'Forged foreign link',false,p_venue_master_id=>master); exception when insufficient_privilege then denied:=true; end;
 insert into venue_results values('foreign club link denied',denied);
 denied:=false;
 begin insert into public.venue_master(name) values('Forged'); exception when insufficient_privilege then denied:=true; end;
 insert into venue_results values('club admin master creation denied',denied);
 update public.venue_master set name='Forged' where id=master;
 get diagnostics n=row_count;
 insert into venue_results values('club admin shared edit denied',n=0);
 delete from public.venue_master where id=master;
 get diagnostics n=row_count;
 insert into venue_results values('club admin shared deletion denied',n=0);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
 set local role authenticated;
 vb:=public.create_club_venue(d,'Opponent B',false,p_venue_master_id=>master);
 insert into venue_results select 'club B reuses same master',venue_master_id=master from public.venues where id=vb;
 insert into venue_results select 'club B reads shared master',count(*)=1 from public.venue_master where id=master;
 insert into venue_results select 'club B sees own shared details',town_city='Shared town' from public.venues_with_details where id=vb;
 insert into venue_results select 'club B cannot see club A links',count(*)=0 from public.venues_with_details where id in(va,home);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',su,'role','authenticated')::text,true);
 set local role authenticated;
 insert into venue_results select 'superuser view retains all links',count(*)=3 from public.venues_with_details where id in(va,vb,home);
 reset role;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 foreach op in array array[
 'select count(*) from public.venue_master',
 'insert into public.venue_master(name) values(''forged'')',
 'update public.venue_master set name=name where false',
 'delete from public.venue_master where false'
 ] loop
  denied:=false;
  begin execute op; exception when insufficient_privilege then denied:=true; end;
  insert into venue_results values('anonymous denied '||split_part(op,' ',1),denied);
 end loop;
 reset role;
 set local role service_role;
 insert into public.venue_master(name) values('Server venue') returning id into spare;
 update public.venue_master set name='Server updated' where id=spare;
 insert into venue_results select 'server CRUD',name='Server updated' from public.venue_master where id=spare;
 delete from public.venue_master where id=spare;
 reset role;
 insert into venue_results values('one master three links',(select count(*) from public.venues where venue_master_id=master)=3);
 insert into venue_results values('cron stays disabled',not exists(select 1 from cron.job where active));
 if exists(select 1 from venue_results where not passed) then raise exception 'Venue regression failed'; end if;
end $test$;
select * from venue_results order by test;
rollback;
