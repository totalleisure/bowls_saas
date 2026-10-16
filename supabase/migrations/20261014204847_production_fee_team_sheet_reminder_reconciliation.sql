-- Corrective reconciliation of the reviewed fee, member PDF and reminder changes.
-- Existing applied migrations remain unchanged. Preserve production email configuration.
DO $reconcile$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='fixtures' AND column_name='match_fee_pence') THEN
 EXECUTE $fee_install$
-- Additive: old clients and existing fixtures continue to work unchanged.
alter table public.fixtures add column match_fee_pence integer
  constraint fixtures_match_fee_nonnegative check (match_fee_pence >= 0);
comment on column public.fixtures.match_fee_pence is 'GBP match fee per player, in whole pence. NULL means not set; zero means free.';

-- Keep the established creation function intact. Delegate to it in the SAME
-- transaction so a failed fee write cannot leave a partially created fixture.
do $migration$
declare
  source_oid oid;
  arguments text;
  forwarded text;
  signature text;
begin
  select oid into strict source_oid from pg_proc
  where pronamespace='public'::regnamespace and proname='create_fixture_with_setup_v2';
  arguments := pg_get_function_arguments(source_oid);
  select string_agg(format('%I => %I',name,name), ', ' order by ord)
    into forwarded from pg_proc p,
    unnest(p.proargnames) with ordinality n(name,ord) where p.oid=source_oid;
  execute format($ddl$
    create function public.create_fixture_with_match_fee(%s, p_match_fee_pence integer default null)
    returns uuid language plpgsql security definer set search_path = '' as $body$
    declare fixture_id uuid;
    begin
      if auth.uid() is null then raise exception 'You must be signed in.' using errcode='42501'; end if;
      if p_match_fee_pence < 0 then raise exception 'Match fee cannot be negative.' using errcode='22023'; end if;
      fixture_id := public.create_fixture_with_setup_v2(%s);
      update public.fixtures set match_fee_pence=p_match_fee_pence where id=fixture_id;
      return fixture_id;
    end;
    $body$;
  $ddl$,arguments,forwarded);
  select pg_get_function_identity_arguments(oid) into signature from pg_proc
  where pronamespace='public'::regnamespace and proname='create_fixture_with_match_fee';
  execute 'revoke all on function public.create_fixture_with_match_fee('||signature||') from public, anon';
  execute 'grant execute on function public.create_fixture_with_match_fee('||signature||') to authenticated';
end;
$migration$;

create function public.set_fixture_match_fee(p_fixture_id uuid, p_match_fee_pence integer,
  p_expected_match_fee_pence integer)
returns void language plpgsql security definer set search_path='' as $body$
declare current_fee integer;
begin
  if auth.uid() is null or not (public.can_manage_fixture(p_fixture_id)
    or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception 'You do not have permission to amend this fixture.' using errcode='42501';
  end if;
  if p_match_fee_pence < 0 then raise exception 'Match fee cannot be negative.' using errcode='22023'; end if;
  select match_fee_pence into current_fee from public.fixtures where id=p_fixture_id for update;
  if not found then raise exception 'Fixture not found.'; end if;
  if current_fee is distinct from p_expected_match_fee_pence then
    raise exception 'The fee was changed by someone else. Refresh and try again.' using errcode='40001';
  end if;
  update public.fixtures set match_fee_pence=p_match_fee_pence where id=p_fixture_id;
end;
$body$;
revoke all on function public.set_fixture_match_fee(uuid,integer,integer) from public,anon;
grant execute on function public.set_fixture_match_fee(uuid,integer,integer) to authenticated;

-- Preserve the local deployed repeat function, adding only fee inheritance.
do $migration$
declare definition text;
begin
  select pg_get_functiondef(oid) into strict definition from pg_proc
  where pronamespace='public'::regnamespace and proname='create_repeated_fixture_from_source';
  if (length(definition)-length(replace(definition,'return v_fixture_id;','')))/length('return v_fixture_id;') <> 1 then
    raise exception 'Unexpected repeat function definition; review before applying.';
  end if;
  execute replace(definition,'return v_fixture_id;',
    'update public.fixtures set match_fee_pence=v_source.match_fee_pence where id=v_fixture_id; return v_fixture_id;');
end;
$migration$;
notify pgrst, 'reload schema';


$fee_install$;
 END IF;
END;
$reconcile$;

CREATE OR REPLACE FUNCTION public.get_authorized_team_sheet_data(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_member_profile_id uuid;
  v_fixture public.fixtures%rowtype;
  v_selection public.team_selections%rowtype;
  v_is_superuser boolean := false;
  v_can_manage boolean := false;
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

  -- Historical selections must not grant access after club membership ends.
  IF NOT v_is_superuser AND NOT EXISTS (
    SELECT 1 FROM public.club_memberships cm
    WHERE cm.club_id = v_fixture.club_id
      AND cm.member_profile_id = v_member_profile_id
      AND cm.is_active = true
  ) THEN
    RAISE EXCEPTION 'Not authorised to view this team sheet.';
  END IF;

  v_can_manage :=
    v_is_superuser
    OR COALESCE(public.can_manage_team_selection(p_fixture_id), false);

  -- Active club members can read draft and published team sheets.
  -- Management rights remain independently calculated above.

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
      'notes', v_fixture.notes, 'match_fee_pence', v_fixture.match_fee_pence,
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
$function$
;
CREATE OR REPLACE FUNCTION public.prepare_team_selection_email_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_request_id uuid;
  v_code text;
  v_code_hash text;
  v_team_selection_id uuid;
  v_team_selection_member_id uuid;
  v_club_id uuid;
  v_expires_at timestamptz;
  v_action_type text;
  v_heading text;
  v_accept_label text;
  v_decline_label text;
begin
  if new.event_type not in ('fixture_selected', 'team_published_player', 'reserve_promoted', 'acceptance_reminder')
     or new.member_profile_id is null
     or new.fixture_id is null then
    return new;
  end if;

  select
    ts.id,
    tsm.id,
    f.club_id,
    f.start_at,
    case
      when new.event_type in ('fixture_selected', 'acceptance_reminder')
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ) then 'marker_assignment'
      when tsm.role::text = 'player'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 1 and fr.players_per_rink
       ) then 'team_selection'
      when new.event_type in ('fixture_selected', 'acceptance_reminder')
       and tsm.role::text = 'opponent'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 101 and (100 + fr.players_per_rink)
       ) then 'team_selection'
      else null
    end
  into
    v_team_selection_id,
    v_team_selection_member_id,
    v_club_id,
    v_expires_at,
    v_action_type
  from public.team_selections ts
  join public.team_selection_members tsm
    on tsm.team_selection_id = ts.id
   and tsm.member_profile_id = new.member_profile_id
  join public.fixtures f
    on f.id = ts.fixture_id
  where ts.fixture_id = new.fixture_id
    and (new.team_selection_id is null or ts.id = new.team_selection_id)
    and ts.status = 'published'
    and (new.event_type <> 'acceptance_reminder' or tsm.acceptance::text = 'pending')
    and coalesce(tsm.is_selected, false) = true
    and (
      (new.event_type in ('fixture_selected', 'team_published_player', 'reserve_promoted', 'acceptance_reminder')
       and tsm.role::text = 'player'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 1 and fr.players_per_rink
       ))
      or
      (new.event_type in ('fixture_selected', 'acceptance_reminder')
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ))
      or
      (new.event_type in ('fixture_selected', 'acceptance_reminder')
       and tsm.role::text = 'opponent'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.fixture_rinks fr
           on fr.id = fra.fixture_rink_id
          and fr.fixture_id = f.id
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position between 101 and (100 + fr.players_per_rink)
       ))
    )
    and f.cancelled_at is null
  limit 1;

  if v_team_selection_member_id is null or v_action_type is null then
    return new;
  end if;

  update public.email_action_requests
     set status = 'cancelled',
         updated_at = now()
   where action_type = v_action_type
     and target_record_id = v_team_selection_member_id
     and status in ('pending', 'responded');

  if v_action_type = 'marker_assignment' then
    v_heading := 'Please respond to your marker assignment';
    v_accept_label := 'Accept marker assignment';
    v_decline_label := 'Decline marker assignment';
  else
    v_heading := 'Please respond to your selection';
    v_accept_label := 'Accept selection';
    v_decline_label := 'Decline selection';
  end if;

  v_code := 'BWL-' || upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_code_hash := encode(
    extensions.digest(upper(v_code), 'sha256'),
    'hex'
  );
  insert into public.email_action_requests (
    club_id,
    member_profile_id,
    recipient_email,
    action_type,
    target_record_id,
    fixture_id,
    team_selection_id,
    source_email_queue_id,
    allowed_actions,
    response_code_hash,
    response_protocol_version,
    expires_at
  )
  values (
    v_club_id,
    new.member_profile_id,
    new.recipient_email,
    v_action_type,
    v_team_selection_member_id,
    new.fixture_id,
    v_team_selection_id,
    new.id,
    array['ACCEPT','DECLINE'],
    v_code_hash,
    2,
    v_expires_at
  )
  returning id into v_request_id;

  update public.email_queue
     set payload = coalesce(payload, '{}'::jsonb) ||
       jsonb_build_object(
         'action_block',
         jsonb_build_object(
           'version', 2,
           'request_id', v_request_id,
           'action_type', v_action_type,
           'heading', v_heading,
           'instructions',
             'Select Accept or Decline. Your email application will open a prepared reply; send it without changing the response code.',
           'response_code', v_code,
           'expires_at', v_expires_at,
           'actions', jsonb_build_array(
             jsonb_build_object(
               'command', 'ACCEPT',
               'label', v_accept_label,
               'style', 'positive'
             ),
             jsonb_build_object(
               'command', 'DECLINE',
               'label', v_decline_label,
               'style', 'negative'
             )
           )
         )
       )
   where id = new.id;

  return new;
end;
$function$
;
NOTIFY pgrst, 'reload schema';

