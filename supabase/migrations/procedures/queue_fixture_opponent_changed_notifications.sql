create or replace function public.queue_fixture_opponent_changed_notifications(
  p_fixture_id uuid,
  p_old_opponent_venue_id uuid,
  p_new_opponent_venue_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changed_by_member_profile_id uuid;
  v_team_selection_id uuid;

  v_old_opponent_name text;
  v_new_opponent_name text;

  v_start_at timestamptz;
  v_fixture_name text;
  v_team_name text;
  v_selection_mode text;
  v_is_published boolean := false;

  v_queued_count integer := 0;
begin
  /*
   * Who made the change?
   */
  select public.my_member_profile_id()
  into v_changed_by_member_profile_id;

  /*
   * Current fixture details.
   */
  select
    f.start_at,
    coalesce(nullif(ct.name, ''), 'Fixture'),
    nullif(
      trim(
        coalesce(t.name, f.team_name, '')
      ),
      ''
    ),
    lower(coalesce(ct.selection_mode, ''))
  into
    v_start_at,
    v_fixture_name,
    v_team_name,
    v_selection_mode
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.teams t
    on t.id = f.team_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found', p_fixture_id;
  end if;

  /*
   * Venue names before and after the change.
   */
  select name
  into v_old_opponent_name
  from public.venues
  where id = p_old_opponent_venue_id;

  select name
  into v_new_opponent_name
  from public.venues
  where id = p_new_opponent_venue_id;

  v_old_opponent_name :=
    coalesce(nullif(v_old_opponent_name, ''), 'To be confirmed');

  v_new_opponent_name :=
    coalesce(nullif(v_new_opponent_name, ''), 'To be confirmed');

  /*
   * Current team selection, if one exists.
   */
  select
  id,
  status = 'published'
  into
  v_team_selection_id,
  v_is_published
  from public.team_selections
  where fixture_id = p_fixture_id
  order by created_at desc nulls last
  limit 1;

  /*
 * Before publication, opponent changes are still part of fixture preparation.
 * Do not notify selected members until the fixture has been published.
 */
  if coalesce(v_is_published, false) = false then
  return 0;
  end if;

  /*
   * Build one deduplicated recipient set.
   *
   * Recipients:
   *   - fixture captain
   *   - fixture vice-captain
   *   - selected team-selection members
   *   - RSVP Yes / Maybe members
   *
   * The person making the change is excluded.
   */
  with recipients as (

    select f.captain_member_profile_id as member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.captain_member_profile_id is not null

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.vice_captain_member_profile_id is not null

    union

    select tsm.member_profile_id
    from public.team_selection_members tsm
    join public.team_selections ts
      on ts.id = tsm.team_selection_id
    where ts.fixture_id = p_fixture_id
      and tsm.member_profile_id is not null
      and coalesce(tsm.is_selected, false) = true

    union

    select frsvp.member_profile_id
    from public.fixture_rsvps frsvp
    where frsvp.fixture_id = p_fixture_id
      and frsvp.member_profile_id is not null
      and lower(coalesce(frsvp.status::text, '')) in ('yes', 'maybe')
  ),
  inserted as (
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
      'fixture_opponent_changed',
      v_changed_by_member_profile_id,
      r.member_profile_id,
      p_fixture_id,
      v_team_selection_id,
      jsonb_build_object(
        'old_opponent_venue_id', p_old_opponent_venue_id,
        'new_opponent_venue_id', p_new_opponent_venue_id,
        'old_opponent_name', v_old_opponent_name,
        'new_opponent_name', v_new_opponent_name,
        'start_at', v_start_at,
        'fixture_name', v_fixture_name,
        'team_name', v_team_name,
        'selection_mode', v_selection_mode
      ),
      'pending'
    from recipients r
    where r.member_profile_id is not null
      and (
        v_changed_by_member_profile_id is null
        or r.member_profile_id <> v_changed_by_member_profile_id
      )
    returning 1
  )
  select count(*)
  into v_queued_count
  from inserted;

  return v_queued_count;
end;
$$;