do $$ begin
 if (select regexp_replace(pg_get_functiondef(p.oid),'[[:space:]]','','g') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='arrange_competition_match') is distinct from regexp_replace($original$CREATE OR REPLACE FUNCTION public.arrange_competition_match(p_match_id uuid, p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_rink_labels text[], p_orientation text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 m public.competition_draw_matches; c public.club_competitions; r public.competition_rounds;
 actor uuid; cid uuid; venue uuid; settings jsonb; nr int; nplayers int; ppr int;
 home_entry uuid; away_entry uuid; v_fixture uuid; assignments jsonb; selections jsonb; labels jsonb;
 is_admin boolean; requested int; conditions text;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select competition_id into cid from public.competition_draw_matches where id=p_match_id;
 select * into c from public.club_competitions where id=cid for update;
 if not found then raise exception 'Competition match not found'; end if;
 select * into strict m from public.competition_draw_matches where id=p_match_id for update;
 actor:=public.my_member_profile_id();
 is_admin:=competition_private.can_manage(c.club_id);
 if not is_admin and not exists (
   select 1 from public.competition_entry_members em
   join public.club_memberships cm on cm.member_profile_id=em.member_profile_id and cm.club_id=c.club_id
   where em.competition_id=c.id and em.entry_id in (m.side_a_entry_id,m.side_b_entry_id)
   and em.member_profile_id=actor and cm.is_active and cm.role::text<>'guest'
 ) then raise exception 'Only a player in this match or a Club Admin can arrange it' using errcode='42501'; end if;
 -- Retry returns the existing booking; it can never create a second fixture.
 if m.fixture_id is not null then return m.fixture_id; end if;
 if c.status<>'published' or m.status<>'to_be_arranged' or m.side_a_entry_id is null or m.side_b_entry_id is null
 then raise exception 'A published playable match is required'; end if;
 if c.fixture_type_id is null then raise exception 'Choose the competition Fixture Type first'; end if;
 if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at
    or p_end_at>p_start_at+interval '24 hours' then raise exception 'Choose a future date and a valid start and end time'; end if;
 select g.venue_id into venue from public.green_areas g join public.venues v on v.id=g.venue_id
 where g.id=p_green_area_id and v.club_id=c.club_id and v.is_home_venue;
 if venue is null then raise exception 'Choose a home green belonging to this Club'; end if;
 select * into strict r from public.competition_rounds where id=m.round_id;
 settings:=c.settings||r.rule_overrides;
 nr:=coalesce((settings->>'rinks_required')::int,1);
 nplayers:=(c.settings->>'players_per_entry')::int;
 if nr<1 or nplayers<1 or nplayers%nr<>0 then raise exception 'Competition team and rink settings are inconsistent'; end if;
 ppr:=nplayers/nr;
 if ppr not between 1 and 4 then raise exception 'Competition format requires between one and four players per rink'; end if;
 select count(distinct label) into requested from unnest(p_rink_labels) label where nullif(btrim(label),'') is not null;
 if p_rink_labels is null or cardinality(p_rink_labels)<>nr or requested<>nr then raise exception 'Select exactly % different rinks',nr; end if;
 -- Serialize against ordinary fixture inserts/updates as well as competition bookings.
 -- These locks last only for this short booking transaction, never while the user chooses.
 lock table public.fixtures in share row exclusive mode;
 lock table public.fixture_rinks in share row exclusive mode;
 if (select count(*) from public.get_green_rink_availability(p_green_area_id,p_start_at,p_end_at) a
     where a.rink_label=any(p_rink_labels) and not a.is_booked and a.free_capacity_rinks>=nr)<>nr
 then raise exception 'The selected rinks are no longer available. Refresh and choose another rink or time.'; end if;
 home_entry:=m.side_a_entry_id; away_entry:=m.side_b_entry_id;
 -- The ordinary member booking workflow requires its organiser on the player side.
 if exists(select 1 from public.competition_entry_members where entry_id=away_entry and member_profile_id=actor)
 then home_entry:=m.side_b_entry_id; away_entry:=m.side_a_entry_id; end if;
 if (select count(*) from public.competition_entry_members where entry_id=home_entry)<>nplayers
 or (select count(*) from public.competition_entry_members where entry_id=away_entry)<>nplayers
 then raise exception 'Both entries must contain the competition team size'; end if;
 with members as (
  select em.member_profile_id, em.entry_id,
   row_number() over(partition by em.entry_id order by
    nullif(strpos(lower(e.name),lower(btrim(mp.first_name||' '||mp.last_name))),0) nulls last,
    mp.last_name,mp.first_name,em.member_profile_id)::int as pos
  from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
  join public.competition_entries e on e.id=em.entry_id
  where em.competition_id=c.id and em.entry_id in (home_entry,away_entry)
 ) select jsonb_agg(jsonb_build_object('team_no',((pos-1)/ppr)+1,
    'position',((pos-1)%ppr)+1+case when entry_id=home_entry then 0 else 100 end,
    'member_profile_id',member_profile_id)),
   jsonb_agg(jsonb_build_object('member_profile_id',member_profile_id,
    'role',case when entry_id=home_entry then 'player' else 'opponent' end,
    'is_selected',true,'acceptance',case when member_profile_id=actor then 'accepted' else 'pending' end))
 into assignments,selections from members;
 select jsonb_agg(jsonb_build_object('team_no',i,'home_rink_label',label)) into labels
 from unnest(p_rink_labels) with ordinality t(label,i);
 conditions:=concat_ws(E'\n',c.name||' - '||r.name||' '||m.match_number,
    'Play by: '||coalesce(r.play_by::text,'Not set'),
    'Scoring: '||nullif(settings->>'scoring',''),
    'Woods per player: '||nullif(settings->>'woods_per_player',''),
    nullif(settings->>'rules',''));
 v_fixture:=public.create_fixture_with_match_fee(
   p_club_id=>c.club_id,p_start_at=>p_start_at,p_end_at=>p_end_at,p_is_home=>true,
   p_section=>coalesce(settings->>'section','open'),p_rinks_required=>nr,p_players_per_rink=>ppr,
   p_format=>settings->>'playing_format',p_competition_type_id=>c.fixture_type_id,
   p_dress_code=>coalesce(nullif(settings->>'dress',''),'open'),p_team_id=>null,p_team_name=>c.name,
   p_requires_rsvp=>false,p_venue_id=>venue,p_opponent_venue_id=>null,p_green_area_id=>p_green_area_id,
   p_orientation=>p_orientation,p_captain_member_profile_id=>actor,p_vice_captain_member_profile_id=>null,
   p_notes=>conditions,p_create_team_selection=>true,p_team_selection_status=>'published',
   p_home_rink_labels=>labels,p_rink_assignments=>assignments,p_team_selection_members=>selections,
   p_match_fee_pence=>null);
 update public.competition_draw_matches set fixture_id=v_fixture where id=m.id;
 perform competition_private.queue_booking_communications(v_fixture,'booked','booked');
 return v_fixture;
end $function$
$original$,'[[:space:]]','','g') then raise exception 'Unexpected arrange_competition_match definition'; end if;
 if (select regexp_replace(pg_get_functiondef(p.oid),'[[:space:]]','','g') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_fixture_with_setup_v2') is distinct from regexp_replace($original$CREATE OR REPLACE FUNCTION public.create_fixture_with_setup_v2(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_dress_code text, p_team_id uuid DEFAULT NULL::uuid, p_team_name text DEFAULT NULL::text, p_requires_rsvp boolean DEFAULT true, p_venue_id uuid DEFAULT NULL::uuid, p_opponent_venue_id uuid DEFAULT NULL::uuid, p_green_area_id uuid DEFAULT NULL::uuid, p_orientation text DEFAULT NULL::text, p_captain_member_profile_id uuid DEFAULT NULL::uuid, p_vice_captain_member_profile_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_create_team_selection boolean DEFAULT false, p_team_selection_status text DEFAULT 'published'::text, p_home_rink_labels jsonb DEFAULT '[]'::jsonb, p_rink_assignments jsonb DEFAULT '[]'::jsonb, p_team_selection_members jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        and lower(cm.role::text) <> 'guest'
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
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception
      'The captain/organiser and vice/deputy must be active non-Guest club members.';
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
         v_position between 1 and p_players_per_rink
         or v_position between 101 and (100 + p_players_per_rink)
       ) then
      raise exception
        'External names can only be used in player or opponent positions.';
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
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception
      'One or more rink assignments are not active non-Guest members of this club.';
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
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception
      'One or more selected people are not active non-Guest members of this club.';
  end if;

  if v_is_ordinary_member_booking then
    -- A member may book an external player; the captain must still be the booking member. Prevent nomination
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
    ) and not exists (
      select 1 from jsonb_array_elements(coalesce(p_rink_assignments,'[]'::jsonb)) as a(item)
      where nullif(btrim(a.item->>'display_name'),'') is not null
        and nullif(a.item->>'member_profile_id','') is null
        and (a.item->>'position')::integer between 1 and p_players_per_rink
    ) then
      raise exception
        'The booking member must occupy a player position or book an external player.';
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
$function$
$original$,'[[:space:]]','','g') then raise exception 'Unexpected create_fixture_with_setup_v2 definition'; end if;
end $$;
-- Only the authenticated, validated competition arranger can establish this scope.
create table competition_private.booking_scope (
 backend_pid integer not null, transaction_id bigint not null,
 actor_id uuid not null, club_id uuid not null, fixture_type_id uuid not null,
 assignments jsonb not null, primary key(backend_pid,transaction_id)
);
alter table competition_private.booking_scope enable row level security;
revoke all on competition_private.booking_scope from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.arrange_competition_match(p_match_id uuid, p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_rink_labels text[], p_orientation text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 m public.competition_draw_matches; c public.club_competitions; r public.competition_rounds;
 actor uuid; cid uuid; venue uuid; settings jsonb; nr int; nplayers int; ppr int;
 home_entry uuid; away_entry uuid; v_fixture uuid; assignments jsonb; selections jsonb; labels jsonb;
 is_admin boolean; requested int; conditions text;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
 select competition_id into cid from public.competition_draw_matches where id=p_match_id;
 select * into c from public.club_competitions where id=cid for update;
 if not found then raise exception 'Competition match not found'; end if;
 select * into strict m from public.competition_draw_matches where id=p_match_id for update;
 actor:=public.my_member_profile_id();
 is_admin:=competition_private.can_manage(c.club_id);
 if not is_admin and not exists (
   select 1 from public.competition_entry_members em
   join public.club_memberships cm on cm.member_profile_id=em.member_profile_id and cm.club_id=c.club_id
   where em.competition_id=c.id and em.entry_id in (m.side_a_entry_id,m.side_b_entry_id)
   and em.member_profile_id=actor and cm.is_active and cm.role::text<>'guest'
 ) then raise exception 'Only a player in this match or a Club Admin can arrange it' using errcode='42501'; end if;
 -- Retry returns the existing booking; it can never create a second fixture.
 if m.fixture_id is not null then return m.fixture_id; end if;
 if c.status<>'published' or m.status<>'to_be_arranged' or m.side_a_entry_id is null or m.side_b_entry_id is null
 then raise exception 'A published playable match is required'; end if;
 if c.fixture_type_id is null then raise exception 'Choose the competition Fixture Type first'; end if;
 if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at
    or p_end_at>p_start_at+interval '24 hours' then raise exception 'Choose a future date and a valid start and end time'; end if;
 select g.venue_id into venue from public.green_areas g join public.venues v on v.id=g.venue_id
 where g.id=p_green_area_id and v.club_id=c.club_id and v.is_home_venue;
 if venue is null then raise exception 'Choose a home green belonging to this Club'; end if;
 select * into strict r from public.competition_rounds where id=m.round_id;
 settings:=c.settings||r.rule_overrides;
 nr:=coalesce((settings->>'rinks_required')::int,1);
 nplayers:=(c.settings->>'players_per_entry')::int;
 if nr<1 or nplayers<1 or nplayers%nr<>0 then raise exception 'Competition team and rink settings are inconsistent'; end if;
 ppr:=nplayers/nr;
 if ppr not between 1 and 4 then raise exception 'Competition format requires between one and four players per rink'; end if;
 select count(distinct label) into requested from unnest(p_rink_labels) label where nullif(btrim(label),'') is not null;
 if p_rink_labels is null or cardinality(p_rink_labels)<>nr or requested<>nr then raise exception 'Select exactly % different rinks',nr; end if;
 -- Serialize against ordinary fixture inserts/updates as well as competition bookings.
 -- These locks last only for this short booking transaction, never while the user chooses.
 lock table public.fixtures in share row exclusive mode;
 lock table public.fixture_rinks in share row exclusive mode;
 if (select count(*) from public.get_green_rink_availability(p_green_area_id,p_start_at,p_end_at) a
     where a.rink_label=any(p_rink_labels) and not a.is_booked and a.free_capacity_rinks>=nr)<>nr
 then raise exception 'The selected rinks are no longer available. Refresh and choose another rink or time.'; end if;
 home_entry:=m.side_a_entry_id; away_entry:=m.side_b_entry_id;
 -- Draw order is stable: challenger first, opponent second.
 if (select count(*) from public.competition_entry_members where entry_id=home_entry)<>nplayers
 or (select count(*) from public.competition_entry_members where entry_id=away_entry)<>nplayers
 then raise exception 'Both entries must contain the competition team size'; end if;
 with members as (
  select em.member_profile_id, em.entry_id,
   row_number() over(partition by em.entry_id order by
    nullif(strpos(lower(e.name),lower(btrim(mp.first_name||' '||mp.last_name))),0) nulls last,
    mp.last_name,mp.first_name,em.member_profile_id)::int as pos
  from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
  join public.competition_entries e on e.id=em.entry_id
  where em.competition_id=c.id and em.entry_id in (home_entry,away_entry)
 ) select jsonb_agg(jsonb_build_object('team_no',((pos-1)/ppr)+1,
    'position',((pos-1)%ppr)+1+case when entry_id=home_entry then 0 else 100 end,
    'member_profile_id',member_profile_id)),
   jsonb_agg(jsonb_build_object('member_profile_id',member_profile_id,
    'role',case when entry_id=home_entry then 'player' else 'opponent' end,
    'is_selected',true,'acceptance',case when member_profile_id=actor then 'accepted' else 'pending' end))
 into assignments,selections from members;
 select jsonb_agg(jsonb_build_object('team_no',i,'home_rink_label',label)) into labels
 from unnest(p_rink_labels) with ordinality t(label,i);
 conditions:=concat_ws(E'\n',c.name||' - '||r.name||' '||m.match_number,
    'Play by: '||coalesce(r.play_by::text,'Not set'),
    'Scoring: '||nullif(settings->>'scoring',''),
    'Woods per player: '||nullif(settings->>'woods_per_player',''),
    nullif(settings->>'rules',''));
 insert into competition_private.booking_scope(backend_pid,transaction_id,actor_id,club_id,fixture_type_id,assignments)
 values(pg_backend_pid(),txid_current(),auth.uid(),c.club_id,c.fixture_type_id,assignments);
 v_fixture:=public.create_fixture_with_match_fee(
   p_club_id=>c.club_id,p_start_at=>p_start_at,p_end_at=>p_end_at,p_is_home=>true,
   p_section=>coalesce(settings->>'section','open'),p_rinks_required=>nr,p_players_per_rink=>ppr,
   p_format=>settings->>'playing_format',p_competition_type_id=>c.fixture_type_id,
   p_dress_code=>coalesce(nullif(settings->>'dress',''),'open'),p_team_id=>null,p_team_name=>c.name,
   p_requires_rsvp=>false,p_venue_id=>venue,p_opponent_venue_id=>null,p_green_area_id=>p_green_area_id,
   p_orientation=>p_orientation,p_captain_member_profile_id=>actor,p_vice_captain_member_profile_id=>null,
   p_notes=>conditions,p_create_team_selection=>true,p_team_selection_status=>'published',
   p_home_rink_labels=>labels,p_rink_assignments=>assignments,p_team_selection_members=>selections,
   p_match_fee_pence=>null);
 delete from competition_private.booking_scope where backend_pid=pg_backend_pid() and transaction_id=txid_current();
 update public.competition_draw_matches set fixture_id=v_fixture where id=m.id;
 perform competition_private.queue_booking_communications(v_fixture,'booked','booked');
 return v_fixture;
end $function$
;
CREATE OR REPLACE FUNCTION public.create_fixture_with_setup_v2(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_dress_code text, p_team_id uuid DEFAULT NULL::uuid, p_team_name text DEFAULT NULL::text, p_requires_rsvp boolean DEFAULT true, p_venue_id uuid DEFAULT NULL::uuid, p_opponent_venue_id uuid DEFAULT NULL::uuid, p_green_area_id uuid DEFAULT NULL::uuid, p_orientation text DEFAULT NULL::text, p_captain_member_profile_id uuid DEFAULT NULL::uuid, p_vice_captain_member_profile_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_create_team_selection boolean DEFAULT false, p_team_selection_status text DEFAULT 'published'::text, p_home_rink_labels jsonb DEFAULT '[]'::jsonb, p_rink_assignments jsonb DEFAULT '[]'::jsonb, p_team_selection_members jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        and lower(cm.role::text) <> 'guest'
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
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception
      'The captain/organiser and vice/deputy must be active non-Guest club members.';
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
         v_position between 1 and p_players_per_rink
         or v_position between 101 and (100 + p_players_per_rink)
       ) then
      raise exception
        'External names can only be used in player or opponent positions.';
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
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception
      'One or more rink assignments are not active non-Guest members of this club.';
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
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception
      'One or more selected people are not active non-Guest members of this club.';
  end if;

  if v_is_ordinary_member_booking then
    -- A member may book an external player; the captain must still be the booking member. Prevent nomination
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
    ) and not exists (
      select 1 from jsonb_array_elements(coalesce(p_rink_assignments,'[]'::jsonb)) as a(item)
      where nullif(btrim(a.item->>'display_name'),'') is not null
        and nullif(a.item->>'member_profile_id','') is null
        and (a.item->>'position')::integer between 1 and p_players_per_rink
    ) and not exists (
      select 1 from competition_private.booking_scope s
      where s.backend_pid=pg_backend_pid() and s.transaction_id=txid_current()
        and s.actor_id=auth.uid() and s.club_id=p_club_id
        and s.fixture_type_id=p_competition_type_id and s.assignments=p_rink_assignments
    ) then
      raise exception
        'The booking member must occupy a player position or book an external player.';
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
$function$
;
