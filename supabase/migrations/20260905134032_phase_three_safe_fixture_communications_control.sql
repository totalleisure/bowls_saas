-- Phase III: secured, fixture-scoped communications analysis and repair.

revoke all on function public.communications_health_check(uuid) from public, anon, authenticated;
revoke all on function public.communications_health_detail(uuid) from public, anon, authenticated;
revoke all on function public.communications_fixture_status(uuid) from public, anon, authenticated;

create or replace function public.communications_require_superuser()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_superusers su where su.user_id = auth.uid()
  ) then
    raise exception 'Superuser access required.';
  end if;
end;
$function$;

revoke all on function public.communications_require_superuser()
from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.queue_team_publication_communications(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_fixture_label text;
  v_start_at timestamptz;
  v_home_away text;
  v_venue_name text;
  v_team_id uuid;
  v_captain uuid;
  v_vice uuid;
  v_required integer;
  v_assigned integer;
  v_missing integer;
  v_count integer := 0;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if not (
    public.can_manage_team_selection(p_fixture_id)
    or exists (
      select 1 from public.app_superusers su where su.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.fixtures f
      where f.id = p_fixture_id
        and (
          f.captain_member_profile_id = v_current_member
          or f.vice_captain_member_profile_id = v_current_member
        )
    )
  ) then
    raise exception 'You do not have permission to queue team communications.';
  end if;

  select
    coalesce(nullif(f.team_name, ''), 'Fixture'),
    f.start_at,
    case when f.is_home then 'Home' else 'Away' end,
    coalesce(v.name, ov.name, ''),
    f.team_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_fixture_label,
    v_start_at,
    v_home_away,
    v_venue_name,
    v_team_id,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where f.id = p_fixture_id;

  select coalesce(sum(players_per_rink), 0)
  into v_required
  from public.fixture_rinks
  where fixture_id = p_fixture_id;

  select count(*)
  into v_assigned
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and fra.position between 1 and fr.players_per_rink;

  v_missing := greatest(v_required - v_assigned, 0);

  -- Assigned players
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'team_published_player',
    v_current_member,
    fra.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id

    -- Only real club members can receive a player notification.
    and fra.member_profile_id is not null

    -- Only actual player positions, not opponents/markers/request rows.
    and fra.position between 1 and fr.players_per_rink

    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = fra.member_profile_id
        and nq.event_type = 'team_published_player'
    );

  get diagnostics v_count = row_count;

  -- Reserves
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'team_published_reserve',
    v_current_member,
    tsm.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'reserve'::selection_member_role
    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = tsm.member_profile_id
        and nq.event_type = 'team_published_reserve'
    );

  -- Captain copy
  if v_captain is not null then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'team_published_captain',
      v_current_member,
      v_captain,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_captain
        and nq.event_type = 'team_published_captain'
    );
  end if;

  -- Vice captain copy
  if v_vice is not null and v_vice is distinct from v_captain then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'team_published_vice',
      v_current_member,
      v_vice,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_vice
        and nq.event_type = 'team_published_vice'
    );
  end if;

  -- Available but not selected: notification/email, no team sheet.
  -- Assumes team_members has team_id/member_profile_id/is_active.
  if v_team_id is not null then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      case
        when p_allow_incomplete = true and v_missing > 0
          then 'team_published_incomplete_request'
        else 'team_published_not_selected'
      end,
      v_current_member,
      tm.member_profile_id,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', false
      ),
      'pending'
    from public.team_members tm
    where tm.team_id = v_team_id
      and tm.member_profile_id is not null
      and coalesce(tm.is_active, true) = true
      and not exists (
        select 1
        from public.team_selection_members tsm
        where tsm.team_selection_id = p_team_selection_id
          and tsm.member_profile_id = tm.member_profile_id
          and tsm.is_selected = true
      )
      and not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = p_team_selection_id
          and nq.target_member_profile_id = tm.member_profile_id
          and nq.event_type in (
            'team_published_not_selected',
            'team_published_incomplete_request'
          )
      );
  end if;

  return v_count;
end;
$function$;

revoke all on function
  public.queue_team_publication_communications(uuid, uuid, boolean)
from public, anon;

grant execute on function
  public.queue_team_publication_communications(uuid, uuid, boolean)
to authenticated;

create or replace function public.communications_health_check_v2(p_fixture_id uuid)
returns table(item text, expected integer, actual integer, status text)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  perform public.communications_require_superuser();

  return query
  with detail as materialized (
    select * from public.communications_health_detail_v2(p_fixture_id)
  ),
  rows as (
    select 1 sort_order, 'Playing players'::text item,
      count(*) filter (where category = 'Player')::integer expected,
      count(*) filter (where category = 'Player' and app_notification = 'Created')::integer actual
    from detail
    union all select 2, 'Opponents',
      count(*) filter (where category = 'Opponent')::integer,
      count(*) filter (where category = 'Opponent' and app_notification = 'Created')::integer from detail
    union all select 3, 'Named markers',
      count(*) filter (where category = 'Named Marker')::integer,
      count(*) filter (where category = 'Named Marker' and app_notification = 'Created')::integer from detail
    union all select 4, 'Marker volunteers',
      count(*) filter (where category like 'Marker Volunteer%')::integer,
      count(*) filter (where category like 'Marker Volunteer%' and app_notification = 'Created')::integer from detail
    union all select 5, 'Reserves',
      count(*) filter (where category = 'Reserve')::integer,
      count(*) filter (where category = 'Reserve' and app_notification = 'Created')::integer from detail
    union all select 6, 'Captain/Vice copies',
      count(*) filter (where category in ('Captain','Vice Captain'))::integer,
      count(*) filter (where category in ('Captain','Vice Captain') and app_notification = 'Created')::integer from detail
    union all select 7, 'Not selected',
      count(*) filter (where category = 'Not Selected')::integer,
      count(*) filter (where category = 'Not Selected' and app_notification = 'Created')::integer from detail
    union all select 8, 'App notifications created',
      count(*)::integer,
      count(*) filter (where app_notification = 'Created')::integer from detail
    union all select 9, 'Emails queued',
      count(*) filter (where email_status <> 'No Email')::integer,
      count(*) filter (where email_status not in ('No Email','Missing'))::integer from detail
    union all select 10, 'Emails sent',
      count(*) filter (where email_status <> 'No Email')::integer,
      count(*) filter (where email_status = 'sent')::integer from detail
    union all select 11, 'Emails failed', 0,
      count(*) filter (where email_status = 'failed')::integer from detail
    union all select 12, 'Team sheets required',
      count(*) filter (where team_sheet <> 'Not Required')::integer,
      count(*) filter (where team_sheet <> 'Not Required')::integer from detail
    union all select 13, 'Team sheets attached',
      count(*) filter (where team_sheet <> 'Not Required')::integer,
      count(*) filter (where team_sheet = 'Attached')::integer from detail
    union all select 14, 'Team sheets sent',
      count(*) filter (where team_sheet <> 'Not Required' and email_status <> 'No Email')::integer,
      count(*) filter (where team_sheet = 'Attached' and email_status = 'sent')::integer from detail
  )
  select rows.item, rows.expected, rows.actual,
    case when rows.item = 'Emails failed'
      then case when rows.actual = 0 then 'OK' else 'CHECK' end
      when rows.actual >= rows.expected then 'OK' else 'CHECK' end
  from rows order by rows.sort_order;
end;
$function$;

revoke all on function public.communications_health_check_v2(uuid)
from public, anon, authenticated;
grant execute on function public.communications_health_check_v2(uuid)
to authenticated;

create or replace function public.communications_health_detail_v2(p_fixture_id uuid)
returns table(
  member_profile_id uuid,
  member_name text,
  category text,
  app_notification text,
  email_status text,
  team_sheet text,
  email_address text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_selection_id uuid;
  v_selection_mode text;
  v_composition_version integer;
begin
  perform public.communications_require_superuser();

  select ts.id, lower(coalesce(ct.selection_mode::text, '')),
         ts.composition_version
  into v_selection_id, v_selection_mode, v_composition_version
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  join lateral (
    select x.id, x.composition_version
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if v_selection_id is null then raise exception 'Team selection not found.'; end if;

  return query
  with participants as (
    select tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_selection_id and tsm.is_selected = true
    union
    select fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id and fra.member_profile_id is not null
  ),
  preselect_assignments as (
    select distinct fra.member_profile_id,
      case when fra.position = 201 then 'Named Marker'
           when fra.position between 101 and 100 + fr.players_per_rink then 'Opponent'
           else 'Player' end category,
      'fixture_selected'::text event_type,
      true team_sheet_required,
      fr.fixture_rink_no team_no,
      fra.position
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where v_selection_mode = 'preselect'
      and fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
      and (fra.position between 1 and fr.players_per_rink
        or fra.position between 101 and 100 + fr.players_per_rink
        or fra.position = 201)
  ),
  leadership as (
    select x.member_profile_id, x.category, x.event_type,
           true team_sheet_required, null::integer team_no, null::integer position
    from public.fixtures f
    cross join lateral (values
      (f.captain_member_profile_id, 'Captain'::text, 'team_published_captain'::text),
      (f.vice_captain_member_profile_id, 'Vice Captain'::text, 'team_published_vice'::text)
    ) x(member_profile_id, category, event_type)
    where f.id = p_fixture_id and x.member_profile_id is not null
      and not exists (
        select 1 from participants p where p.member_profile_id = x.member_profile_id
      )
  ),
  marker_volunteers as (
    select distinct mlm.member_profile_id,
      'Marker Volunteer - Team ' || fr.fixture_rink_no::text category,
      'marker_request_opened'::text event_type,
      false team_sheet_required,
      fr.fixture_rink_no team_no,
      null::integer position
    from public.fixture_marker_requests mr
    join public.fixture_rinks fr on fr.id = mr.fixture_rink_id
    join public.fixtures f on f.id = fr.fixture_id
    join public.volunteer_tasks vt on vt.club_id = f.club_id
      and vt.task_code = 'marker' and vt.is_active = true
    join public.mailing_list_members mlm on mlm.mailing_list_id = vt.mailing_list_id
      and mlm.is_active = true
    join public.club_memberships cm on cm.club_id = f.club_id
      and cm.member_profile_id = mlm.member_profile_id and cm.is_active = true
    where v_selection_mode = 'preselect'
      and fr.fixture_id = p_fixture_id and mr.status = 'open'
      and not exists (
        select 1 from participants p where p.member_profile_id = mlm.member_profile_id
      )
  ),
  ordinary_players as (
    select distinct fra.member_profile_id, 'Player'::text category,
      'team_published_player'::text event_type, true team_sheet_required,
      null::integer team_no, null::integer position
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where v_selection_mode <> 'preselect' and fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
      and fra.position between 1 and fr.players_per_rink
  ),
  ordinary_reserves as (
    select distinct tsm.member_profile_id, 'Reserve'::text category,
      'team_published_reserve'::text event_type, true team_sheet_required,
      null::integer team_no, null::integer position
    from public.team_selection_members tsm
    where v_selection_mode <> 'preselect'
      and tsm.team_selection_id = v_selection_id
      and tsm.is_selected = true and lower(tsm.role::text) = 'reserve'
      and not exists (
        select 1 from ordinary_players p where p.member_profile_id = tsm.member_profile_id
      )
  ),
  ordinary_not_selected as (
    select distinct tm.member_profile_id, 'Not Selected'::text category,
      'team_published_not_selected'::text event_type, false team_sheet_required,
      null::integer team_no, null::integer position
    from public.fixtures f
    join public.team_members tm on tm.team_id = f.team_id and tm.is_active = true
    where v_selection_mode <> 'preselect' and f.id = p_fixture_id
      and not exists (
        select 1 from participants p where p.member_profile_id = tm.member_profile_id
      )
  ),
  expected as (
    select * from preselect_assignments
    union all select * from leadership
    union all select * from marker_volunteers
    union all select * from ordinary_players
    union all select * from ordinary_reserves
    union all select * from ordinary_not_selected
  )
  select e.member_profile_id,
    coalesce(nullif(btrim(mp.display_name), ''),
      nullif(btrim(coalesce(mp.first_name, '') || ' ' || coalesce(mp.last_name, '')), ''),
      'Unknown') member_name,
    e.category,
    case when app.id is null then 'Missing' else 'Created' end app_notification,
    case when nullif(btrim(mp.email_address), '') is null then 'No Email'
         else coalesce(mail.status, 'Missing') end email_status,
    case when not e.team_sheet_required then 'Not Required'
         when mail.id is null then 'Missing'
         when case
          when jsonb_typeof(coalesce(mail.attachments, '[]'::jsonb)) = 'array'
          then jsonb_array_length(coalesce(mail.attachments, '[]'::jsonb)) = 1
          and mail.attachments->0->>'contentType' = 'application/pdf'
          and nullif(mail.attachments->0->>'contentBytes', '') is not null
          and length(mail.attachments->0->>'contentBytes') <= 2700000
          and mail.attachments->0->>'contentBytes' like 'JVBERi%'
          and mail.attachments->0->>'compositionVersion' = v_composition_version::text
          else false
         end then 'Attached' else 'Missing' end team_sheet,
    mp.email_address
  from expected e
  left join public.member_profiles mp on mp.id = e.member_profile_id
  left join lateral (
    select an.id from public.app_notifications an
    where an.fixture_id = p_fixture_id
      and an.team_selection_id = v_selection_id
      and an.member_profile_id = e.member_profile_id
      and (an.type = e.event_type
        or (e.category = 'Player' and an.type in ('fixture_selected','reserve_promoted')))
    order by an.created_at desc limit 1
  ) app on true
  left join lateral (
    select eq.id, eq.status::text, eq.attachments
    from public.email_queue eq
    where eq.fixture_id = p_fixture_id
      and eq.team_selection_id = v_selection_id
      and eq.member_profile_id = e.member_profile_id
      and eq.status <> 'cancelled'
      and (eq.event_type = e.event_type
        or (e.category = 'Player' and eq.event_type in ('fixture_selected','reserve_promoted')))
    order by eq.created_at desc limit 1
  ) mail on true
  order by case e.category when 'Player' then 1 when 'Opponent' then 2
    when 'Named Marker' then 3 when 'Reserve' then 4 when 'Captain' then 5
    when 'Vice Captain' then 6 when 'Not Selected' then 8 else 7 end,
    member_name;
end;
$function$;

revoke all on function public.communications_health_detail_v2(uuid)
from public, anon, authenticated;
grant execute on function public.communications_health_detail_v2(uuid)
to authenticated;

create or replace function public.communications_fixture_status_v2(p_fixture_id uuid)
returns table(
  status text,
  next_action text,
  message text,
  progress integer,
  can_repair boolean,
  can_prepare boolean,
  can_send boolean,
  can_retry boolean,
  blocking_issues jsonb,
  diagnostics jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_base record;
  v_selection_id uuid;
  v_pending_notifications integer := 0;
  v_pending_sheet_failures integer := 0;
  v_pending_emails integer := 0;
  v_stale_failures integer := 0;
  v_app_expected integer := 0;
  v_app_actual integer := 0;
  v_email_expected integer := 0;
  v_email_actual integer := 0;
  v_email_sent integer := 0;
  v_email_failed integer := 0;
  v_sheet_expected integer := 0;
  v_sheet_actual integer := 0;
begin
  perform public.communications_require_superuser();

  select * into v_base from public.communications_fixture_status(p_fixture_id);

  if v_base.next_action = 'open_fixture' then
    return query select v_base.status, v_base.next_action, v_base.message,
      v_base.progress, false, false, false, false,
      v_base.blocking_issues, v_base.diagnostics;
    return;
  end if;

  select ts.id into v_selection_id
  from public.team_selections ts where ts.fixture_id = p_fixture_id
  order by ts.created_at desc limit 1;

  select
    coalesce(max(expected) filter (where item = 'App notifications created'),0),
    coalesce(max(actual) filter (where item = 'App notifications created'),0),
    coalesce(max(expected) filter (where item = 'Emails queued'),0),
    coalesce(max(actual) filter (where item = 'Emails queued'),0),
    coalesce(max(actual) filter (where item = 'Emails sent'),0),
    coalesce(max(actual) filter (where item = 'Emails failed'),0),
    coalesce(max(expected) filter (where item = 'Team sheets attached'),0),
    coalesce(max(actual) filter (where item = 'Team sheets attached'),0)
  into v_app_expected, v_app_actual, v_email_expected, v_email_actual,
       v_email_sent, v_email_failed, v_sheet_expected, v_sheet_actual
  from public.communications_health_check_v2(p_fixture_id);

  select count(*) into v_pending_notifications
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id and nq.team_selection_id = v_selection_id
    and nq.status = 'pending';
  select count(*) into v_pending_sheet_failures
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_selection_id
    and nq.status = 'pending'
    and nq.team_sheet_required = true
    and not case
      when jsonb_typeof(coalesce(nq.payload->'attachments', '[]'::jsonb)) = 'array'
      then jsonb_array_length(coalesce(nq.payload->'attachments', '[]'::jsonb)) = 1
      and nq.payload->'attachments'->0->>'contentType' = 'application/pdf'
      and nullif(nq.payload->'attachments'->0->>'contentBytes', '') is not null
      and length(nq.payload->'attachments'->0->>'contentBytes') <= 2700000
      and nq.payload->'attachments'->0->>'contentBytes' like 'JVBERi%'
      and nq.payload->'attachments'->0->>'compositionVersion' = (
        select ts.composition_version::text
        from public.team_selections ts where ts.id = v_selection_id
      )
      else false
    end;
  select count(*) into v_pending_emails
  from public.email_queue eq
  where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_selection_id
    and eq.status = 'pending';
  select count(*) into v_stale_failures
  from public.email_queue eq
  where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_selection_id
    and eq.status = 'failed'
    and eq.last_error = 'Required Team Sheet attachment is missing or stale.';

  diagnostics := coalesce(v_base.diagnostics, '{}'::jsonb) || jsonb_build_object(
    'app_notifications_expected',v_app_expected,
    'app_notifications_actual',v_app_actual,
    'emails_expected',v_email_expected,
    'emails_actual',v_email_actual,
    'emails_sent',v_email_sent,
    'emails_failed',v_email_failed,
    'team_sheets_expected',v_sheet_expected,
    'team_sheets_actual',v_sheet_actual,
    'pending_fixture_notifications',v_pending_notifications,
    'pending_invalid_team_sheets',v_pending_sheet_failures,
    'pending_fixture_emails',v_pending_emails
  );
  blocking_issues := coalesce(v_base.blocking_issues, '[]'::jsonb);

  if v_stale_failures > 0 or v_pending_sheet_failures > 0 then
    return query select 'team_sheets_required'::text,
      'prepare_team_sheets'::text,
      'Current Team Sheet attachments must be prepared before sending.'::text,
      70, false, false, false, false, blocking_issues, diagnostics;
  elsif v_pending_notifications > 0 then
    return query select 'preparation_required'::text, 'prepare_messages'::text,
      'This fixture has pending notifications ready to prepare.'::text,
      65, false, true, false, false, blocking_issues, diagnostics;
  elsif v_app_actual < v_app_expected or v_email_actual < v_email_expected then
    return query select 'communications_repair_required'::text,
      'repair_communications'::text,
      'Current recipients are missing fixture communication records.'::text,
      55, true, false, false, false, blocking_issues, diagnostics;
  elsif v_sheet_actual < v_sheet_expected then
    return query select 'team_sheets_required'::text,
      'prepare_team_sheets'::text,
      'Current Team Sheet attachments must be prepared before sending.'::text,
      70, false, false, false, false, blocking_issues, diagnostics;
  elsif v_email_failed > 0 then
    return query select 'email_retry_required'::text, 'retry_failed_emails'::text,
      'Some fixture emails failed and can be retried safely.'::text,
      80, false, false, false, true, blocking_issues, diagnostics;
  elsif v_pending_emails > 0 or v_email_sent < v_email_expected then
    return query select 'ready_to_send'::text, 'send_emails'::text,
      'This fixture has prepared emails ready to send.'::text,
      90, false, false, true, false, blocking_issues, diagnostics;
  else
    return query select 'communications_complete'::text, 'complete'::text,
      'All expected fixture communications and Team Sheets are complete.'::text,
      100, false, false, false, false, blocking_issues, diagnostics;
  end if;
end;
$function$;

revoke all on function public.communications_fixture_status_v2(uuid)
from public, anon, authenticated;
grant execute on function public.communications_fixture_status_v2(uuid)
to authenticated;

create or replace function public.repair_fixture_publication_communications(
  p_fixture_id uuid
)
returns table(
  team_selection_id uuid,
  deleted_notifications integer,
  deleted_app_notifications integer,
  deleted_emails integer,
  queued_notifications integer,
  processed_notifications integer,
  status text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_team_selection_id uuid;
  v_selection_mode text;
  v_before integer;
  v_after integer;
begin
  perform public.communications_require_superuser();

  select ts.id, lower(coalesce(ct.selection_mode::text, ''))
  into v_team_selection_id, v_selection_mode
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id and x.status::text = 'published'
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if v_team_selection_id is null then
    raise exception 'Published team selection not found.';
  end if;

  select count(*) into v_before
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_team_selection_id
    and nq.status <> 'cancelled';

  if v_selection_mode = 'preselect' then
    perform public.reconcile_preselect_communications(p_fixture_id);
  else
    perform public.queue_team_publication_communications(
      p_fixture_id,
      v_team_selection_id,
      true
    );
  end if;

  select count(*) into v_after
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_team_selection_id
    and nq.status <> 'cancelled';

  return query select
    v_team_selection_id,
    0,
    0,
    0,
    greatest(v_after - v_before, 0),
    0,
    'communications reconciled; no history deleted and no queue processed'::text;
end;
$function$;

revoke all on function public.repair_fixture_publication_communications(uuid)
from public, anon, authenticated;
grant execute on function public.repair_fixture_publication_communications(uuid)
to authenticated;

create or replace function public.process_fixture_notification_queue(
  p_fixture_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_ids uuid[];
begin
  perform public.communications_require_superuser();

  select coalesce(array_agg(nq.id order by nq.created_at), array[]::uuid[])
  into v_ids
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id and nq.status = 'pending';

  if cardinality(v_ids) = 0 then return 0; end if;

  perform set_config(
    'app.notification_queue_ids',
    array_to_string(v_ids, ','),
    true
  );
  return public.process_notification_queue(cardinality(v_ids));
end;
$function$;

revoke all on function public.process_fixture_notification_queue(uuid)
from public, anon, authenticated;
grant execute on function public.process_fixture_notification_queue(uuid)
to authenticated;

create or replace function public.retry_fixture_failed_emails(p_fixture_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_ids uuid[];
begin
  perform public.communications_require_superuser();

  update public.email_queue eq
  set status = 'pending', attempts = 0, last_error = null,
      processing_started_at = null, locked_at = null, locked_by = null
  where eq.fixture_id = p_fixture_id
    and eq.status = 'failed'
    and eq.sent_at is null
    and eq.last_error is distinct from
        'Required Team Sheet attachment is missing or stale.'
  ;

  select coalesce(array_agg(eq.id order by eq.created_at), array[]::uuid[])
  into v_ids
  from public.email_queue eq
  where eq.fixture_id = p_fixture_id and eq.status = 'pending';

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'email_queue_ids', to_jsonb(v_ids),
    'pending_count', cardinality(v_ids)
  );
end;
$function$;

revoke all on function public.retry_fixture_failed_emails(uuid)
from public, anon, authenticated;
grant execute on function public.retry_fixture_failed_emails(uuid)
to authenticated;
