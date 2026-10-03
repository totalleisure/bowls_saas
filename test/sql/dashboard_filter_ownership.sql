-- Transactional test; synthetic Auth/profile/filter rows always rolled back.
begin;
set local statement_timeout='20s';
create temporary table filter_results(test text, passed boolean) on commit drop;
grant insert,select on filter_results to authenticated,anon;
do $test$
declare
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid();
 ca uuid:=gen_random_uuid(); cb uuid:=gen_random_uuid();
 n integer; blocked boolean;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must stay disabled'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
 values(a,a::text||'@example.invalid','{"display_name":"Filter test A"}','{}'),
       (b,b::text||'@example.invalid','{"display_name":"Filter test B"}','{}');
 insert into public.clubs(id,name) values(ca,'ROLLBACK filter A'),(cb,'ROLLBACK filter B');
 insert into public.user_club_dashboard_filters(user_id,club_id,filter_json) values(b,ca,'{"other":true}');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 set local role authenticated;
 insert into public.user_club_dashboard_filters(user_id,club_id,filter_json) values(a,ca,'{"first":true}');
 insert into filter_results select 'own insert/read',count(*)=1 from public.user_club_dashboard_filters where user_id=a and club_id=ca;
 insert into public.user_club_dashboard_filters(user_id,club_id,filter_json) values(a,ca,'{"saved":true}')
 on conflict(user_id,club_id) do update set filter_json=excluded.filter_json;
 insert into filter_results select 'own upsert',filter_json='{"saved":true}'::jsonb from public.user_club_dashboard_filters where user_id=a and club_id=ca;
 insert into public.user_club_dashboard_filters(user_id,club_id) values(a,cb);
 insert into filter_results select 'separate per-club filters',count(*)=2 from public.user_club_dashboard_filters where user_id=a;
 insert into filter_results select 'foreign read hidden',count(*)=0 from public.user_club_dashboard_filters where user_id=b;
 update public.user_club_dashboard_filters set filter_json='{}' where user_id=b;
 get diagnostics n=row_count;
 insert into filter_results values('foreign update denied',n=0);
 delete from public.user_club_dashboard_filters where user_id=b;
 get diagnostics n=row_count;
 insert into filter_results values('foreign delete denied',n=0);
 blocked:=false;
 begin
  insert into public.user_club_dashboard_filters(user_id,club_id) values(b,cb);
 exception when insufficient_privilege then blocked:=true; end;
 insert into filter_results values('foreign insert denied',blocked);
 blocked:=false;
 begin
  insert into public.user_club_dashboard_filters(user_id,club_id) values(b,ca)
  on conflict(user_id,club_id) do update set filter_json='{"forged":true}';
 exception when insufficient_privilege then blocked:=true; end;
 insert into filter_results values('foreign upsert denied',blocked);
 blocked:=false;
 begin
  update public.user_club_dashboard_filters set user_id=b where user_id=a and club_id=cb;
 exception when insufficient_privilege then blocked:=true; end;
 insert into filter_results values('ownership reassignment denied',blocked);
 delete from public.user_club_dashboard_filters where user_id=a and club_id=cb;
 get diagnostics n=row_count;
 insert into filter_results values('own delete',n=1);
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 insert into filter_results select 'anonymous read hidden',count(*)=0 from public.user_club_dashboard_filters;
 blocked:=false;
 begin
  insert into public.user_club_dashboard_filters(user_id,club_id) values(a,cb);
 exception when insufficient_privilege then blocked:=true; end;
 insert into filter_results values('anonymous insert denied',blocked);
 update public.user_club_dashboard_filters set filter_json='{}' where user_id=a;
 get diagnostics n=row_count;
 insert into filter_results values('anonymous update denied',n=0);
 delete from public.user_club_dashboard_filters where user_id=a;
 get diagnostics n=row_count;
 insert into filter_results values('anonymous delete denied',n=0);
 reset role;
 insert into filter_results select 'other owner record unchanged',filter_json='{"other":true}'::jsonb from public.user_club_dashboard_filters where user_id=b and club_id=ca;
 insert into filter_results values('cron disabled',not exists(select 1 from cron.job where active));
end $test$;
select * from filter_results order by test;
rollback;
