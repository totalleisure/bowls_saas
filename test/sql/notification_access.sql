begin;
set local statement_timeout='20s';
create temp table notification_results(test text,passed boolean) on commit drop;
grant select,insert on notification_results to authenticated,anon,service_role;
do $test$
declare
 ua uuid:=gen_random_uuid(); ub uuid:=gen_random_uuid(); unlinked uuid:=gen_random_uuid();
 pa uuid; pb uuid; na uuid; nb uuid; ns uuid; n integer; denied boolean; col text;
begin
 if exists(select 1 from cron.job where active) then raise exception 'Cron must remain disabled'; end if;
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data)
 values(ua,ua::text||'@example.invalid','{"display_name":"Notification RLS test"}','{}'),
 (ub,ub::text||'@example.invalid','{"display_name":"Notification RLS test"}','{}');
 select id into pa from public.member_profiles where user_id=ua;
 select id into pb from public.member_profiles where user_id=ub;
 -- Exercise privileged creation without invoking any queue processor or email sender.
 set local role service_role;
 insert into public.app_notifications(member_profile_id,type,title,body)
 values(pa,'test','A','Body A') returning id into na;
 insert into public.app_notifications(member_profile_id,type,title,body)
 values(pb,'test','B','Body B') returning id into nb;
 insert into notification_results select 'service can create/read recipients',count(*)=2 from public.app_notifications where id in(na,nb);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ua,'role','authenticated')::text,true);
 set local role authenticated;
 insert into notification_results select 'own notification readable',count(*)=1 from public.app_notifications where id=na;
 insert into notification_results select 'other notification hidden',count(*)=0 from public.app_notifications where id=nb;
 insert into notification_results select 'unfiltered query still private',count(*)=1 from public.app_notifications where id in(na,nb);
 insert into notification_results select 'dashboard unread count',count(*)=1 from public.app_notifications where member_profile_id=pa and not is_read;
 update public.app_notifications set is_read=true,read_at=now() where id=na;
 get diagnostics n=row_count;
 insert into notification_results values('mark own read',n=1);
 insert into notification_results select 'read state persisted',is_read and read_at is not null from public.app_notifications where id=na;
 update public.app_notifications set is_read=true,read_at=now() where id=nb;
 get diagnostics n=row_count;
 insert into notification_results values('other read-state update denied',n=0);
 foreach col in array array['id','member_profile_id','type','title','body','data','created_at','fixture_id','team_selection_id'] loop
  denied:=false;
  begin
   execute format('update public.app_notifications set %I=%I where id=$1',col,col) using na;
  exception when insufficient_privilege then denied:=true; end;
  insert into notification_results values('client cannot edit '||col,denied);
 end loop;
 denied:=false;
 begin
  insert into public.app_notifications(member_profile_id,type,title,body) values(pa,'test','Forged','Forged');
 exception when insufficient_privilege then denied:=true; end;
 insert into notification_results values('client cannot create notification',denied);
 denied:=false;
 begin
  delete from public.app_notifications where id=na;
 exception when insufficient_privilege then denied:=true; end;
 insert into notification_results values('client cannot delete notification',denied);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ub,'role','authenticated')::text,true);
 insert into notification_results select 'second recipient own unread unchanged',not is_read from public.app_notifications where id=nb;
 insert into notification_results select 'second recipient cannot read first',count(*)=0 from public.app_notifications where id=na;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',unlinked,'role','authenticated')::text,true);
 insert into notification_results select 'unlinked identity sees nothing',count(*)=0 from public.app_notifications;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 denied:=false;
 begin
  select count(*) into n from public.app_notifications;
 exception when insufficient_privilege then denied:=true; end;
 insert into notification_results values('anonymous read denied',denied);
 denied:=false;
 begin
  update public.app_notifications set is_read=true where id=na;
 exception when insufficient_privilege then denied:=true; end;
 insert into notification_results values('anonymous update denied',denied);
 reset role;
 set local role service_role;
 update public.app_notifications set body='Server correction' where id=na;
 get diagnostics n=row_count;
 insert into notification_results values('service retains content update',n=1);
 delete from public.app_notifications where id=na;
 get diagnostics n=row_count;
 insert into notification_results values('service retains deletion',n=1);
 reset role;
 insert into notification_results values('no client truncate',not has_table_privilege('authenticated','public.app_notifications','TRUNCATE') and not has_table_privilege('anon','public.app_notifications','TRUNCATE'));
 insert into notification_results values('cron remains disabled',not exists(select 1 from cron.job where active));
end $test$;
select * from notification_results order by test;
rollback;
