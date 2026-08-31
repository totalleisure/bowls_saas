create or replace function public.queue_post_publication_player_change(
  p_team_selection_member_id uuid,
  p_event_type text,
  p_actor_member_profile_id uuid
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_row record;
begin
  if p_event_type not in ('fixture_selected', 'reserve_promoted') then
    raise exception 'Unsupported player-change event type.';
  end if;

  select
    tsm.member_profile_id,
    ts.id as team_selection_id,
    ts.status::text as selection_status,
    f.id as fixture_id,
    f.start_at,
    f.is_home,
    coalesce(nullif(btrim(f.team_name), ''), 'Fixture') as fixture_label,
    coalesce(v.name, ov.name, '') as venue_name,
    coalesce(nullif(btrim(mp.display_name), ''),
      concat_ws(' ', nullif(btrim(mp.first_name), ''), nullif(btrim(mp.last_name), '')),
      'A player') as player_name,
    fr.fixture_rink_no as team_no,
    fr.home_rink_label,
    fr.players_per_rink,
    fra.position
  into v_row
  from public.team_selection_members tsm
  join public.team_selections ts on ts.id = tsm.team_selection_id
  join public.fixtures f on f.id = ts.fixture_id
  join public.member_profiles mp on mp.id = tsm.member_profile_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  left join public.fixture_rink_assignments fra
    on fra.fixture_id = f.id and fra.member_profile_id = tsm.member_profile_id
  left join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
  where tsm.id = p_team_selection_member_id
    and tsm.role = 'player'::public.selection_member_role
    and tsm.is_selected = true;

  if not found
     or v_row.selection_status <> 'published'
     or exists (
       select 1 from public.fixtures f
       where f.id = v_row.fixture_id and f.cancelled_at is not null
     ) then
    return false;
  end if;

  if p_event_type = 'reserve_promoted' then
    update public.notification_queue set status = 'cancelled'
    where fixture_id = v_row.fixture_id
      and target_member_profile_id = v_row.member_profile_id
      and event_type = 'team_published_reserve' and status = 'pending';

    update public.email_queue set status = 'cancelled'
    where fixture_id = v_row.fixture_id
      and member_profile_id = v_row.member_profile_id
      and event_type = 'team_published_reserve'
      and status in ('pending', 'failed') and sent_at is null;
  end if;

  insert into public.notification_queue (
    event_type, member_profile_id, target_member_profile_id,
    fixture_id, team_selection_id, payload, status
  ) values (
    p_event_type,
    p_actor_member_profile_id,
    v_row.member_profile_id,
    v_row.fixture_id,
    v_row.team_selection_id,
    jsonb_strip_nulls(jsonb_build_object(
      'player_name', v_row.player_name,
      'fixture_label', v_row.fixture_label,
      'fixture_date', v_row.start_at,
      'start_at', v_row.start_at,
      'home_away', case when v_row.is_home then 'Home' else 'Away' end,
      'venue_name', v_row.venue_name,
      'team_no', v_row.team_no,
      'home_rink_label', v_row.home_rink_label,
      'players_per_rink', v_row.players_per_rink,
      'position', v_row.position,
      'role', 'player',
      'old_role', case when p_event_type = 'reserve_promoted' then 'reserve' end,
      'new_role', case when p_event_type = 'reserve_promoted' then 'player' end
    )),
    'pending'
  );

  return true;
end;
$function$;

revoke all on function public.queue_post_publication_player_change(uuid, text, uuid)
from public, anon, authenticated, service_role;
