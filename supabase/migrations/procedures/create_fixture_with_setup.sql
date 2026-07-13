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

  v_assignment jsonb;
  v_team_no integer;
  v_position integer;
  v_member_profile_id_text text;
  v_display_name text;
  v_marker_required boolean;
  v_request_marker boolean;
begin
  -- ==========================================================
  -- BASIC VALIDATION
  -- ==========================================================

  if p_start_at is null
     or p_end_at is null
     or p_start_at >= p_end_at then
    raise exception 'Invalid fixture start/end time.';
  end if;

  if p_competition_type_id is null then
    raise exception 'Fixture type is required.';
  end if;

  if p_rinks_required < 0 then
    raise exception 'Rinks required cannot be negative.';
  end if;

  if p_players_per_rink < 1
     or p_players_per_rink > 4 then
    raise exception 'Players per rink must be between 1 and 4.';
  end if;

  if jsonb_typeof(coalesce(p_home_rink_labels, '[]'::jsonb)) <> 'array' then
    raise exception 'Home rink labels must be supplied as a JSON array.';
  end if;

  if jsonb_typeof(coalesce(p_rink_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Rink assignments must be supplied as a JSON array.';
  end if;

  if jsonb_typeof(
       coalesce(p_team_selection_members, '[]'::jsonb)
     ) <> 'array' then
    raise exception 'Team selection members must be supplied as a JSON array.';
  end if;


  -- ==========================================================
  -- VALIDATE RINK ASSIGNMENT PAYLOAD
  --
  -- Supported positions:
  --   1-4       players
  --   101-104   opponents
  --   201       marker
  --
  -- An assignment can contain:
  --   member_profile_id
  -- or
  --   display_name, for an external opponent
  --
  -- A marker-state item may contain neither identity where it
  -- only records marker_required/request_marker for that rink.
  -- ==========================================================

  for v_assignment in
    select value
    from jsonb_array_elements(
      coalesce(p_rink_assignments, '[]'::jsonb)
    )
  loop
    begin
      v_team_no := nullif(v_assignment->>'team_no', '')::integer;
      v_position := nullif(v_assignment->>'position', '')::integer;
    exception
      when invalid_text_representation then
        raise exception
          'Every rink assignment must contain a valid team_no and position.';
    end;

    if v_team_no is null
       or v_team_no < 1
       or v_team_no > p_rinks_required then
      raise exception
        'Invalid rink/team number % in rink assignments.',
        coalesce(v_team_no, 0);
    end if;

    if v_position is null
       or not (
         v_position between 1 and p_players_per_rink
         or v_position between 101 and (100 + p_players_per_rink)
         or v_position = 201
       ) then
      raise exception
        'Invalid position % for rink/team %.',
        coalesce(v_position, 0),
        v_team_no;
    end if;

    v_member_profile_id_text :=
      nullif(btrim(coalesce(
        v_assignment->>'member_profile_id',
        ''
      )), '');

    v_display_name :=
      nullif(btrim(coalesce(
        v_assignment->>'display_name',
        ''
      )), '');

    v_marker_required :=
      coalesce(
        nullif(v_assignment->>'marker_required', '')::boolean,
        false
      );

    v_request_marker :=
      coalesce(
        nullif(v_assignment->>'request_marker', '')::boolean,
        false
      );

    if v_member_profile_id_text is not null
       and v_display_name is not null then
      raise exception
        'Rink/team % position % cannot contain both a member and an external name.',
        v_team_no,
        v_position;
    end if;

    if v_display_name is not null
       and not (
         v_position between 101 and (100 + p_players_per_rink)
       ) then
      raise exception
        'External names can only be used in opponent positions.';
    end if;

    if v_request_marker and v_position <> 201 then
      raise exception
        'A marker request must use marker position 201.';
    end if;

    if v_marker_required and v_position <> 201 then
      raise exception
        'Marker-required state must use marker position 201.';
    end if;

    if v_member_profile_id_text is null
       and v_display_name is null
       and not (
         v_position = 201
         and (v_marker_required or v_request_marker)
       ) then
      raise exception
        'Rink/team % position % has no member or external name.',
        v_team_no,
        v_position;
    end if;
  end loop;


  -- No two payload entries may occupy the same position
  -- on the same rink.
  if exists (
    select 1
    from (
      select
        (a.item->>'team_no')::integer as team_no,
        (a.item->>'position')::integer as position,
        count(*) as item_count
      from jsonb_array_elements(
        coalesce(p_rink_assignments, '[]'::jsonb)
      ) as a(item)
      group by
        (a.item->>'team_no')::integer,
        (a.item->>'position')::integer
      having count(*) > 1
    ) duplicates
  ) then
    raise exception
      'More than one assignment was supplied for the same rink position.';
  end if;


  -- A known member may only appear once within the fixture.
  if exists (
    select 1
    from (
      select
        nullif(a.item->>'member_profile_id', '')::uuid
          as member_profile_id,
        count(*) as item_count
      from jsonb_array_elements(
        coalesce(p_rink_assignments, '[]'::jsonb)
      ) as a(item)
      where nullif(a.item->>'member_profile_id', '') is not null
      group by nullif(a.item->>'member_profile_id', '')::uuid
      having count(*) > 1
    ) duplicates
  ) then
    raise exception
      'The same member cannot occupy more than one position in a fixture.';
  end if;


  -- ==========================================================
  -- FINAL SERVER-SIDE RINK CAPACITY CHECK
  -- ==========================================================

  if p_is_home = true
     and p_green_area_id is not null
     and p_rinks_required > 0 then

    select free_capacity_rinks
    into v_free_rinks
    from public.get_green_rink_availability(
      p_green_area_id,
      p_start_at,
      p_end_at
    )
    limit 1;

    if v_free_rinks is null then
      raise exception
        'No rink availability returned for this green.';
    end if;

    if v_free_rinks < p_rinks_required then
      raise exception
        'Not enough rinks available: % free, % required.',
        v_free_rinks,
        p_rinks_required;
    end if;
  end if;


  -- ==========================================================
  -- CREATE FIXTURE
  -- ==========================================================

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


  -- ==========================================================
  -- CREATE FIXTURE RINKS
  --
  -- marker_required is derived from the position-201 item for
  -- that rink. A named marker or open request also means the
  -- rink requires a marker.
  -- ==========================================================

  if p_rinks_required > 0 then
    insert into public.fixture_rinks (
      fixture_id,
      fixture_rink_no,
      format,
      players_per_rink,
      home_rink_label,
      marker_required
    )
    select
      v_fixture_id,
      gs.team_no,

      case
        when p_players_per_rink = 3 then 'triples'
        when p_players_per_rink = 2 then 'pairs'
        when p_players_per_rink = 1 then 'singles'
        else 'rinks'
      end,

      p_players_per_rink,
      labels.home_rink_label,

      exists (
        select 1
        from jsonb_array_elements(
          coalesce(p_rink_assignments, '[]'::jsonb)
        ) as marker(item)
        where (marker.item->>'team_no')::integer = gs.team_no
          and (marker.item->>'position')::integer = 201
          and (
            coalesce(
              nullif(marker.item->>'marker_required', '')::boolean,
              false
            )
            or coalesce(
              nullif(marker.item->>'request_marker', '')::boolean,
              false
            )
            or nullif(
              btrim(coalesce(
                marker.item->>'member_profile_id',
                ''
              )),
              ''
            ) is not null
          )
      )

    from generate_series(
      1,
      p_rinks_required
    ) as gs(team_no)

    left join (
      select
        (x->>'team_no')::integer as team_no,
        nullif(btrim(x->>'home_rink_label'), '')
          as home_rink_label
      from jsonb_array_elements(
        coalesce(p_home_rink_labels, '[]'::jsonb)
      ) as x
    ) labels
      on labels.team_no = gs.team_no;
  end if;


  -- ==========================================================
  -- CREATE TEAM SELECTION
  -- ==========================================================

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


  -- ==========================================================
  -- CREATE RINK ASSIGNMENTS
  --
  -- Marker-state-only entries are excluded because they have no
  -- member_profile_id or display_name.
  -- ==========================================================

  if jsonb_array_length(
       coalesce(p_rink_assignments, '[]'::jsonb)
     ) > 0 then

    insert into public.fixture_rink_assignments (
      fixture_id,
      fixture_rink_id,
      member_profile_id,
      display_name,
      position
    )
    select
      v_fixture_id,
      fr.id,

      case
        when nullif(
          btrim(coalesce(
            a.item->>'member_profile_id',
            ''
          )),
          ''
        ) is null
        then null
        else (a.item->>'member_profile_id')::uuid
      end,

      nullif(
        btrim(coalesce(
          a.item->>'display_name',
          ''
        )),
        ''
      ),

      (a.item->>'position')::integer

    from jsonb_array_elements(
      coalesce(p_rink_assignments, '[]'::jsonb)
    ) as a(item)

    join public.fixture_rinks fr
      on fr.fixture_id = v_fixture_id
     and fr.fixture_rink_no =
       (a.item->>'team_no')::integer

    where
      nullif(
        btrim(coalesce(
          a.item->>'member_profile_id',
          ''
        )),
        ''
      ) is not null

      or nullif(
        btrim(coalesce(
          a.item->>'display_name',
          ''
        )),
        ''
      ) is not null;
  end if;


  -- ==========================================================
  -- CREATE OPEN MARKER REQUESTS
  --
  -- The marker request belongs to the individual fixture rink.
  -- No request is opened where a marker has already been
  -- assigned at position 201.
  -- ==========================================================

  insert into public.fixture_marker_requests (
    fixture_rink_id,
    status,
    requested_by_member_profile_id
  )
  select
    fr.id,
    'open',
    p_captain_member_profile_id

  from jsonb_array_elements(
    coalesce(p_rink_assignments, '[]'::jsonb)
  ) as marker(item)

  join public.fixture_rinks fr
    on fr.fixture_id = v_fixture_id
   and fr.fixture_rink_no =
     (marker.item->>'team_no')::integer

  where
    (marker.item->>'position')::integer = 201

    and coalesce(
      nullif(marker.item->>'request_marker', '')::boolean,
      false
    )

    and not exists (
      select 1
      from public.fixture_rink_assignments fra
      where fra.fixture_rink_id = fr.id
        and fra.position = 201
    );


  -- ==========================================================
  -- CREATE TEAM-SELECTION MEMBER RECORDS
  --
  -- External opponents deliberately do not appear here because
  -- they have no member_profile_id and cannot receive an
  -- acceptance request.
  -- ==========================================================

  if v_team_selection_id is not null
     and jsonb_array_length(
       coalesce(p_team_selection_members, '[]'::jsonb)
     ) > 0 then

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

      coalesce(
        nullif(m.item->>'role', ''),
        'player'
      )::selection_member_role,

      coalesce(
        nullif(m.item->>'acceptance', ''),
        'pending'
      )::acceptance_status,

      coalesce(
        nullif(m.item->>'is_selected', '')::boolean,
        true
      )

    from jsonb_array_elements(
      coalesce(p_team_selection_members, '[]'::jsonb)
    ) as m(item)

    where nullif(
      btrim(coalesce(
        m.item->>'member_profile_id',
        ''
      )),
      ''
    ) is not null;
  end if;


  return v_fixture_id;
end;
$$;