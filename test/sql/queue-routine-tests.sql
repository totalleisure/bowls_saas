begin;
set local statement_timeout='25s';
create temp table routine_results(test text,passed boolean) on commit drop;
grant insert,select on routine_results to authenticated,anon,service_role;
-- Reproduce an elevated wrapper: its owner must not make an ordinary caller trusted.
create function public.test_queue_security_wrapper() returns integer language sql security definer
as 'select public.process_notification_queue(0)';
grant execute on function public.test_queue_security_wrapper() to authenticated;
do $test$
declare
 u uuid:=gen_random_uuid(); su uuid:=gen_random_uuid(); fixture uuid; unknown_fixture uuid:=gen_random_uuid();
 r text; op text; denied boolean; result jsonb; did_reset boolean; count_before bigint;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Disable cron before tests'; end if;
 select count(*) into count_before from public.email_queue;
 select fixture_id into fixture from public.team_selections limit 1;
 if fixture is null then raise exception 'Test requires a fixture with a team selection'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
 values(u,u::text||'@example.invalid','{"display_name":"Routine test"}','{}'),
 (su,su::text||'@example.invalid','{"display_name":"Routine superuser test"}','{}');
 insert into public.app_superusers(user_id) values(su);
 foreach r in array array['anon','authenticated'] loop
  perform set_config('request.jwt.claims',case when r='authenticated' then jsonb_build_object('sub',u,'role',r)::text else '{"role":"anon"}' end,true);
  execute format('set local role %I',r);
  foreach op in array array['select public.get_queue_admin_stats()','select public.process_notification_queue(0)',format('select * from public.reset_fixture_publication_test(%L)',fixture)] loop
   denied:=false;
   begin execute op; exception when insufficient_privilege then denied:=true; end;
   insert into routine_results values(r||' denied '||split_part(op,'(',1),denied);
  end loop;
  reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 set local role authenticated;
 denied:=false;
 begin perform public.test_queue_security_wrapper(); exception when insufficient_privilege then denied:=true; end;
 insert into routine_results values('definer wrapper does not bypass guard',denied);
 reset role;
 foreach r in array array['authenticated','service_role','postgres'] loop
  perform set_config('request.jwt.claims',case when r='authenticated' then jsonb_build_object('sub',su,'role',r)::text else '{}' end,true);
  execute format('set local role %I',r);
  result:=public.get_queue_admin_stats();
  insert into routine_results values(r||' stats allowed',result ? 'email_pending' and result ? 'notification_failed');
  insert into routine_results values(r||' zero-work processing allowed',public.process_notification_queue(0)=0);
  -- Reset is exercised within an immediately rolled-back subtransaction.
  did_reset:=false;
  begin
   perform * from public.reset_fixture_publication_test(fixture);
   did_reset:=true;
   raise exception 'Rollback reset test' using errcode='Z0001';
  exception when sqlstate 'Z0001' then null;
  end;
  insert into routine_results values(r||' reset allowed and rolled back',did_reset);
  reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',su,'role','authenticated')::text,true);
 delete from public.app_superusers where user_id=su;
 set local role authenticated;
 denied:=false;
 begin perform public.get_queue_admin_stats(); exception when insufficient_privilege then denied:=true; end;
 insert into routine_results values('removed superuser denied immediately',denied);
 reset role;
 insert into routine_results values('queue count unchanged',(select count(*) from public.email_queue)=count_before);
 insert into routine_results values('cron remains disabled',not exists(select 1 from cron.job where active));
 if exists(select 1 from routine_results where not passed) then raise exception 'Routine regression failed'; end if;
end $test$;
select * from routine_results order by test;
rollback;
