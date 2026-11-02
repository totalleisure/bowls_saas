begin;
do $$
declare worker text;env text;host text;
begin
 select environment into strict env from public.competition_release_controls where id;
 host:=case env when 'production' then 'xfjelvvfoguzukgvxchh' when 'staging' then 'egxdkaotepgfjmszxlyn' else null end;
 select command into strict worker from cron.job where jobname='bowls-process-email-queue';
 if host is null or position('https://'||host||'.supabase.co/functions/v1/process-email-queue' in worker)=0 then raise exception 'Worker environment does not match this project';end if;
 worker:=replace(worker,'/functions/v1/process-email-queue','/functions/v1/competition-round-ready');
 perform cron.schedule('bowls-competition-round-ready','* * * * *',worker);
end $$;
commit;
