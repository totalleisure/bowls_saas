create or replace function public.communications_health_check(
  p_fixture_id uuid
)
returns table (
  item text,
  expected integer,
  actual integer,
  status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team_selection_id uuid;
begin
  select ts.id
  into v_team_selection_id
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc
  limit 1;

  if v_team_selection_id is null then
    raise exception 'No team selection found for fixture %', p_fixture_id;
  end if;

  return query
  with
  assigned as (
    select distinct fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id
  ),
  reserves as (
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_team_selection_id
      and tsm.is_selected = true
      and tsm.role = 'reserve'::selection_member_role
  ),
  captains as (
    select distinct x.member_profile_id
    from public.fixtures f
    cross join lateral (
      values
        (f.captain_member_profile_id),
        (f.vice_captain_member_profile_id)
    ) x(member_profile_id)
    where f.id = p_fixture_id
      and x.member_profile_id is not null
  ),
  selected_people as (
    select member_profile_id from assigned
    union
    select member_profile_id from reserves
  ),
  team_pool as (
    select tm.member_profile_id
    from public.fixtures f
    join public.team_members tm on tm.team_id = f.team_id
    where f.id = p_fixture_id
      and coalesce(tm.is_active, true) = true
  ),
  not_selected as (
    select member_profile_id from team_pool
    except
    select member_profile_id from selected_people
  ),
  expected_counts as (
    select
      (select count(*) from assigned)::int as players,
      (select count(*) from reserves)::int as reserves,
      (select count(*) from captains)::int as captains,
      (select count(*) from not_selected)::int as not_selected
  ),
  totals as (
    select
      players,
      reserves,
      captains,
      not_selected,
      players + reserves + captains + not_selected as total_comms,
      players + reserves + captains as team_sheet_comms
    from expected_counts
  ),
  rows as (
    select 'Playing players'::text item, players expected,
      (select count(*)::int from public.notification_queue nq where nq.fixture_id = p_fixture_id and nq.team_selection_id = v_team_selection_id and nq.event_type = 'team_published_player') actual
    from totals

    union all
    select 'Reserves', reserves,
      (select count(*)::int from public.notification_queue nq where nq.fixture_id = p_fixture_id and nq.team_selection_id = v_team_selection_id and nq.event_type = 'team_published_reserve')
    from totals

    union all
    select 'Captain/Vice copies', captains,
      (select count(*)::int from public.notification_queue nq where nq.fixture_id = p_fixture_id and nq.team_selection_id = v_team_selection_id and nq.event_type in ('team_published_captain', 'team_published_vice'))
    from totals

    union all
    select 'Not selected', not_selected,
      (select count(*)::int from public.notification_queue nq where nq.fixture_id = p_fixture_id and nq.team_selection_id = v_team_selection_id and nq.event_type in ('team_published_not_selected', 'team_published_incomplete_request'))
    from totals

    union all
    select 'Notifications queued', total_comms,
      (select count(*)::int from public.notification_queue nq where nq.fixture_id = p_fixture_id and nq.team_selection_id = v_team_selection_id and nq.event_type like 'team_published%')
    from totals

    union all
    select 'App notifications created', total_comms,
      (select count(*)::int from public.app_notifications an where an.fixture_id = p_fixture_id and an.team_selection_id = v_team_selection_id and an.type like 'team_published%')
    from totals

    union all
    select 'Emails queued', total_comms,
      (select count(*)::int from public.email_queue eq where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_team_selection_id and eq.event_type like 'team_published%')
    from totals

    union all
    select 'Emails sent', total_comms,
      (select count(*)::int from public.email_queue eq where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_team_selection_id and eq.event_type like 'team_published%' and eq.status = 'sent')
    from totals

    union all
    select 'Emails failed', 0,
      (select count(*)::int from public.email_queue eq where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_team_selection_id and eq.event_type like 'team_published%' and eq.status = 'failed')
    from totals

    union all
    select 'Team sheets required', team_sheet_comms,
      (select count(*)::int from public.email_queue eq where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_team_selection_id and eq.event_type in ('team_published_player', 'team_published_reserve', 'team_published_captain', 'team_published_vice'))
    from totals

    union all
    select 'Team sheets attached', team_sheet_comms,
      (select count(*)::int from public.email_queue eq where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_team_selection_id and eq.event_type in ('team_published_player', 'team_published_reserve', 'team_published_captain', 'team_published_vice') and jsonb_array_length(coalesce(eq.attachments, '[]'::jsonb)) > 0)
    from totals

    union all
    select 'Team sheets sent', team_sheet_comms,
      (select count(*)::int from public.email_queue eq where eq.fixture_id = p_fixture_id and eq.team_selection_id = v_team_selection_id and eq.event_type in ('team_published_player', 'team_published_reserve', 'team_published_captain', 'team_published_vice') and eq.status = 'sent' and jsonb_array_length(coalesce(eq.attachments, '[]'::jsonb)) > 0)
    from totals
  )
  select
    rows.item,
    rows.expected,
    rows.actual,
    case
      when rows.expected = rows.actual then 'OK'
      else 'CHECK'
    end as status
  from rows;
end;
$$;