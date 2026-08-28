-- Replace the transitional overload arrangement with one definitive v2
-- implementation and one temporary legacy compatibility wrapper.

-- Exact identity deployed by 20260822173549_add_fixture_dress_override_to_create_rpc.
drop function if exists public.create_fixture_with_setup(
  uuid,
  timestamptz,
  timestamptz,
  boolean,
  text,
  integer,
  integer,
  text,
  uuid,
  text,
  uuid,
  text,
  boolean,
  uuid,
  uuid,
  uuid,
  text,
  uuid,
  uuid,
  text,
  boolean,
  text,
  jsonb,
  jsonb,
  jsonb
);

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

-- Temporary compatibility wrapper for installed clients that do not yet
-- send p_dress_code. All validation, authorization and creation are performed
-- by public.create_fixture_with_setup_v2.
create or replace function public.create_fixture_with_setup(
  p_club_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_is_home boolean,
  p_section text,
  p_rinks_required integer,
  p_players_per_rink integer,
  p_format text,
  p_competition_type_id uuid,
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
  v_dress_code text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select coalesce(nullif(btrim(ct.dress_code), ''), 'open')
  into v_dress_code
  from public.competition_types ct
  where ct.id = p_competition_type_id
    and ct.club_id = p_club_id;

  if not found then
    raise exception 'Fixture Type does not belong to this club.';
  end if;

  return public.create_fixture_with_setup_v2(
    p_club_id,
    p_start_at,
    p_end_at,
    p_is_home,
    p_section,
    p_rinks_required,
    p_players_per_rink,
    p_format,
    p_competition_type_id,
    v_dress_code,
    p_team_id,
    p_team_name,
    p_requires_rsvp,
    p_venue_id,
    p_opponent_venue_id,
    p_green_area_id,
    p_orientation,
    p_captain_member_profile_id,
    p_vice_captain_member_profile_id,
    p_notes,
    p_create_team_selection,
    p_team_selection_status,
    p_home_rink_labels,
    p_rink_assignments,
    p_team_selection_members
  );
end;
$$;

revoke all on function public.create_fixture_with_setup(
  uuid, timestamptz, timestamptz, boolean, text, integer, integer, text,
  uuid, uuid, text, boolean, uuid, uuid, uuid, text, uuid, uuid, text,
  boolean, text, jsonb, jsonb, jsonb
) from public, anon, service_role;

grant execute on function public.create_fixture_with_setup(
  uuid, timestamptz, timestamptz, boolean, text, integer, integer, text,
  uuid, uuid, text, boolean, uuid, uuid, uuid, text, uuid, uuid, text,
  boolean, text, jsonb, jsonb, jsonb
) to authenticated;

create or replace function public.save_preselect_fixture_state(
  p_fixture_id uuid,
  p_assignments jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_players_per_rink integer;
  v_captain_member_profile_id uuid;
  v_vice_captain_member_profile_id uuid;
  v_selection_mode text;
  v_team_selection_id uuid;

  v_is_superuser boolean := false;
  v_has_permission boolean := false;

  v_added jsonb := '[]'::jsonb;
  v_removed jsonb := '[]'::jsonb;
  v_retained jsonb := '[]'::jsonb;
  v_role_changed jsonb := '[]'::jsonb;
  v_marker_events jsonb := '[]'::jsonb;
  v_external_opponents jsonb := '[]'::jsonb;
  v_communications jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Assignments must be supplied as a JSON array.';
  end if;

  select
    f.club_id,
    f.players_per_rink,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id,
    lower(btrim(coalesce(ct.selection_mode, '')))
  into
    v_club_id,
    v_players_per_rink,
    v_captain_member_profile_id,
    v_vice_captain_member_profile_id,
    v_selection_mode
  from public.fixtures f
  join public.competition_types ct
    on ct.id = f.competition_type_id
  where f.id = p_fixture_id
  for update of f;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_selection_mode <> 'preselect' then
    raise exception 'This fixture does not use the Pre-Select workflow.';
  end if;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  v_has_permission :=
    v_is_superuser
    or exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
        and (
          lower(cm.role::text) in ('admin', 'selector')
          or v_actor_member_profile_id = v_captain_member_profile_id
          or v_actor_member_profile_id = v_vice_captain_member_profile_id
        )
    );

  if not v_has_permission then
    raise exception 'You do not have permission to maintain this fixture.';
  end if;

  -- ==========================================================
  -- NORMALISE THE COMPLETE SUBMITTED STATE
  --
  -- Positions:
  --   1–4       players
  --   101–104   opponents
  --   201       marker / marker-state record
  -- ==========================================================

  create temporary table preselect_desired_assignments (
    fixture_rink_id uuid not null,
    position integer not null,
    member_profile_id uuid,
    display_name text,
    marker_required boolean not null default false,
    request_marker boolean not null default false,
    role text
  ) on commit drop;

  insert into preselect_desired_assignments (
    fixture_rink_id,
    position,
    member_profile_id,
    display_name,
    marker_required,
    request_marker,
    role
  )
  select
    nullif(btrim(item->>'fixture_rink_id'), '')::uuid,
    nullif(item->>'position', '')::integer,

    case
      when nullif(
        btrim(coalesce(item->>'member_profile_id', '')),
        ''
      ) is null then null
      else (item->>'member_profile_id')::uuid
    end,

    nullif(
      btrim(coalesce(item->>'display_name', '')),
      ''
    ),

    coalesce(
      nullif(item->>'marker_required', '')::boolean,
      false
    ),

    coalesce(
      nullif(item->>'request_marker', '')::boolean,
      false
    ),

    case
      when nullif(item->>'position', '')::integer
        between 1 and v_players_per_rink
        then 'player'

      when nullif(item->>'position', '')::integer
        between 101 and (100 + v_players_per_rink)
        then 'opponent'

      when nullif(item->>'position', '')::integer = 201
        then 'marker'

      else null
    end

  from jsonb_array_elements(
    coalesce(p_assignments, '[]'::jsonb)
  ) as submitted(item);

  -- Every referenced rink must belong to this fixture.
  if exists (
    select 1
    from preselect_desired_assignments d
    left join public.fixture_rinks fr
      on fr.id = d.fixture_rink_id
     and fr.fixture_id = p_fixture_id
    where fr.id is null
  ) then
    raise exception 'An assignment refers to an invalid fixture rink.';
  end if;

  -- Validate the supported slot positions.
  if exists (
    select 1
    from preselect_desired_assignments d
    where not (
      d.position between 1 and v_players_per_rink
      or d.position between 101 and (100 + v_players_per_rink)
      or d.position = 201
    )
  ) then
    raise exception 'An invalid Pre-Select position was supplied.';
  end if;

  -- Only one submitted record may occupy a rink position.
  if exists (
    select 1
    from preselect_desired_assignments
    group by fixture_rink_id, position
    having count(*) > 1
  ) then
    raise exception
      'More than one assignment was supplied for the same rink position.';
  end if;

  -- A known member can only occupy one slot in this fixture.
  if exists (
    select 1
    from preselect_desired_assignments
    where member_profile_id is not null
    group by member_profile_id
    having count(*) > 1
  ) then
    raise exception
      'The same member cannot occupy more than one position in the fixture.';
  end if;

  -- A slot cannot contain both a member and an external name.
  if exists (
    select 1
    from preselect_desired_assignments
    where member_profile_id is not null
      and display_name is not null
  ) then
    raise exception
      'An assignment cannot contain both a member and an external name.';
  end if;

  -- External names are only valid for opponents.
  if exists (
    select 1
    from preselect_desired_assignments
    where display_name is not null
      and role <> 'opponent'
  ) then
    raise exception
      'External names may only be used for opponent positions.';
  end if;

  -- Player/opponent slots need an identity.
  if exists (
    select 1
    from preselect_desired_assignments
    where role in ('player', 'opponent')
      and member_profile_id is null
      and display_name is null
  ) then
    raise exception 'A player or opponent assignment has no identity.';
  end if;

  -- Marker-state-only rows may have no identity, but must actually
  -- represent a requirement or request.
  if exists (
    select 1
    from preselect_desired_assignments
    where role = 'marker'
      and member_profile_id is null
      and display_name is null
      and marker_required = false
      and request_marker = false
  ) then
    raise exception 'An empty marker-state record was supplied.';
  end if;

  if exists (
    select 1
    from preselect_desired_assignments
    where role <> 'marker'
      and (marker_required or request_marker)
  ) then
    raise exception
      'Marker requirement settings must use position 201.';
  end if;

  if exists (
    select 1
    from preselect_desired_assignments
    where role = 'marker'
      and member_profile_id is not null
      and request_marker = true
  ) then
    raise exception
      'A rink cannot request a marker when a marker is already assigned.';
  end if;

  -- All known people must be active members of the fixture club.
  if exists (
    select 1
    from preselect_desired_assignments d
    where d.member_profile_id is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = d.member_profile_id
          and cm.is_active = true
      )
  ) then
    raise exception
      'One or more selected people are not active members of this club.';
  end if;

  -- ==========================================================
  -- ENSURE THE FIXTURE HAS A TEAM SELECTION
  -- ==========================================================

  select ts.id
  into v_team_selection_id
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  for update;

  if v_team_selection_id is null then
    insert into public.team_selections (
      fixture_id,
      status,
      published_at,
      published_by_member_profile_id
    )
    values (
      p_fixture_id,
      'published',
      now(),
      v_actor_member_profile_id
    )
    returning id into v_team_selection_id;
  end if;

  -- Snapshot only the people who were selected immediately before
  -- this Save. Inactive historical rows remain available separately.
  create temporary table preselect_old_selected
  on commit drop
  as
  select
    tsm.member_profile_id,
    tsm.role::text as role,
    tsm.acceptance::text as acceptance,
    tsm.responded_at,
    tsm.acceptance_by
  from public.team_selection_members tsm
  where tsm.team_selection_id = v_team_selection_id
    and tsm.is_selected = true;

  create temporary table preselect_desired_members
  on commit drop
  as
  select
    d.member_profile_id,
    d.role
  from preselect_desired_assignments d
  where d.member_profile_id is not null;

  -- ==========================================================
  -- BUILD THE MEMBER CHANGE SET BEFORE WRITING
  -- ==========================================================

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', d.member_profile_id,
        'role', d.role
      )
      order by d.role, d.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_added
  from preselect_desired_members d
  left join preselect_old_selected o
    on o.member_profile_id = d.member_profile_id
  where o.member_profile_id is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', o.member_profile_id,
        'role', o.role,
        'acceptance', o.acceptance
      )
      order by o.role, o.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_removed
  from preselect_old_selected o
  left join preselect_desired_members d
    on d.member_profile_id = o.member_profile_id
  where d.member_profile_id is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', d.member_profile_id,
        'role', d.role,
        'acceptance', o.acceptance
      )
      order by d.role, d.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_retained
  from preselect_desired_members d
  join preselect_old_selected o
    on o.member_profile_id = d.member_profile_id
   and o.role = d.role;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_profile_id', d.member_profile_id,
        'old_role', o.role,
        'new_role', d.role
      )
      order by d.member_profile_id
    ),
    '[]'::jsonb
  )
  into v_role_changed
  from preselect_desired_members d
  join preselect_old_selected o
    on o.member_profile_id = d.member_profile_id
   and o.role <> d.role;

  -- ==========================================================
  -- REPLACE THE COMPLETE RINK ASSIGNMENT STATE
  -- ==========================================================

  delete from public.fixture_rink_assignments
  where fixture_id = p_fixture_id;

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    display_name,
    position
  )
  select
    p_fixture_id,
    d.fixture_rink_id,
    d.member_profile_id,
    d.display_name,
    d.position
  from preselect_desired_assignments d
  where d.member_profile_id is not null
     or d.display_name is not null;

  -- ==========================================================
  -- UPDATE TEAM-SELECTION MEMBERS
  --
  -- Removed people remain in history with is_selected=false.
  -- Re-added people retain acceptance when their role is unchanged.
  -- A role change resets acceptance to pending.
  -- ==========================================================

  update public.team_selection_members existing
  set is_selected = false
  where existing.team_selection_id = v_team_selection_id
    and existing.is_selected = true
    and not exists (
      select 1
      from preselect_desired_members desired
      where desired.member_profile_id = existing.member_profile_id
    );

  insert into public.team_selection_members as existing (
    team_selection_id,
    member_profile_id,
    role,
    acceptance,
    responded_at,
    is_selected,
    acceptance_by
  )
  select
    v_team_selection_id,
    desired.member_profile_id,
    desired.role::selection_member_role,

    case
      when desired.member_profile_id =
        v_captain_member_profile_id
        then 'accepted'::acceptance_status
      else 'pending'::acceptance_status
    end,

    null,
    true,
    null

  from preselect_desired_members desired

  on conflict (
    team_selection_id,
    member_profile_id
  )
  do update set
    is_selected = true,

    role = excluded.role,

    acceptance = case
      when excluded.member_profile_id =
        v_captain_member_profile_id
        then 'accepted'::acceptance_status

      when existing.role = excluded.role
        then existing.acceptance

      else 'pending'::acceptance_status
    end,

    responded_at = case
      when existing.role = excluded.role
        then existing.responded_at
      else null
    end,

    acceptance_by = case
      when existing.role = excluded.role
        then existing.acceptance_by
      else null
    end;

  update public.team_selections
  set updated_at = now()
  where id = v_team_selection_id;

  -- ==========================================================
  -- PER-RINK MARKER REQUIREMENTS
  -- ==========================================================

  update public.fixture_rinks fr
  set marker_required = exists (
    select 1
    from preselect_desired_assignments d
    where d.fixture_rink_id = fr.id
      and d.position = 201
      and (
        d.marker_required = true
        or d.request_marker = true
        or d.member_profile_id is not null
      )
  )
  where fr.fixture_id = p_fixture_id;

  create temporary table preselect_marker_events (
    action text not null,
    fixture_rink_id uuid not null,
    member_profile_id uuid
  ) on commit drop;

  -- Assigning a named marker fulfils any open request for that rink.
  with fulfilled as (
    update public.fixture_marker_requests request
    set
      status = 'fulfilled',
      fulfilled_by_member_profile_id = marker.member_profile_id,
      fulfilled_at = now(),
      updated_at = now()
    from preselect_desired_assignments marker
    where request.fixture_rink_id = marker.fixture_rink_id
      and request.status = 'open'
      and marker.position = 201
      and marker.member_profile_id is not null
    returning
      request.fixture_rink_id,
      request.fulfilled_by_member_profile_id
  )
  insert into preselect_marker_events (
    action,
    fixture_rink_id,
    member_profile_id
  )
  select
    'fulfilled',
    fulfilled.fixture_rink_id,
    fulfilled.fulfilled_by_member_profile_id
  from fulfilled;

  -- Cancel open requests no longer present in the authoritative state.
  with cancelled as (
    update public.fixture_marker_requests request
    set
      status = 'cancelled',
      cancelled_by_member_profile_id = v_actor_member_profile_id,
      cancelled_at = now(),
      updated_at = now()
    where request.status = 'open'
      and exists (
        select 1
        from public.fixture_rinks fr
        where fr.id = request.fixture_rink_id
          and fr.fixture_id = p_fixture_id
      )
      and not exists (
        select 1
        from preselect_desired_assignments desired
        where desired.fixture_rink_id = request.fixture_rink_id
          and desired.position = 201
          and desired.request_marker = true
          and desired.member_profile_id is null
      )
    returning request.fixture_rink_id
  )
  insert into preselect_marker_events (
    action,
    fixture_rink_id,
    member_profile_id
  )
  select
    'cancelled',
    cancelled.fixture_rink_id,
    null
  from cancelled;

  -- Open new requests where requested and no request is already open.
  with opened as (
    insert into public.fixture_marker_requests (
      fixture_rink_id,
      status,
      requested_by_member_profile_id
    )
    select
      desired.fixture_rink_id,
      'open',
      v_actor_member_profile_id
    from preselect_desired_assignments desired
    where desired.position = 201
      and desired.request_marker = true
      and desired.member_profile_id is null
      and not exists (
        select 1
        from public.fixture_marker_requests existing
        where existing.fixture_rink_id = desired.fixture_rink_id
          and existing.status = 'open'
      )
    returning fixture_rink_id
  )
  insert into preselect_marker_events (
    action,
    fixture_rink_id,
    member_profile_id
  )
  select
    'opened',
    opened.fixture_rink_id,
    null
  from opened;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'action', event.action,
        'fixture_rink_id', event.fixture_rink_id,
        'fixture_rink_no', fr.fixture_rink_no,
        'member_profile_id', event.member_profile_id
      )
      order by fr.fixture_rink_no, event.action
    ),
    '[]'::jsonb
  )
  into v_marker_events
  from preselect_marker_events event
  join public.fixture_rinks fr
    on fr.id = event.fixture_rink_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'fixture_rink_id', d.fixture_rink_id,
        'fixture_rink_no', fr.fixture_rink_no,
        'position', d.position,
        'display_name', d.display_name
      )
      order by fr.fixture_rink_no, d.position
    ),
    '[]'::jsonb
  )
  into v_external_opponents
  from preselect_desired_assignments d
  join public.fixture_rinks fr
    on fr.id = d.fixture_rink_id
  where d.display_name is not null;

  -- Communications are reconciled inside the same transaction as the save.
  -- If reconciliation fails, the entire save is rolled back.
  select public.reconcile_preselect_communications(p_fixture_id)
  into v_communications;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'team_selection_id', v_team_selection_id,
    'added', v_added,
    'removed', v_removed,
    'retained', v_retained,
    'role_changed', v_role_changed,
    'marker_events', v_marker_events,
    'external_opponents', v_external_opponents,
    'communications', coalesce(v_communications, '{}'::jsonb),
    'assignment_count', (
      select count(*)
      from preselect_desired_assignments
      where member_profile_id is not null
         or display_name is not null
    )
  );
end;
$$;

revoke all
on function public.save_preselect_fixture_state(uuid, jsonb)
from public, anon, service_role;

grant execute
on function public.save_preselect_fixture_state(uuid, jsonb)
to authenticated;
