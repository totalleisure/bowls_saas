CREATE OR REPLACE FUNCTION public.validate_required_team_sheet_email_attachment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_current_version integer;
  v_attachment jsonb;
  v_pdf_bytes bytea;
BEGIN
  IF NEW.event_type NOT IN (
    'team_published_player',
    'team_published_reserve',
    'team_published_captain',
    'team_published_vice',
    'fixture_selected',
    'reserve_promoted'
  ) THEN
    RETURN NEW;
  END IF;

  IF NEW.fixture_id IS NULL OR NEW.team_selection_id IS NULL THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  SELECT ts.composition_version
  INTO v_current_version
  FROM public.team_selections ts
  WHERE ts.id = NEW.team_selection_id
    AND ts.fixture_id = NEW.fixture_id
    AND ts.status = 'published'::public.selection_status;

  IF NOT FOUND
     OR jsonb_typeof(COALESCE(NEW.attachments, '[]'::jsonb)) <> 'array'
     OR jsonb_array_length(COALESCE(NEW.attachments, '[]'::jsonb)) <> 1 THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  v_attachment := NEW.attachments->0;

  IF jsonb_typeof(v_attachment) <> 'object'
     OR v_attachment->>'contentType' <> 'application/pdf'
     OR NULLIF(BTRIM(v_attachment->>'contentBytes'), '') IS NULL
     OR NOT (v_attachment ? 'compositionVersion')
     OR (v_attachment->>'compositionVersion')::integer <> v_current_version THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  BEGIN
    v_pdf_bytes := decode(v_attachment->>'contentBytes', 'base64');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END;

  IF octet_length(v_pdf_bytes) = 0
     OR octet_length(v_pdf_bytes) > 2000000
     OR substring(v_pdf_bytes FROM 1 FOR 4) <> convert_to('%PDF', 'UTF8') THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Required Team Sheet attachment is missing or stale.';
END;
$function$;

REVOKE ALL
ON FUNCTION public.validate_required_team_sheet_email_attachment()
FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_00_validate_required_team_sheet_attachment
ON public.email_queue;

CREATE TRIGGER trg_00_validate_required_team_sheet_attachment
BEFORE INSERT OR UPDATE OF attachments
ON public.email_queue
FOR EACH ROW
EXECUTE FUNCTION public.validate_required_team_sheet_email_attachment();
