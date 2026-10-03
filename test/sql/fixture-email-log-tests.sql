begin;
set local statement_timeout='20s';
create temp table email_log_results(test text,passed boolean) on commit drop;
grant insert,select on email_log_results to authenticated,anon,service_role;
do $test$
declare
 log_id uuid:=gen_random_uuid(); fixture uuid:=gen_random_uuid();
 caller uuid:=gen_random_uuid(); denied boolean; r text; op text; n integer;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must remain disabled'; end if;
 set local role service_role;
 insert into public.fixture_email_log(id,fixture_id,email_address,email_type,send_status,provider_response)
 values(log_id,fixture,'synthetic@example.invalid','player','submitted','{"test":true}');
 insert into email_log_results select 'server insert/read',count(*)=1 from public.fixture_email_log where id=log_id;
 update public.fixture_email_log set send_status='test-updated' where id=log_id;
 get diagnostics n=row_count;
 insert into email_log_results values('server update',n=1);
 reset role;
 foreach r in array array['authenticated','anon'] loop
  perform set_config('request.jwt.claims',case when r='authenticated' then jsonb_build_object('sub',caller,'role',r)::text else '{"role":"anon"}' end,true);
  execute format('set local role %I',r);
  foreach op in array array['select count(*) from public.fixture_email_log','update public.fixture_email_log set send_status=send_status','delete from public.fixture_email_log'] loop
   denied:=false;
   begin execute op; exception when insufficient_privilege then denied:=true; end;
   insert into email_log_results values(r||' denied '||split_part(op,' ',1),denied);
  end loop;
  denied:=false;
  begin insert into public.fixture_email_log(email_address) values('forged@example.invalid'); exception when insufficient_privilege then denied:=true; end;
  insert into email_log_results values(r||' denied insert',denied);
  reset role;
 end loop;
 set local role service_role;
 insert into email_log_results select 'evidence unchanged by denied writes',send_status='test-updated' and provider_response='{"test":true}'::jsonb from public.fixture_email_log where id=log_id;
 delete from public.fixture_email_log where id=log_id;
 get diagnostics n=row_count;
 insert into email_log_results values('server cleanup',n=1);
 reset role;
 insert into email_log_results values('no client truncate',not has_table_privilege('authenticated','public.fixture_email_log','TRUNCATE') and not has_table_privilege('anon','public.fixture_email_log','TRUNCATE'));
 insert into email_log_results values('cron disabled',not exists(select 1 from cron.job where active));
end $test$;
select * from email_log_results order by test;
rollback;
