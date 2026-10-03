begin;
set local statement_timeout='20s';
create temp table queue_results(test text,passed boolean) on commit drop;
grant insert,select on queue_results to authenticated,anon,service_role;
do $test$
declare
 u uuid:=gen_random_uuid(); su uuid:=gen_random_uuid(); p uuid;
 q uuid:=gen_random_uuid(); n integer; denied boolean; actor uuid; label text; op text;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Disable cron before tests'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
 values(u,u::text||'@example.invalid','{"display_name":"Queue test"}','{}'),
 (su,su::text||'@example.invalid','{"display_name":"Queue superuser test"}','{}');
 select id into p from public.member_profiles where user_id=u;
 insert into public.app_superusers(user_id) values(su);
 set local role service_role;
 insert into public.email_queue(id,member_profile_id,event_type,recipient_email,subject,body,status)
 values(q,p,'rls_test','synthetic@example.invalid','Test','Test','failed');
 insert into queue_results select 'server insert/read',count(*)=1 from public.email_queue where id=q;
 update public.email_queue set attempts=attempts+1 where id=q;
 get diagnostics n=row_count;
 insert into queue_results values('server update',n=1);
 reset role;
 foreach actor in array array[u,su] loop
  label:=case when actor=u then 'ordinary user' else 'superuser' end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  insert into queue_results select label||' visibility',count(*)=case when actor=u then 0 else 1 end from public.email_queue where id=q;
  foreach op in array array[
   format('update public.email_queue set attempts=99 where id=%L',q),
   format('delete from public.email_queue where id=%L',q),
   format('insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body) values(%L,''rls_test'',''forged@example.invalid'',''x'',''x'')',p)
  ] loop
   denied:=false;
   begin execute op; exception when insufficient_privilege then denied:=true; end;
   insert into queue_results values(label||' denied '||split_part(op,' ',1),denied);
  end loop;
  reset role;
 end loop;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 foreach op in array array[
  format('select id from public.email_queue where id=%L',q),
  format('update public.email_queue set attempts=99 where id=%L',q),
  format('delete from public.email_queue where id=%L',q),
  format('insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body) values(%L,''rls_test'',''forged@example.invalid'',''x'',''x'')',p)
 ] loop
  denied:=false;
  begin execute op; exception when insufficient_privilege then denied:=true; end;
  insert into queue_results values('anon denied '||split_part(op,' ',1),denied);
 end loop;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',su,'role','authenticated')::text,true);
 delete from public.app_superusers where user_id=su;
 set local role authenticated;
 insert into queue_results select 'revoked superuser immediately hidden',count(*)=0 from public.email_queue where id=q;
 reset role;
 set local role service_role;
 insert into queue_results select 'denied writes preserved row',attempts=1 and status='failed' from public.email_queue where id=q;
 delete from public.email_queue where id=q;
 get diagnostics n=row_count;
 insert into queue_results values('server delete',n=1);
 reset role;
 insert into queue_results values('client truncate revoked',not has_table_privilege('anon','public.email_queue','TRUNCATE') and not has_table_privilege('authenticated','public.email_queue','TRUNCATE'));
 insert into queue_results values('cron remains disabled',not exists(select 1 from cron.job where active));
 if exists(select 1 from queue_results where not passed) then raise exception 'Queue regression failed'; end if;
end $test$;
select * from queue_results order by test;
rollback;
