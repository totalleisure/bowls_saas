create or replace function public.create_fixture_with_setup(
  p_club_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_is_home boolean,
  p_section text,
  p_rinks_required integer,
  p_players_per_rink integer,
  p_competition_type_id uuid,
  p_team_id uuid default null,
  p_team_name text default null,
  p_requires_rsvp boolean default true,
  p_venue_id uuid default null,
  p_opponent_venue_id uuid default null,
  p_green_area_id uuid default null,
  p_orientation text default null,
  p_captain_member_profile_id uuid default null,
  p_notes text default null,
  p_create_team_selection boolean default false,
  p_team_selection_status text default 'published',
  p_home_rink_labels jsonb default '[]'::jsonb,
  p_rink_assignments jsonb default '[]'::jsonb,
  p_team_selection_members jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fixture_id uuid;
  v_team_selection_id uuid;
  v_free_rinks integer;
begin
  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'Invalid fixture start/end time.';
  end if;

  if p_competition_type_id is null then
    raise exception 'Fixture type is required.';
  end if;

  if p_rinks_required < 0 then
    raise exception 'Rinks required cannot be negative.';
  end if;

  if p_players_per_rink < 1 then
    raise exception 'Players per rink must be at least 1.';
  end if;

  -- Final server-side capacity check for home fixtures using rinks.
  if p_is_home = true and p_green_area_id is not null and p_rinks_required > 0 then
    select free_capacity_rinks
    into v_free_rinks
    from public.get_green_rink_availability(
      p_green_area_id,
      p_start_at,
      p_end_at
    )
    limit 1;

    if v_free_rinks is null then
      raise exception 'No rink availability returned for this green.';
    end if;

    if v_free_rinks < p_rinks_required then
      raise exception 'Not enough rinks available: % free, % required.',
        v_free_rinks,
        p_rinks_required;
    end if;
  end if;

  insert into public.fixtures (
    club_id,
    start_at,
    end_at,
    is_home,
    section,
    rinks_required,
    players_per_rink,
    competition_type_id,
    team_id,
    team_name,
    requires_rsvp,
    venue_id,
    opponent_venue_id,
    green_area_id,
    orientation,
    captain_member_profile_id,
    notes
  )
  values (
    p_club_id,
    p_start_at,
    p_end_at,
    p_is_home,
    coalesce(nullif(trim(p_section), ''), 'open')::section,
    p_rinks_required,
    p_players_per_rink,
    p_competition_type_id,
    p_team_id,
    nullif(trim(coalesce(p_team_name, '')), ''),
    p_requires_rsvp,
    p_venue_id,
    p_opponent_venue_id,
    p_green_area_id,
    nullif(trim(coalesce(p_orientation, '')), '')::orientation,
    p_captain_member_profile_id,
    nullif(trim(coalesce(p_notes, '')), '')
  )
  returning id into v_fixture_id;

  if p_rinks_required > 0 then
    insert into public.fixture_rinks (
      fixture_id,
      fixture_rink_no,
      format,
      players_per_rink,
      home_rink_label
    )
    select
      v_fixture_id,
      gs.team_no,
      case
        when p_players_per_rink = 3 then 'triples'
        when p_players_per_rink = 2 then 'pairs'
        when p_players_per_rink = 1 then 'singles'
        else 'fours'
      end,
      p_players_per_rink,
      labels.home_rink_label
    from generate_series(1, p_rinks_required) as gs(team_no)
    left join (
      select
        (x->>'team_no')::integer as team_no,
        nullif(x->>'home_rink_label', '') as home_rink_label
      from jsonb_array_elements(p_home_rink_labels) as x
    ) labels on labels.team_no = gs.team_no;
  end if;

  if p_create_team_selection then
    insert into public.team_selections (
      fixture_id,
      status
    )
    values (
      v_fixture_id,
      p_team_selection_status::selection_status
    )
    returning id into v_team_selection_id;
  end if;

  if jsonb_array_length(p_rink_assignments) > 0 then
    insert into public.fixture_rink_assignments (
      fixture_id,
      fixture_rink_id,
      member_profile_id,
      position
    )
    select
      v_fixture_id,
      fr.id,
      (a.item->>'member_profile_id')::uuid,
      (a.item->>'position')::integer
    from jsonb_array_elements(p_rink_assignments) as a(item)
    join public.fixture_rinks fr
      on fr.fixture_id = v_fixture_id
     and fr.fixture_rink_no = (a.item->>'team_no')::integer
    where nullif(a.item->>'member_profile_id', '') is not null;
  end if;

  if v_team_selection_id is not null
     and jsonb_array_length(p_team_selection_members) > 0 then
    insert into public.team_selection_members (
      team_selection_id,
      member_profile_id,
      role,
      acceptance,
      is_selected
    )
    select
      v_team_selection_id,
      (m.item->>'member_profile_id')::uuid,
      coalesce(nullif(m.item->>'role', ''), 'player')::selection_member_role,
      coalesce(nullif(m.item->>'acceptance', ''), 'pending')::acceptance_status,
      coalesce((m.item->>'is_selected')::boolean, true)
    from jsonb_array_elements(p_team_selection_members) as m(item)
    where nullif(m.item->>'member_profile_id', '') is not null;
  end if;

  return v_fixture_id;
end;
$$;