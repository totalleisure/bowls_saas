create or replace function public.queue_team_acceptance_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_team_selection record;
  v_fixture record;
  v_player_name text;
  v_fixture_label text;
  v_home_away text;
  v_venue_name text;
  v_opponent_name text;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.acceptance is not distinct from new.acceptance then
    return new;
  end if;

  if new.acceptance is null then
    return new;
  end if;

  select ts.*
  into v_team_selection
  from public.team_selections ts
  where ts.id = new.team_selection_id;

  if v_team_selection is null then
    return new;
  end if;

  if v_team_selection.status is distinct from 'published' then
    return new;
  end if;

  select f.*
  into v_fixture
  from public.fixtures f
  where f.id = v_team_selection.fixture_id;

  if v_fixture is null then
    return new;
  end if;

  if v_fixture.captain_member_profile_id is null then
    return new;
  end if;

  -- Do not notify the captain about their own acceptance change.
  if v_fixture.captain_member_profile_id = new.member_profile_id then
    return new;
  end if;

  select mp.display_name
  into v_player_name
  from public.member_profiles mp
  where mp.id = new.member_profile_id;

  v_home_away := case when v_fixture.is_home then 'Home' else 'Away' end;

  select coalesce(v.name, '')
  into v_venue_name
  from public.venues v
  where v.id = v_fixture.venue_id;

  select coalesce(ov.name, '')
  into v_opponent_name
  from public.venues ov
  where ov.id = v_fixture.opponent_venue_id;

  v_fixture_label := coalesce(
    nullif(v_fixture.team_name, ''),
    case
      when v_opponent_name <> '' then
        v_home_away || ' v ' || v_opponent_name
      else
        'Fixture'
    end
  );

  /*
    Coalesce repeated acceptance changes before the queue is processed.

    Example:
      pending  -> accepted
      accepted -> declined
      declined -> accepted

    If all of that happens before process_notification_queue runs,
    the captain should receive one Team Update, not three.
  */
  delete from public.notification_queue nq
  where nq.event_type = 'team_acceptance_changed'
    and nq.fixture_id = v_fixture.id
    and nq.team_selection_id = new.team_selection_id
    and nq.member_profile_id = new.member_profile_id
    and nq.target_member_profile_id = v_fixture.captain_member_profile_id
    and nq.status = 'pending';

  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  values (
    'team_acceptance_changed',
    new.member_profile_id,
    v_fixture.captain_member_profile_id,
    v_fixture.id,
    new.team_selection_id,
    jsonb_build_object(
      'changed_member_profile_id', new.member_profile_id,
      'old_acceptance', old.acceptance::text,
      'new_acceptance', new.acceptance::text,
      'player_name', coalesce(v_player_name, 'A player'),
      'fixture_label', v_fixture_label,
      'fixture_date', v_fixture.start_at,
      'home_away', v_home_away,
      'venue_name', coalesce(v_venue_name, ''),
      'opponent_name', coalesce(v_opponent_name, '')
    ),
    'pending'
  );

  return new;
end;
$function$;