-- Restore the two staging queue jobs that were absent after the staging build.
-- The existing email-response inbox job is preserved.
do $$
begin
  if not exists (
    select 1 from cron.job where jobname = 'bowls-process-notification-queue'
  ) then
    perform cron.schedule(
      'bowls-process-notification-queue',
      '*/5 * * * *',
      $job$select public.process_notification_queue(50);$job$
    );
  end if;

  if not exists (
    select 1 from cron.job where jobname = 'bowls-process-email-queue'
  ) then
    perform cron.schedule(
      'bowls-process-email-queue',
      '*/5 * * * *',
      $job$
      select net.http_post(
        url := 'https://egxdkaotepgfjmszxlyn.supabase.co/functions/v1/process-email-queue',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'Authorization','Bearer ' || (
            select decrypted_secret from vault.decrypted_secrets
            where name='staging_email_responses_service_role'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 60000
      ) as request_id;
      $job$
    );
  end if;
end $$;

create or replace function public.get_notification_queue_cron_status()
returns jsonb language plpgsql security definer
set search_path = 'public','cron' as $$
declare v_job cron.job;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select * into v_job from cron.job
    where jobname='bowls-process-notification-queue' limit 1;
  if not found then return jsonb_build_object('found',false,'active',false); end if;
  return jsonb_build_object('found',true,'job_id',v_job.jobid,
    'job_name',v_job.jobname,'schedule',v_job.schedule,'active',v_job.active);
end $$;

create or replace function public.get_email_queue_cron_status()
returns jsonb language plpgsql security definer
set search_path = 'public','cron' as $$
declare v_job cron.job;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select * into v_job from cron.job
    where jobname='bowls-process-email-queue' limit 1;
  if not found then return jsonb_build_object('found',false,'active',false); end if;
  return jsonb_build_object('found',true,'job_id',v_job.jobid,
    'job_name',v_job.jobname,'schedule',v_job.schedule,'active',v_job.active);
end $$;

create or replace function public.get_email_responses_cron_status()
returns jsonb language plpgsql security definer
set search_path = 'public','cron' as $$
declare v_job cron.job; v_state public.email_inbox_sync_state;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select * into v_job from cron.job where jobname='process-email-responses' limit 1;
  select * into v_state from public.email_inbox_sync_state order by updated_at desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    'found',v_job.jobid is not null,'active',coalesce(v_job.active,false),
    'job_id',v_job.jobid,'job_name',v_job.jobname,'schedule',v_job.schedule,
    'mailbox',v_state.mailbox,'last_checked_at',v_state.last_checked_at,
    'last_success_at',v_state.last_success_at,'last_error',v_state.last_error
  ));
end $$;

create or replace function public.set_notification_queue_cron_enabled(p_enabled boolean)
returns jsonb language plpgsql security definer
set search_path = 'public','cron' as $$
declare v_job_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select jobid into v_job_id from cron.job
    where jobname='bowls-process-notification-queue' limit 1;
  if v_job_id is null then raise exception 'Notification cron job is missing'; end if;
  perform cron.alter_job(v_job_id,active:=p_enabled);
  return jsonb_build_object('ok',true,'job_id',v_job_id,'active',p_enabled);
end $$;

create or replace function public.set_email_queue_cron_enabled(p_enabled boolean)
returns jsonb language plpgsql security definer
set search_path = 'public','cron' as $$
declare v_job_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select jobid into v_job_id from cron.job
    where jobname='bowls-process-email-queue' limit 1;
  if v_job_id is null then raise exception 'Email cron job is missing'; end if;
  perform cron.alter_job(v_job_id,active:=p_enabled);
  return jsonb_build_object('ok',true,'job_id',v_job_id,'active',p_enabled);
end $$;

create or replace function public.set_email_responses_cron_enabled(p_enabled boolean)
returns jsonb language plpgsql security definer
set search_path = 'public','cron' as $$
declare v_job_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select jobid into v_job_id from cron.job
    where jobname='process-email-responses' limit 1;
  if v_job_id is null then raise exception 'Email receipt cron job is missing'; end if;
  perform cron.alter_job(v_job_id,active:=p_enabled);
  return jsonb_build_object('ok',true,'job_id',v_job_id,'active',p_enabled);
end $$;

create or replace function public.run_email_responses_now()
returns jsonb language plpgsql security definer
set search_path = '' as $$
declare v_secret text; v_request_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets
    where name='staging_email_responses_service_role';
  if nullif(v_secret,'') is null then raise exception 'Staging service secret is missing'; end if;
  select net.http_post(
    url:='https://egxdkaotepgfjmszxlyn.supabase.co/functions/v1/process-email-responses',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_secret),
    body:='{}'::jsonb,timeout_milliseconds:=60000
  ) into v_request_id;
  return jsonb_build_object('ok',true,'request_id',v_request_id);
end $$;

revoke all on function public.get_notification_queue_cron_status() from public,anon;
revoke all on function public.get_email_queue_cron_status() from public,anon;
revoke all on function public.get_email_responses_cron_status() from public,anon;
revoke all on function public.set_notification_queue_cron_enabled(boolean) from public,anon;
revoke all on function public.set_email_queue_cron_enabled(boolean) from public,anon;
revoke all on function public.set_email_responses_cron_enabled(boolean) from public,anon;
revoke all on function public.run_email_responses_now() from public,anon;
grant execute on function public.get_notification_queue_cron_status() to authenticated;
grant execute on function public.get_email_queue_cron_status() to authenticated;
grant execute on function public.get_email_responses_cron_status() to authenticated;
grant execute on function public.set_notification_queue_cron_enabled(boolean) to authenticated;
grant execute on function public.set_email_queue_cron_enabled(boolean) to authenticated;
grant execute on function public.set_email_responses_cron_enabled(boolean) to authenticated;
grant execute on function public.run_email_responses_now() to authenticated;
