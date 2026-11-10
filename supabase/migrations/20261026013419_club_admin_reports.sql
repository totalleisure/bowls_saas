
-- Admin reports and minimal first-party usage counters. No historical events are invented.
create schema if not exists app_reporting;
revoke all on schema app_reporting from public, anon, authenticated;
create table app_reporting.settings (
  singleton boolean primary key default true check(singleton),
  recording_started_at timestamptz not null default clock_timestamp()
);
insert into app_reporting.settings(singleton) values(true);
create table app_reporting.events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete cascade,
  kind text not null check(kind in ('login','app_visit','screen_view')),
  screen text,
  platform text,
  occurred_at timestamptz not null default clock_timestamp(),
  check((kind='login' and club_id is null) or (kind<>'login' and club_id is not null))
);
alter table app_reporting.settings enable row level security;
alter table app_reporting.events enable row level security;
revoke all on all tables in schema app_reporting from public,anon,authenticated;
create index reporting_club_time on app_reporting.events(club_id,occurred_at,user_id);
create index reporting_user_time on app_reporting.events(user_id,occurred_at);
create unique index reporting_login_once on app_reporting.events(user_id,occurred_at) where kind='login';

create function app_reporting.capture_login() returns trigger language plpgsql security definer
set search_path='' as $$
begin
  if new.last_sign_in_at is not null then
    if TG_OP='INSERT' then
      insert into app_reporting.events(user_id,kind,occurred_at) values(new.id,'login',new.last_sign_in_at) on conflict do nothing;
    elsif new.last_sign_in_at is distinct from old.last_sign_in_at then
      insert into app_reporting.events(user_id,kind,occurred_at) values(new.id,'login',new.last_sign_in_at) on conflict do nothing;
    end if;
  end if;
  return new;
end $$;
revoke all on function app_reporting.capture_login() from public,anon,authenticated;
create trigger reporting_login after insert or update of last_sign_in_at on auth.users
for each row execute function app_reporting.capture_login();

create function public.record_club_usage(p_club_id uuid,p_event_id uuid,p_kind text,p_screen text,p_platform text)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id where cm.club_id=p_club_id and cm.is_active and mp.user_id=auth.uid()) then
    raise exception 'Active Club membership required' using errcode='42501';
  end if;
  if p_kind not in ('app_visit','screen_view') or p_kind is null
    or p_screen not in ('Dashboard','Month View','List View','Day View','Rinks View','Membership','Reports') or p_screen is null
    or p_platform not in ('iOS','Android','Windows','macOS','Linux','Web') or p_platform is null or p_event_id is null then
    raise exception 'Invalid usage event' using errcode='22023';
  end if;
  insert into app_reporting.events(id,user_id,club_id,kind,screen,platform)
  values(p_event_id,auth.uid(),p_club_id,p_kind,p_screen,p_platform) on conflict(id) do nothing;
end $$;
revoke all on function public.record_club_usage(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.record_club_usage(uuid,uuid,text,text,text) to authenticated;

create function public.get_club_admin_report(p_club_id uuid,p_from date,p_to date,p_offset int default 0,p_limit int default 500)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_from timestamptz; v_to timestamptz;
begin
  if auth.uid() is null or not (public.is_app_superuser() or public.is_club_admin(p_club_id)) then
    raise exception 'Club administrator access required' using errcode='42501';
  end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>3660 or p_offset<0 or p_limit not between 1 and 1000 then
    raise exception 'Invalid reporting range or page' using errcode='22023';
  end if;
  v_from := p_from::timestamp at time zone 'Europe/London';
  v_to := (p_to+1)::timestamp at time zone 'Europe/London';
  with members as materialized (
    select cm.member_profile_id,mp.user_id,coalesce(mp.last_name,'') surname,coalesce(mp.first_name,'') forename,
      coalesce(mp.email_address,'') email,coalesce(mp.phone,'') mobile,coalesce(mp.home_phone,'') home_phone,
      coalesce(mp.office_phone,'') office_phone,cm.role::text member_type,cm.is_active active,cm.is_coach coach,
      mp.is_captain_managed captain_managed,cm.created_at member_since,u.last_sign_in_at last_sign_in,
      (mp.user_id is not null) login_enabled
    from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
    left join auth.users u on u.id=mp.user_id where cm.club_id=p_club_id
  ), page as materialized (
    select * from members order by lower(surname),lower(forename),member_profile_id limit p_limit offset p_offset
  ), period_fixtures as materialized (
    select f.id,f.created_by_user_id,f.cancelled_at,f.archived_at,f.start_at,
      coalesce(nullif(btrim(f.team_name),''),ct.name,f.fixture_type::text,'Fixture') label,
      coalesce(ct.name,f.fixture_type::text,'Fixture') fixture_type
    from public.fixtures f left join public.competition_types ct on ct.id=f.competition_type_id
    where f.club_id=p_club_id and f.start_at>=v_from and f.start_at<v_to
  ), involvement as (
    select tsm.member_profile_id,f.id fixture_id from period_fixtures f
      join public.team_selections ts on ts.fixture_id=f.id
      join public.team_selection_members tsm on tsm.team_selection_id=ts.id
      where tsm.is_selected and f.cancelled_at is null and f.archived_at is null
    union
    select fra.member_profile_id,f.id from period_fixtures f
      join public.fixture_rinks fr on fr.fixture_id=f.id
      join public.fixture_rink_assignments fra on fra.fixture_rink_id=fr.id
      where f.cancelled_at is null and f.archived_at is null
  ), member_rows as (
    select p.*,
      (select count(*) from app_reporting.events e where e.user_id=p.user_id and e.kind='login' and e.occurred_at>=v_from and e.occurred_at<v_to) recorded_logins,
      (select count(*) from app_reporting.events e where e.user_id=p.user_id and e.club_id=p_club_id and e.kind='app_visit' and e.occurred_at>=v_from and e.occurred_at<v_to) app_visits,
      (select count(*) from app_reporting.events e where e.user_id=p.user_id and e.club_id=p_club_id and e.kind='screen_view' and e.occurred_at>=v_from and e.occurred_at<v_to) screen_views,
      (select max(e.occurred_at) from app_reporting.events e where e.user_id=p.user_id and e.club_id=p_club_id) last_app_activity,
      (select count(*) from public.fixtures f where f.club_id=p_club_id and f.created_by_user_id=p.user_id and f.created_at>=v_from and f.created_at<v_to) bookings_created,
      (select count(*) from involvement i where i.member_profile_id=p.member_profile_id) selected_fixtures,
      (select count(*) from public.fixture_rsvps r join public.fixtures f on f.id=r.fixture_id where f.club_id=p_club_id and r.member_profile_id=p.member_profile_id and r.responded_at>=v_from and r.responded_at<v_to) fixture_responses
    from page p
  ), booking_groups as (
    select fixture_type,count(*) fixtures,count(*) filter(where cancelled_at is not null) cancelled,
      count(*) filter(where archived_at is not null) archived,
      count(*) filter(where cancelled_at is null and archived_at is null) current_fixtures
    from period_fixtures group by fixture_type
  ), screens as (
    select screen,platform,count(*) views,count(distinct user_id) members
    from app_reporting.events where club_id=p_club_id and kind='screen_view' and occurred_at>=v_from and occurred_at<v_to group by screen,platform
  )
  select jsonb_build_object(
    'club_name',(select name from public.clubs where id=p_club_id),
    'generated_at',clock_timestamp(),'from',p_from,'to',p_to,
    'recording_started_at',(select recording_started_at from app_reporting.settings where singleton),
    'total_members',(select count(*) from members),
    'members',coalesce((select jsonb_agg(to_jsonb(x) order by lower(surname),lower(forename),member_profile_id) from member_rows x),'[]'::jsonb),
    'summary',case when p_offset=0 then (select jsonb_build_object(
      'active_members',count(*) filter(where active),'inactive_members',count(*) filter(where not active),
      'ever_signed_in',count(*) filter(where active and last_sign_in is not null),
      'last_sign_in_in_period',count(*) filter(where active and last_sign_in>=v_from and last_sign_in<v_to),
      'no_recorded_sign_in',count(*) filter(where active and last_sign_in is null),
      'without_email',count(*) filter(where active and btrim(email)=''),
      'without_phone',count(*) filter(where active and btrim(mobile||home_phone||office_phone)=''),
      'bookings_created',(select count(*) from public.fixtures where club_id=p_club_id and created_at>=v_from and created_at<v_to),
      'recorded_logins',(select count(*) from app_reporting.events e where e.kind='login' and e.occurred_at>=v_from and e.occurred_at<v_to and exists(select 1 from members m where m.user_id=e.user_id)),
      'app_visits',(select count(*) from app_reporting.events where club_id=p_club_id and kind='app_visit' and occurred_at>=v_from and occurred_at<v_to),
      'screen_views',(select count(*) from app_reporting.events where club_id=p_club_id and kind='screen_view' and occurred_at>=v_from and occurred_at<v_to),
      'active_app_users',(select count(distinct user_id) from app_reporting.events where club_id=p_club_id and kind in ('app_visit','screen_view') and occurred_at>=v_from and occurred_at<v_to)
    ) from members) else null end,
    'bookings',case when p_offset=0 then coalesce((select jsonb_agg(x order by fixture_type) from booking_groups x),'[]'::jsonb) else '[]'::jsonb end,
    'screens',case when p_offset=0 then coalesce((select jsonb_agg(x order by views desc,screen,platform) from screens x),'[]'::jsonb) else '[]'::jsonb end
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.get_club_admin_report(uuid,date,date,int,int) from public,anon;
grant execute on function public.get_club_admin_report(uuid,date,date,int,int) to authenticated;
comment on function public.get_club_admin_report(uuid,date,date,int,int) is 'Admin-only Club reports. Member type is the App role, not a subscription category. Login counts start at recording_started_at and are account-wide; visits/views require the reporting-enabled App. Selected fixtures are current assignments, not proof of attendance. Booking groups use fixture dates; bookings_created uses creation dates. All dates use Europe/London.';
