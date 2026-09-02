CREATE OR REPLACE FUNCTION public.get_authorized_team_sheet_data(
  p_fixture_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_member_profile_id uuid;
  v_fixture public.fixtures%rowtype;
  v_selection public.team_selections%rowtype;
  v_is_superuser boolean := false;
  v_can_manage boolean := false;
  v_is_positioned_player boolean := false;
  v_is_selected_reserve boolean := false;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authorised to view this team sheet.';
  END IF;

  v_member_profile_id := public.my_member_profile_id();

  IF v_member_profile_id IS NULL THEN
    RAISE EXCEPTION 'Not authorised to view this team sheet.';
  END IF;

  SELECT f.*
  INTO v_fixture
  FROM public.fixtures f
  WHERE f.id = p_fixture_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not authorised to view this team sheet.';
  END IF;

  SELECT ts.*
  INTO v_selection
  FROM public.team_selections ts
  WHERE ts.fixture_id = p_fixture_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Team sheet is not available.';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.app_superusers su
    WHERE su.user_id = v_user_id
  )
  INTO v_is_superuser;

  v_can_manage :=
    v_is_superuser
    OR COALESCE(public.can_manage_team_selection(p_fixture_id), false);

  IF v_selection.status = 'published'::public.selection_status THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.fixture_rink_assignments fra
      JOIN public.fixture_rinks fr
        ON fr.id = fra.fixture_rink_id
       AND fr.fixture_id = p_fixture_id
      JOIN public.team_selection_members tsm
        ON tsm.team_selection_id = v_selection.id
       AND tsm.member_profile_id = fra.member_profile_id
       AND tsm.is_selected = true
       AND tsm.role = 'player'::public.selection_member_role
      WHERE fra.fixture_id = p_fixture_id
        AND fra.member_profile_id = v_member_profile_id
        AND fra.position BETWEEN 1 AND fr.players_per_rink
    )
    INTO v_is_positioned_player;

    SELECT EXISTS (
      SELECT 1
      FROM public.team_selection_members tsm
      WHERE tsm.team_selection_id = v_selection.id
        AND tsm.member_profile_id = v_member_profile_id
        AND tsm.is_selected = true
        AND tsm.role = 'reserve'::public.selection_member_role
    )
    INTO v_is_selected_reserve;

    IF NOT (
      v_can_manage
      OR v_is_positioned_player
      OR v_is_selected_reserve
    ) THEN
      RAISE EXCEPTION 'Not authorised to view this team sheet.';
    END IF;
  ELSIF NOT v_can_manage THEN
    RAISE EXCEPTION 'Not authorised to view this team sheet.';
  END IF;

  RETURN jsonb_build_object(
    'access',
    jsonb_build_object(
      'can_manage', v_can_manage,
      'selection_status', v_selection.status::text
    ),
    'fixture',
    jsonb_build_object(
      'id', v_fixture.id,
      'club_id', v_fixture.club_id,
      'start_at', v_fixture.start_at,
      'is_home', v_fixture.is_home,
      'section', v_fixture.section,
      'dress_code', to_jsonb(v_fixture.dress_code),
      'notes', v_fixture.notes,
      'captain_member_profile_id', v_fixture.captain_member_profile_id,
      'vice_captain_member_profile_id', v_fixture.vice_captain_member_profile_id,
      'club_name', (
        SELECT c.name
        FROM public.clubs c
        WHERE c.id = v_fixture.club_id
      ),
      'venue_name', (
        SELECT v.name
        FROM public.venues v
        WHERE v.id = v_fixture.venue_id
      ),
      'opponent_name', (
        CASE
          WHEN v_fixture.is_home THEN (
            SELECT ov.name
            FROM public.venues ov
            WHERE ov.id = v_fixture.opponent_venue_id
          )
          ELSE (
            SELECT v.name
            FROM public.venues v
            WHERE v.id = v_fixture.venue_id
          )
        END
      ),
      'captain', (
        SELECT jsonb_build_object(
          'display_name', mp.display_name,
          'first_name', mp.first_name,
          'last_name', mp.last_name,
          'email_address', mp.email_address,
          'phone', mp.phone
        )
        FROM public.member_profiles mp
        WHERE mp.id = v_fixture.captain_member_profile_id
      ),
      'vice_captain', (
        SELECT jsonb_build_object(
          'display_name', mp.display_name,
          'first_name', mp.first_name,
          'last_name', mp.last_name,
          'email_address', mp.email_address,
          'phone', mp.phone
        )
        FROM public.member_profiles mp
        WHERE mp.id = v_fixture.vice_captain_member_profile_id
      ),
      'competition_type', (
        SELECT jsonb_build_object(
          'name', ct.name,
          'is_internal', ct.is_internal,
          'selection_mode', ct.selection_mode,
          'background_hex', fcs.background_hex,
          'foreground_hex', fcs.foreground_hex
        )
        FROM public.competition_types ct
        LEFT JOIN public.fixture_colour_schemes fcs
          ON fcs.id = ct.colour_scheme_id
        WHERE ct.id = v_fixture.competition_type_id
      )
    ),
    'team_selection',
    jsonb_build_object(
      'id', v_selection.id,
      'status', v_selection.status::text,
      'composition_version', v_selection.composition_version
    ),
    'rinks',
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', fr.id,
          'fixture_rink_no', fr.fixture_rink_no,
          'home_rink_label', fr.home_rink_label,
          'players_per_rink', fr.players_per_rink,
          'format', fr.format
        )
        ORDER BY fr.fixture_rink_no
      )
      FROM public.fixture_rinks fr
      WHERE fr.fixture_id = p_fixture_id
    ), '[]'::jsonb),
    'assignments',
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', fra.id,
          'fixture_rink_id', fra.fixture_rink_id,
          'member_profile_id', fra.member_profile_id,
          'position', fra.position,
          'display_name', COALESCE(NULLIF(BTRIM(fra.display_name), ''), mp.display_name)
        )
        ORDER BY fr.fixture_rink_no, fra.position
      )
      FROM public.fixture_rink_assignments fra
      JOIN public.fixture_rinks fr
        ON fr.id = fra.fixture_rink_id
      LEFT JOIN public.member_profiles mp
        ON mp.id = fra.member_profile_id
      WHERE fra.fixture_id = p_fixture_id
    ), '[]'::jsonb),
    'selection_members',
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'member_profile_id', tsm.member_profile_id,
          'role', tsm.role::text,
          'is_selected', tsm.is_selected,
          'display_name', mp.display_name
        )
        ORDER BY tsm.created_at, tsm.id
      )
      FROM public.team_selection_members tsm
      LEFT JOIN public.member_profiles mp
        ON mp.id = tsm.member_profile_id
      WHERE tsm.team_selection_id = v_selection.id
    ), '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL
ON FUNCTION public.get_authorized_team_sheet_data(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.get_authorized_team_sheet_data(uuid)
TO authenticated;
