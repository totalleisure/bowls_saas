create or replace function public.create_fixture_with_setup_v2(
  p_club_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_is_home boolean,
  p_section text,
  p_rinks_required integer,
  p_players_per_rink integer,
  p_format text,
  p_competition_type_id uuid,
  p_dress_code text,
  p_team_id uuid default null,
  p_team_name text default null,
  p_requires_rsvp boolean default true,
  p_venue_id uuid default null,
  p_opponent_venue_id uuid default null,
  p_green_area_id uuid default null,
  p_orientation text default null,
  p_captain_member_profile_id uuid default null,
  p_vice_captain_member_profile_id uuid default null,
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
  v_format text;
  v_actor_member_profile_id uuid;
  v_fixture_type_bookable_by_members boolean;
  v_fixture_type_is_internal boolean;
  v_fixture_type_selection_mode text;
  v_fixture_type_uses_rinks boolean;
  v_fixture_type_team_selection_enabled boolean;
  v_is_superuser boolean := false;
  v_is_active_club_fixture_creator boolean := false;
  v_is_ordinary_member_booking boolean := false;
  v_has_permission boolean := false;
  v_dress_code text;
  v_dress_codes public.dress_code[];

  v_assignment jsonb;
  v_team_no integer;
  v_position integer;
  v_member_profile_id_text text;
  v_display_name text;
  v_marker_required boolean;
  v_request_marker boolean;
begin
  v_dress_code := lower(
    coalesce(nullif(btrim(p_dress_code), ''), 'open')
  );

  if v_dress_code = 'open' then
    v_dress_codes := '{}'::public.dress_code[];
  elsif v_dress_code in ('whites', 'greys', 'blacks', 'jackets') then
    v_dress_codes := array[v_dress_code::public.dress_code];
  else
    raise exception 'Unsupported dress code: %', p_dress_code;
  end if;

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

  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select
    ct.bookable_by_members,
    ct.is_internal,
    lower(btrim(coalesce(ct.selection_mode, ''))),
    ct.uses_rinks,
    ct.team_selection_enabled
  into
    v_fixture_type_bookable_by_members,
    v_fixture_type_is_internal,
    v_fixture_type_selection_mode,
    v_fixture_type_uses_rinks,
    v_fixture_type_team_selection_enabled
  from public.competition_types ct
  where ct.id = p_competition_type_id
    and ct.club_id = p_club_id
    and ct.is_active = true;

  if not found then
    raise exception 'Fixture Type is not active for this club.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = p_club_id
      and cm.member_profile_id = v_actor_member_profile_id
      and cm.is_active = true
      and lower(cm.role::text) in ('admin', 'selector')
  )
  into v_is_active_club_fixture_creator;

  v_is_ordinary_member_booking :=
    not v_is_superuser
    and not v_is_active_club_fixture_creator
    and v_fixture_type_bookable_by_members = true
    and exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = p_club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
    );

  v_has_permission :=
    v_is_superuser
    or v_is_active_club_fixture_creator
    or v_is_ordinary_member_booking;

  if not v_has_permission then
    raise exception 'You do not have permission to create this fixture.';
  end if;

  if v_is_ordinary_member_booking
     and not (
       v_fixture_type_is_internal = true
       and v_fixture_type_selection_mode = 'preselect'
       and v_fixture_type_uses_rinks = true
       and v_fixture_type_team_selection_enabled = true
       and p_is_home = true
       and p_team_id is null
       and p_opponent_venue_id is null
       and coalesce(
         p_captain_member_profile_id = v_actor_member_profile_id,
         false
       )
       and p_vice_captain_member_profile_id is null
       and p_create_team_selection = true
       and lower(btrim(coalesce(p_team_selection_status, ''))) = 'published'
       and coalesce(p_requires_rsvp = false, false)
     ) then
    raise exception
      'Member-bookable fixtures must use the simple internal Pre-Select workflow.';
  end if;

  if p_rinks_required < 0 then
    raise exception 'Rinks required cannot be negative.';
  end if;

  if p_players_per_rink < 1
     or p_players_per_rink > 4 then
    raise exception 'Players per rink must be between 1 and 4.';
  end if;

  v_format := lower(
    btrim(
      coalesce(
        nullif(p_format, ''),
        case
          when p_players_per_rink = 1 then 'singles'
          when p_players_per_rink = 2 then 'pairs'
          when p_players_per_rink = 3 then 'triples'
          else 'rinks'
        end
      )
    )
  );

  if p_rinks_required > 0
     and not (
       (v_format = 'singles' and p_players_per_rink = 1)
       or (v_format = 'pairs' and p_players_per_rink = 2)
       or (v_format = 'aussie_pairs' and p_players_per_rink = 2)
       or (v_format = 'triples' and p_players_per_rink = 3)
       or (v_format in ('fours', 'rinks') and p_players_per_rink = 4)
     ) then
    raise exception
      'Invalid format/player combination: format=%, players_per_rink=%',
      v_format,
      p_players_per_rink;
  end if;

  if p_captain_member_profile_id is not null
     and p_captain_member_profile_id = p_vice_captain_member_profile_id then
    raise exception
      'The captain/organiser and vice/deputy must be different members.';
  end if;

  if exists (
    select 1
    from unnest(array[
      p_captain_member_profile_id,
      p_vice_captain_member_profile_id
    ]) as leader(member_profile_id)
    where leader.member_profile_id is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = p_club_id
          and cm.member_profile_id = leader.member_profile_id
          and cm.is_active = true
      )
  ) then
    raise exception
      'The captain/organiser and vice/deputy must be active club members.';
  end if;

  if p_team_id is not null
     and not exists (
       select 1
       from public.teams t
       where t.id = p_team_id
         and t.club_id = p_club_id
     ) then
    raise exception 'The selected team does not belong to this club.';
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

  -- Every known assignee must be an active member of this fixture's club.
  if exists (
    select 1
    from jsonb_array_elements(
      coalesce(p_rink_assignments, '[]'::jsonb)
    ) as a(item)
    where nullif(btrim(coalesce(a.item->>'member_profile_id', '')), '')
      is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = p_club_id
          and cm.member_profile_id =
            (a.item->>'member_profile_id')::uuid
          and cm.is_active = true
      )
  ) then
    raise exception
      'One or more rink assignments are not active members of this club.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      coalesce(p_team_selection_members, '[]'::jsonb)
    ) as m(item)
    where nullif(btrim(coalesce(m.item->>'member_profile_id', '')), '')
      is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = p_club_id
          and cm.member_profile_id =
            (m.item->>'member_profile_id')::uuid
          and cm.is_active = true
      )
  ) then
    raise exception
      'One or more selected people are not active members of this club.';
  end if;

  if v_is_ordinary_member_booking then
    -- The booking member must occupy a player slot. This prevents nomination
    -- of an unrelated captain while preserving the existing simple-booking UI.
    if not exists (
      select 1
      from jsonb_array_elements(
        coalesce(p_rink_assignments, '[]'::jsonb)
      ) as a(item)
      where nullif(a.item->>'member_profile_id', '')::uuid =
        v_actor_member_profile_id
        and (a.item->>'position')::integer
          between 1 and p_players_per_rink
    ) then
      raise exception
        'The booking member must occupy a player position.';
    end if;

    -- Every selected member must correspond to exactly one submitted rink
    -- assignment with the role implied by its position.
    if exists (
      select 1
      from jsonb_array_elements(
        coalesce(p_team_selection_members, '[]'::jsonb)
      ) as m(item)
      where nullif(m.item->>'member_profile_id', '') is null
        or coalesce(nullif(m.item->>'is_selected', '')::boolean, true) = false
        or lower(coalesce(nullif(m.item->>'acceptance', ''), 'pending')) <>
          case
            when (m.item->>'member_profile_id')::uuid =
              v_actor_member_profile_id then 'accepted'
            else 'pending'
          end
        or not exists (
          select 1
          from jsonb_array_elements(
            coalesce(p_rink_assignments, '[]'::jsonb)
          ) as a(item)
          where nullif(a.item->>'member_profile_id', '')::uuid =
            (m.item->>'member_profile_id')::uuid
            and lower(coalesce(nullif(m.item->>'role', ''), 'player')) =
              case
                when (a.item->>'position')::integer
                  between 1 and p_players_per_rink then 'player'
                when (a.item->>'position')::integer
                  between 101 and (100 + p_players_per_rink) then 'opponent'
                when (a.item->>'position')::integer = 201 then 'marker'
              end
        )
    ) then
      raise exception
        'Member-booking team selection does not match its rink assignments.';
    end if;

    -- Conversely, no known assignee may be omitted from the team selection;
    -- this keeps selection communications limited to the submitted booking.
    if exists (
      select 1
      from jsonb_array_elements(
        coalesce(p_rink_assignments, '[]'::jsonb)
      ) as a(item)
      where nullif(a.item->>'member_profile_id', '') is not null
        and not exists (
          select 1
          from jsonb_array_elements(
            coalesce(p_team_selection_members, '[]'::jsonb)
          ) as m(item)
          where (m.item->>'member_profile_id')::uuid =
            (a.item->>'member_profile_id')::uuid
        )
    ) then
      raise exception
        'Every assigned member must appear in the team selection.';
    end if;
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
    dress_code,
    competition_type_id,
    team_id,
    team_name,
    requires_rsvp,
    venue_id,
    opponent_venue_id,
    green_area_id,
    orientation,
    captain_member_profile_id,
    vice_captain_member_profile_id,
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
    v_dress_codes,
    p_competition_type_id,
    p_team_id,
    nullif(trim(coalesce(p_team_name, '')), ''),
    p_requires_rsvp,
    p_venue_id,
    p_opponent_venue_id,
    p_green_area_id,
    nullif(trim(coalesce(p_orientation, '')), '')::orientation,
    p_captain_member_profile_id,
    p_vice_captain_member_profile_id,
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

      v_format,

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

revoke all on function public.create_fixture_with_setup_v2(
  uuid, timestamptz, timestamptz, boolean, text, integer, integer, text,
  uuid, text, uuid, text, boolean, uuid, uuid, uuid, text, uuid, uuid,
  text, boolean, text, jsonb, jsonb, jsonb
) from public, anon, service_role;

grant execute on function public.create_fixture_with_setup_v2(
  uuid, timestamptz, timestamptz, boolean, text, integer, integer, text,
  uuid, text, uuid, text, boolean, uuid, uuid, uuid, text, uuid, uuid,
  text, boolean, text, jsonb, jsonb, jsonb
) to authenticated;
