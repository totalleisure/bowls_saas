create or replace function public.create_repeated_fixture_from_source(
  p_source_fixture_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_is_home boolean default null,
  p_opponent_venue_id uuid default null,
  p_preferred_rink_labels text[] default '{}'::text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_source public.fixtures%rowtype;
  v_type public.competition_types%rowtype;
  v_actor uuid := auth.uid();
  v_is_superuser boolean;
  v_is_admin boolean;
  v_uses_rinks boolean;
  v_is_internal boolean;
  v_target_is_home boolean;
  v_home_venue_id uuid;
  v_target_venue_id uuid;
  v_target_opponent_venue_id uuid;
  v_target_green_area_id uuid;
  v_target_orientation text;
  v_format text;
  v_dress_code text;
  v_create_team_selection boolean;
  v_home_rink_labels jsonb := '[]'::jsonb;
  v_marker_structure jsonb := '[]'::jsonb;
  v_fixture_id uuid;
begin
  if v_actor is null then
    raise exception 'You must be signed in.';
  end if;

  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'Invalid fixture start/end time.';
  end if;

  select f.*
  into v_source
  from public.fixtures f
  where f.id = p_source_fixture_id;

  if not found then
    raise exception 'The source fixture was not found.';
  end if;

  select ct.*
  into v_type
  from public.competition_types ct
  where ct.id = v_source.competition_type_id
    and ct.club_id = v_source.club_id
    and ct.is_active = true;

  if not found then
    raise exception 'The source fixture type is not active for this club.';
  end if;

  select exists (
    select 1 from public.app_superusers su where su.user_id = v_actor
  ) into v_is_superuser;

  select exists (
    select 1
    from public.club_memberships cm
    join public.member_profiles mp on mp.id = cm.member_profile_id
    where cm.club_id = v_source.club_id
      and mp.user_id = v_actor
      and cm.is_active = true
      and lower(cm.role::text) = 'admin'
  ) into v_is_admin;

  if not (v_is_superuser or v_is_admin) then
    raise exception 'Only a club Admin or app Superuser can repeat an existing fixture.';
  end if;

  v_uses_rinks := coalesce(v_type.uses_rinks, true);
  v_is_internal := coalesce(v_type.is_internal, false);
  v_create_team_selection :=
    v_uses_rinks
    and coalesce(v_type.team_selection_enabled, false)
    and lower(btrim(coalesce(v_type.selection_mode, ''))) = 'preselect';

  if not v_uses_rinks then
    v_target_is_home := true;
    v_target_venue_id := v_source.venue_id;
    v_target_opponent_venue_id := null;
    v_target_green_area_id := null;
    v_target_orientation := null;
  elsif v_is_internal then
    v_target_is_home := true;
    v_target_venue_id := case
      when v_source.is_home then v_source.venue_id
      else v_source.opponent_venue_id
    end;
    v_target_opponent_venue_id := null;
    v_target_green_area_id := v_source.green_area_id;
    v_target_orientation := v_source.orientation::text;
  else
    if p_is_home is null then
      raise exception 'Please choose whether the repeated fixture is Home or Away.';
    end if;

    if p_opponent_venue_id is null then
      raise exception 'Please choose an opponent venue.';
    end if;

    if not exists (
      select 1 from public.venues v
      where v.id = p_opponent_venue_id and v.club_id = v_source.club_id
    ) then
      raise exception 'The opponent venue does not belong to this club.';
    end if;

    v_home_venue_id := case
      when v_source.is_home then v_source.venue_id
      else v_source.opponent_venue_id
    end;

    if v_home_venue_id is null then
      select v.id into v_home_venue_id
      from public.venues v
      where v.club_id = v_source.club_id and v.is_home_venue = true
      order by v.created_at
      limit 1;
    end if;

    if v_home_venue_id is null then
      raise exception 'The club home venue could not be determined.';
    end if;

    v_target_is_home := p_is_home;
    v_target_venue_id := case when p_is_home then v_home_venue_id else p_opponent_venue_id end;
    v_target_opponent_venue_id := case when p_is_home then p_opponent_venue_id else v_home_venue_id end;
    v_target_green_area_id := case when p_is_home then v_source.green_area_id else null end;
    v_target_orientation := case when p_is_home then v_source.orientation::text else null end;
  end if;

  select coalesce(nullif(btrim(fr.format), ''), nullif(btrim(v_type.default_format), ''))
  into v_format
  from public.fixture_rinks fr
  where fr.fixture_id = v_source.id
  order by fr.fixture_rink_no
  limit 1;

  v_format := coalesce(
    v_format,
    case v_source.players_per_rink
      when 1 then 'singles'
      when 2 then 'pairs'
      when 3 then 'triples'
      else 'rinks'
    end
  );

  v_dress_code := case
    when coalesce(cardinality(v_source.dress_code), 0) = 0 then 'open'
    else v_source.dress_code[1]::text
  end;

  if v_uses_rinks and v_target_is_home and v_target_green_area_id is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object('team_no', available.preference_order, 'home_rink_label', available.rink_label)
      order by available.preference_order
    ), '[]'::jsonb)
    into v_home_rink_labels
    from (
      select preferred.preference_order::integer, availability.rink_label
      from unnest(coalesce(p_preferred_rink_labels, '{}'::text[])) with ordinality
        as preferred(rink_label, preference_order)
      join public.get_green_rink_availability(
        v_target_green_area_id,
        p_start_at,
        p_end_at
      ) availability
        on availability.rink_label = preferred.rink_label
       and availability.is_booked = false
      where preferred.preference_order <= v_source.rinks_required
      order by preferred.preference_order
    ) available;
  end if;

  if v_create_team_selection then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'team_no', fr.fixture_rink_no,
        'position', 201,
        'marker_required', true,
        'request_marker', false
      ) order by fr.fixture_rink_no
    ), '[]'::jsonb)
    into v_marker_structure
    from public.fixture_rinks fr
    where fr.fixture_id = v_source.id
      and fr.marker_required = true;
  end if;

  v_fixture_id := public.create_fixture_with_setup_v2(
    p_club_id => v_source.club_id,
    p_start_at => p_start_at,
    p_end_at => p_end_at,
    p_is_home => v_target_is_home,
    p_section => v_source.section::text,
    p_rinks_required => case when v_uses_rinks then v_source.rinks_required else 0 end,
    p_players_per_rink => case when v_uses_rinks then v_source.players_per_rink else 1 end,
    p_format => case when v_uses_rinks then v_format else 'singles' end,
    p_competition_type_id => v_source.competition_type_id,
    p_dress_code => v_dress_code,
    p_team_id => v_source.team_id,
    p_team_name => v_source.team_name,
    p_requires_rsvp => v_source.requires_rsvp,
    p_venue_id => v_target_venue_id,
    p_opponent_venue_id => v_target_opponent_venue_id,
    p_green_area_id => v_target_green_area_id,
    p_orientation => v_target_orientation,
    p_captain_member_profile_id => null,
    p_vice_captain_member_profile_id => null,
    p_notes => v_source.notes,
    p_create_team_selection => v_create_team_selection,
    p_team_selection_status => 'published',
    p_home_rink_labels => v_home_rink_labels,
    p_rink_assignments => v_marker_structure,
    p_team_selection_members => '[]'::jsonb
  );

  return v_fixture_id;
end;
$function$;

comment on function public.create_repeated_fixture_from_source(uuid, timestamptz, timestamptz, boolean, uuid, text[])
is 'Admin-only safe repeat of an existing fixture. Copies fixture structure while excluding people, responses, communications and workflow history.';

revoke all on function public.create_repeated_fixture_from_source(uuid, timestamptz, timestamptz, boolean, uuid, text[]) from public;
revoke all on function public.create_repeated_fixture_from_source(uuid, timestamptz, timestamptz, boolean, uuid, text[]) from anon;
grant execute on function public.create_repeated_fixture_from_source(uuid, timestamptz, timestamptz, boolean, uuid, text[]) to authenticated;
