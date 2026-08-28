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
  p_dress_code text,
  p_team_id uuid default null,
  p_team_name text default null,
  p_requires_rsvp boolean default false,
  p_venue_id uuid default null,
  p_opponent_venue_id uuid default null,
  p_green_area_id uuid default null,
  p_orientation text default null,
  p_captain_member_profile_id uuid default null,
  p_vice_captain_member_profile_id uuid default null,
  p_notes text default null,
  p_create_team_selection boolean default false,
  p_team_selection_status text default 'draft',
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
  v_dress_code text := lower(coalesce(nullif(trim(p_dress_code), ''), 'open'));
  v_dress_codes public.dress_code[];
begin
  if v_dress_code = 'open' then
    v_dress_codes := '{}'::public.dress_code[];
  elsif v_dress_code in ('whites', 'greys', 'blacks', 'jackets') then
    v_dress_codes := array[v_dress_code::public.dress_code];
  else
    raise exception 'Unsupported dress code: %', p_dress_code;
  end if;

  -- Delegate fixture, rink and Pre-Select creation to the existing deployed
  -- implementation. The UUID in argument 10 selects the original overload.
  v_fixture_id := public.create_fixture_with_setup(
    p_club_id,
    p_start_at,
    p_end_at,
    p_is_home,
    p_section,
    p_rinks_required,
    p_players_per_rink,
    p_format,
    p_competition_type_id,
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

  update public.fixtures
  set dress_code = v_dress_codes
  where id = v_fixture_id;

  return v_fixture_id;
end;
$$;

grant execute on function public.create_fixture_with_setup(
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
) to authenticated, service_role;
