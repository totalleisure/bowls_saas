DROP FUNCTION IF EXISTS public.attach_publication_team_sheet(uuid, uuid, jsonb);

CREATE OR REPLACE FUNCTION public.attach_publication_team_sheet(
  p_fixture_id uuid,
  p_team_selection_id uuid,
  p_expected_composition_version integer,
  p_attachment jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_actual_composition_version integer;
  v_notification_rows integer := 0;
  v_email_rows integer := 0;
  v_pdf_bytes bytea;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not signed in.';
  END IF;

  IF NOT (
    COALESCE(public.can_manage_team_selection(p_fixture_id), false)
    OR EXISTS (
      SELECT 1
      FROM public.app_superusers su
      WHERE su.user_id = v_user_id
    )
  ) THEN
    RAISE EXCEPTION 'You do not have permission to attach this team sheet.';
  END IF;

  SELECT ts.composition_version
  INTO v_actual_composition_version
  FROM public.team_selections ts
  WHERE ts.id = p_team_selection_id
    AND ts.fixture_id = p_fixture_id
    AND ts.status = 'published'::public.selection_status
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Published team selection not found for this fixture.';
  END IF;

  IF p_expected_composition_version IS NULL
     OR p_expected_composition_version <> v_actual_composition_version THEN
    RAISE EXCEPTION
      'Team composition changed. Expected version %, current version %.',
      p_expected_composition_version,
      v_actual_composition_version;
  END IF;

  IF jsonb_typeof(p_attachment) <> 'object'
     OR NULLIF(BTRIM(p_attachment->>'name'), '') IS NULL
     OR p_attachment->>'contentType' <> 'application/pdf'
     OR NULLIF(BTRIM(p_attachment->>'contentBytes'), '') IS NULL
     OR NOT (p_attachment ? 'compositionVersion')
     OR (p_attachment->>'compositionVersion')::integer
        <> v_actual_composition_version THEN
    RAISE EXCEPTION
      'Invalid or obsolete team-sheet attachment for composition version %.',
      v_actual_composition_version;
  END IF;

  BEGIN
    v_pdf_bytes := decode(p_attachment->>'contentBytes', 'base64');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid Team Sheet PDF encoding.';
  END;

  IF octet_length(v_pdf_bytes) = 0
     OR substring(v_pdf_bytes FROM 1 FOR 4) <> convert_to('%PDF', 'UTF8') THEN
    RAISE EXCEPTION 'The Team Sheet attachment is not a valid PDF.';
  END IF;

  -- Enforce a conservative decoded-byte ceiling below Graph's transport limit.
  IF octet_length(v_pdf_bytes) > 2000000 THEN
    RAISE EXCEPTION 'The Team Sheet PDF exceeds the 2 MB attachment limit.';
  END IF;

  UPDATE public.notification_queue nq
  SET
    payload = jsonb_set(
      jsonb_set(
        COALESCE(nq.payload, '{}'::jsonb),
        '{attachments}',
        jsonb_build_array(p_attachment),
        true
      ),
      '{team_sheet_composition_version}',
      to_jsonb(v_actual_composition_version),
      true
    ),
    status = 'pending',
    last_error = NULL
  WHERE nq.fixture_id = p_fixture_id
    AND nq.team_selection_id = p_team_selection_id
    AND (
      nq.status = 'pending'
      OR (
        nq.status = 'failed'
        AND nq.last_error = 'Required Team Sheet attachment is missing or stale.'
      )
    )
    AND nq.event_type IN (
      'team_published_player',
      'team_published_reserve',
      'team_published_captain',
      'team_published_vice',
      'fixture_selected',
      'reserve_promoted'
    )
    AND (
      nq.event_type IN ('fixture_selected', 'reserve_promoted')
      OR nq.payload->>'team_sheet_required' = 'true'
    )
    AND (
      nq.payload->'attachments' IS DISTINCT FROM jsonb_build_array(p_attachment)
      OR nq.payload->>'team_sheet_composition_version'
         IS DISTINCT FROM v_actual_composition_version::text
      OR nq.status = 'failed'
    );

  GET DIAGNOSTICS v_notification_rows = ROW_COUNT;

  UPDATE public.email_queue eq
  SET
    attachments = jsonb_build_array(p_attachment),
    payload = jsonb_set(
      COALESCE(eq.payload, '{}'::jsonb),
      '{team_sheet_composition_version}',
      to_jsonb(v_actual_composition_version),
      true
    ),
    status = CASE
      WHEN eq.status = 'failed'
       AND eq.last_error = 'Required Team Sheet attachment is missing or stale.'
        THEN 'pending'
      ELSE eq.status
    END,
    last_error = CASE
      WHEN eq.status = 'failed'
       AND eq.last_error = 'Required Team Sheet attachment is missing or stale.'
        THEN NULL
      ELSE eq.last_error
    END
  WHERE eq.fixture_id = p_fixture_id
    AND eq.team_selection_id = p_team_selection_id
    AND eq.status IN ('pending', 'failed')
    AND eq.sent_at IS NULL
    AND eq.event_type IN (
      'team_published_player',
      'team_published_reserve',
      'team_published_captain',
      'team_published_vice',
      'fixture_selected',
      'reserve_promoted'
    )
    AND (
      eq.attachments IS DISTINCT FROM jsonb_build_array(p_attachment)
      OR eq.payload->>'team_sheet_composition_version'
         IS DISTINCT FROM v_actual_composition_version::text
      OR (
        eq.status = 'failed'
        AND eq.last_error = 'Required Team Sheet attachment is missing or stale.'
      )
    );

  GET DIAGNOSTICS v_email_rows = ROW_COUNT;

  RETURN jsonb_build_object(
    'composition_version', v_actual_composition_version,
    'notification_rows_updated', v_notification_rows,
    'email_rows_updated', v_email_rows
  );
END;
$function$;

REVOKE ALL
ON FUNCTION public.attach_publication_team_sheet(uuid, uuid, integer, jsonb)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.attach_publication_team_sheet(uuid, uuid, integer, jsonb)
TO authenticated;
