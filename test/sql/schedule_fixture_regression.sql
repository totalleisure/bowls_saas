-- STAGING ONLY: egxdkaotepgfjmszxlyn. Run as postgres through the Supabase tool.
-- All synthetic data and attempted edits are rolled back. No mail/queue RPCs.
-- Database role simulation tests RLS/RPC checks, not HTTP/JWT validation.
begin;
set local statement_timeout = '30s';
set local lock_timeout = '3s';
create temporary table smoke_results(case_id text, passed boolean, observed text) on commit drop;
grant select, insert on smoke_results to authenticated, anon;
do $test$
declare
  ca uuid := gen_random_uuid(); cb uuid := gen_random_uuid();
  ua uuid := gen_random_uuid(); ub uuid := gen_random_uuid();
  pa uuid; pb uuid; va uuid := gen_random_uuid(); vb uuid := gen_random_uuid();
  cta uuid := gen_random_uuid(); ctb uuid := gen_random_uuid();
  ta uuid := gen_random_uuid(); tb uuid := gen_random_uuid();
  f uuid; n integer; err text; sqlstate_seen text; before_n integer; i integer;
  base_email bigint; base_notifications bigint;
begin
  if exists(select 1 from cron.job where active) then
    raise exception 'Refusing to test while cron jobs are active';
  end if;
  select count(*) into base_email from public.email_queue;
  select count(*) into base_notifications from public.notification_queue;
  -- Auth inserts invoke only the inspected profile-creation trigger. No sign-up API.
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data)
  values (ua,ua::text||'@example.invalid','{}','{"display_name":"Smoke Admin A"}'),
         (ub,ub::text||'@example.invalid','{}','{"display_name":"Smoke Admin B"}');
  select id into strict pa from public.member_profiles where user_id=ua;
  select id into strict pb from public.member_profiles where user_id=ub;
  insert into public.clubs(id,name) values(ca,'ROLLBACK smoke club A'),(cb,'ROLLBACK smoke club B');
  insert into public.club_memberships(club_id,member_profile_id,role,is_active)
  values(ca,pa,'admin',true),(cb,pb,'admin',true);
  insert into public.venues(id,club_id,name,is_home_venue)
  values(va,ca,'Smoke away A',false),(vb,cb,'Smoke away B',false);
  insert into public.competition_types(id,club_id,name,section,uses_rinks,bookable_by_members)
  values(cta,ca,'Smoke pairs','mixed',true,false),(ctb,cb,'Smoke pairs','mixed',true,false);
  insert into public.teams(id,club_id,name) values(ta,ca,'Smoke team A'),(tb,cb,'Smoke team B');
  insert into public.user_club_dashboard_filters(user_id,club_id,filter_json)
  values(ua,ca,'{"smoke":true}'),(ub,cb,'{"smoke":true}');
  -- Use the same API role and identity claims consumed by auth.uid(), not postgres RLS bypass.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ua,'role','authenticated')::text,true);
  set local role authenticated;
  for i in 1..10 loop
    f:=public.create_fixture_with_setup_v2(ca,'2030-01-01 12:00Z'::timestamptz + i*interval '1 day',
      '2030-01-01 14:00Z'::timestamptz + i*interval '1 day',false,'mixed',2,2,'pairs',cta,'open',p_venue_id=>va);
  end loop;
  select count(*) into n from public.fixtures where club_id=ca;
  insert into smoke_results values('CREATE_A_10',n=10,n::text);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ub,'role','authenticated')::text,true);
  for i in 1..10 loop
    f:=public.create_fixture_with_setup_v2(cb,'2030-01-01 12:00Z'::timestamptz + i*interval '1 day',
      '2030-01-01 14:00Z'::timestamptz + i*interval '1 day',false,'mixed',2,2,'pairs',ctb,'open',p_venue_id=>vb);
  end loop;
  select count(*) into n from public.fixtures where club_id=cb;
  insert into smoke_results values('CREATE_B_10',n=10,n::text);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ua,'role','authenticated')::text,true);
  select count(*) into n from public.fixtures where club_id=cb;
  insert into smoke_results values('FOREIGN_FIXTURE_READ_DENIED',n=0,n::text);
 select count(*) into n from public.club_diary_view where club_id=ca and source_kind='fixture';
 insert into smoke_results values('OWN_FIXTURES_IN_DIARY',n=10,n::text);
 select count(*) into n from public.club_diary_view where club_id=cb and source_kind='fixture';
 insert into smoke_results values('FOREIGN_FIXTURES_HIDDEN_IN_DIARY',n=0,n::text);
  err:=null;
  begin
    perform public.create_fixture_with_setup_v2(cb,'2030-02-01 12:00Z','2030-02-01 14:00Z',false,'mixed',2,2,'pairs',ctb,'open',p_venue_id=>vb);
  exception when others then err:=sqlerrm; end;
  insert into smoke_results values('FOREIGN_FIXTURE_CREATE_DENIED',err='You do not have permission to create this fixture.',coalesce(err,'UNEXPECTED SUCCESS'));
  select count(*) into before_n from public.fixtures where club_id=ca;
  err:=null;
  begin
    -- Bad venue is rejected by a trigger after entering fixture INSERT.
    perform public.create_fixture_with_setup_v2(ca,'2030-02-01 12:00Z','2030-02-01 14:00Z',false,'mixed',2,2,'pairs',cta,'open',p_venue_id=>vb);
  exception when others then err:=sqlerrm; end;
  select count(*) into n from public.fixtures where club_id=ca;
  insert into smoke_results values('FOREIGN_VENUE_ATOMIC_REJECTION',err='Venue does not belong to club' and n=before_n,coalesce(err,'UNEXPECTED SUCCESS'));
  select count(*) into n from public.teams where id=tb;
  insert into smoke_results values('FOREIGN_TEAM_READ_DENIED',n=0,n::text);
  update public.teams set description='SMOKE UNAUTHORIZED WRITE' where id=tb;
  get diagnostics n=row_count;
  insert into smoke_results values('FOREIGN_TEAM_UPDATE_DENIED',n=0,n::text);
  select count(*) into n from public.user_club_dashboard_filters where user_id=ub;
  insert into smoke_results values('FOREIGN_FILTER_READ_DENIED',n=0,n::text);
  update public.user_club_dashboard_filters set filter_json='{"smoke":"unauthorized"}' where user_id=ub;
  get diagnostics n=row_count;
  insert into smoke_results values('FOREIGN_FILTER_UPDATE_DENIED',n=0,n::text);
  reset role;
  update public.club_memberships set is_active=false where club_id=ca and member_profile_id=pa;
  set local role authenticated;
  err:=null;
  begin
    perform public.create_fixture_with_setup_v2(ca,'2030-02-01 12:00Z','2030-02-01 14:00Z',false,'mixed',2,2,'pairs',cta,'open',p_venue_id=>va);
  exception when others then err:=sqlerrm; end;
  insert into smoke_results values('INACTIVE_ADMIN_CREATE_DENIED',err='You do not have permission to create this fixture.',coalesce(err,'UNEXPECTED SUCCESS'));
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  set local role anon;
  select count(*) into n from public.teams where id in(ta,tb);
  insert into smoke_results values('ANONYMOUS_TEAM_READ_DENIED',n=0,n::text);
  reset role;
  select count(*) into n from public.fixtures where club_id in(ca,cb);
  insert into smoke_results values('EXACT_20_FIXTURES',n=20,n::text);
  select count(*) into n from public.fixture_rinks r join public.fixtures f on f.id=r.fixture_id where f.club_id in(ca,cb);
  insert into smoke_results values('EXACT_40_RINKS',n=40,n::text);
  insert into smoke_results values('NO_EMAIL_ENQUEUED',(select count(*) from public.email_queue)=base_email,'queue count compared');
  insert into smoke_results values('NO_NOTIFICATION_ENQUEUED',(select count(*) from public.notification_queue)=base_notifications,'queue count compared');
  insert into smoke_results values('CRON_STILL_DISABLED',not exists(select 1 from cron.job where active),'all jobs checked');
end $test$;
select * from smoke_results order by case_id;
rollback;
