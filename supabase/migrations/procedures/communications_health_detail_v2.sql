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
          and nullif(mail.attachments->0->>'compositionVersion', '') is not null
          and (
            mail.status = 'sent'
            or mail.attachments->0->>'compositionVersion' = v_composition_version::text
          )
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
