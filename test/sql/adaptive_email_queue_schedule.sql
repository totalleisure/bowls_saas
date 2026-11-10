-- All synthetic messages and schedule changes roll back; no HTTP worker is invoked.
begin;
do $$
declare j record; n int; r jsonb; cmd_hash text; test_member uuid;
begin
 if mailing_private.email_queue_schedule_for_backlog(40,'*/5 * * * *')<>'*/2 * * * *'
 or mailing_private.email_queue_schedule_for_backlog(21,'*/2 * * * *')<>'*/2 * * * *'
 or mailing_private.email_queue_schedule_for_backlog(39,'*/5 * * * *')<>'*/5 * * * *'
 or mailing_private.email_queue_schedule_for_backlog(20,'*/2 * * * *')<>'*/5 * * * *'
 or mailing_private.email_queue_schedule_for_backlog(0,'*/5 * * * *')<>'*/5 * * * *'
 or mailing_private.email_queue_schedule_for_backlog(100,'*/10 * * * *')<>'*/10 * * * *'
 then raise exception 'Backlog threshold policy failed'; end if;
 if has_function_privilege('authenticated','mailing_private.adjust_email_queue_schedule()','execute')
 or has_function_privilege('anon','mailing_private.adjust_email_queue_schedule()','execute') then raise exception 'Client can alter cron'; end if;
 select * into strict j from cron.job where jobname='bowls-process-email-queue';
 cmd_hash:=md5(j.command);
 select id into strict test_member from public.member_profiles order by id limit 1;
 -- Hide existing pending rows within this rolled-back transaction only.
 update public.email_queue set status='sent' where status='pending';
 perform cron.alter_job(job_id:=j.jobid,schedule:='*/5 * * * *',active:=true);
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body)
 select test_member,'adaptive_schedule_rollback_test','not-sent@example.invalid','Rollback test','Never committed' from generate_series(1,40);
 r:=mailing_private.adjust_email_queue_schedule();
 if r->>'schedule'<>'*/2 * * * *' or (r->>'pending')::int<>40 then raise exception 'Backlog did not accelerate: %',r; end if;
 r:=mailing_private.adjust_email_queue_schedule();
 if (r->>'changed')::boolean then raise exception 'Repeated check not idempotent'; end if;
 delete from public.email_queue where event_type='adaptive_schedule_rollback_test' and id in(select id from public.email_queue where event_type='adaptive_schedule_rollback_test' limit 20);
 r:=mailing_private.adjust_email_queue_schedule();
 if r->>'schedule'<>'*/5 * * * *' then raise exception 'Reduced queue did not slow: %',r; end if;
 perform cron.alter_job(job_id:=j.jobid,active:=false);
 r:=mailing_private.adjust_email_queue_schedule();
 if r->>'status'<>'worker_paused' then raise exception 'Paused worker was not respected'; end if;
 if (select md5(command) from cron.job where jobid=j.jobid)<>cmd_hash then raise exception 'Worker command changed'; end if;
end $$;
rollback;
select 'PASS: thresholds, hysteresis, real cron changes, idempotence, paused worker, permissions and unchanged command; test data rolled back' as result;
