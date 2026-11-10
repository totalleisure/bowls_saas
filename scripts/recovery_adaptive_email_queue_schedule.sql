-- Operator recovery: stop adaptation and restore the original five-minute cadence.
-- Does not alter the worker command, credentials, active state or any email records.
begin;
select cron.unschedule(jobid) from cron.job where jobname='bowls-adapt-email-queue-schedule';
select cron.alter_job(job_id:=jobid,schedule:='*/5 * * * *') from cron.job where jobname='bowls-process-email-queue';
commit;
