-- Change only the existing worker's timing, preserving its URL, credentials and active flag.
create function mailing_private.email_queue_schedule_for_backlog(p_pending bigint,p_current text)
returns text language sql immutable set search_path='' as $$
 select case when p_current not in ('*/2 * * * *','*/5 * * * *') then p_current
 when p_pending >= 40 then '*/2 * * * *'
 when p_pending <= 20 then '*/5 * * * *'
 else p_current end;
$$;
revoke all on function mailing_private.email_queue_schedule_for_backlog(bigint,text) from public,anon,authenticated;

create function mailing_private.adjust_email_queue_schedule()
returns jsonb language plpgsql set search_path='' as $$
declare j record; pending_count bigint; target_schedule text;
begin
 if not pg_try_advisory_xact_lock(812690174) then return jsonb_build_object('status','busy'); end if;
 select jobid,schedule,active into j from cron.job where jobname='bowls-process-email-queue';
 if not found then return jsonb_build_object('status','worker_missing'); end if;
 if not j.active then return jsonb_build_object('status','worker_paused'); end if;
 select count(*) into pending_count from public.email_queue where status='pending';
 target_schedule:=mailing_private.email_queue_schedule_for_backlog(pending_count,j.schedule);
 if target_schedule is distinct from j.schedule then
   perform cron.alter_job(job_id:=j.jobid,schedule:=target_schedule);
 end if;
 return jsonb_build_object('pending',pending_count,'previous_schedule',j.schedule,'schedule',target_schedule,'changed',target_schedule is distinct from j.schedule);
end;
$$;
revoke all on function mailing_private.adjust_email_queue_schedule() from public,anon,authenticated;
select cron.schedule('bowls-adapt-email-queue-schedule','* * * * *','select mailing_private.adjust_email_queue_schedule();');
select mailing_private.adjust_email_queue_schedule();
