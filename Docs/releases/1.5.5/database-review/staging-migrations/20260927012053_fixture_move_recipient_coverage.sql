-- Include published selected players/reserves and fixture leaders alongside assigned players/markers.
-- Keep one notification per member and retain timestamp-based retry deduplication.
CREATE OR REPLACE FUNCTION public.queue_fixture_moved_notifications(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int := 0;
begin
  if not public.can_manage_fixture(p_fixture_id) then
    raise exception 'You do not have permission to queue fixture-move notifications.';
  end if;

  -- Serialize retries for this fixture without locking other clubs' fixtures.
  perform 1 from public.fixtures where id = p_fixture_id for update;

  with recipients as (
    -- Includes assigned markers (position 201), as well as playing positions.
    select fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id

    union

    select tsm.member_profile_id
    from public.team_selections ts
    join public.team_selection_members tsm on tsm.team_selection_id = ts.id
    where ts.fixture_id = p_fixture_id
      and ts.status = 'published'
      and tsm.is_selected = true

    union

    select f.captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id
  )
  insert into public.notification_queue (
    target_member_profile_id,
    event_type,
    fixture_id,
    payload,
    status,
    created_at
  )
  select distinct
    recipient.member_profile_id,
    'fixture_moved',
    f.id,
    jsonb_build_object(
      'fixture_id', f.id,
      'fixture_name', coalesce(ct.name, 'Fixture'),
      'old_start_at', p_old_start_at,
      'old_end_at', p_old_end_at,
      'new_start_at', f.start_at,
      'new_end_at', f.end_at,
      'is_home', f.is_home,
      'venue_name', venue.name,
      'opponent_name', opponent.name
    ),
    'pending',
    now()
  from public.fixtures f
  cross join recipients recipient
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues venue
    on venue.id = f.venue_id
  left join public.venues opponent
    on opponent.id = f.opponent_venue_id
  where f.id = p_fixture_id
    and recipient.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = f.id
        and existing.event_type = 'fixture_moved'
        and existing.target_member_profile_id = recipient.member_profile_id
        and (existing.payload ->> 'old_start_at')::timestamptz is not distinct from p_old_start_at
        and nullif(existing.payload ->> 'old_end_at', '')::timestamptz is not distinct from p_old_end_at
        and (existing.payload ->> 'new_start_at')::timestamptz is not distinct from f.start_at
        and nullif(existing.payload ->> 'new_end_at', '')::timestamptz is not distinct from f.end_at
        and existing.status in ('pending', 'processing', 'sent')
    );

  get diagnostics v_count = row_count;

  return v_count;
end;
$function$
;



