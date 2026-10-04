-- RELEASE 1.5.5 (26): REVIEW CANDIDATE. NOT YET REHEARSED OR APPLIED.

-- Requires approved preflight, backup verification and a production-shaped rehearsal.

BEGIN;

SET LOCAL lock_timeout = '5s';

SET LOCAL statement_timeout = '90s';

SET LOCAL check_function_bodies = off;

SET LOCAL search_path = public, extensions, pg_catalog;

DO $$ BEGIN IF coalesce(current_setting('bowls.release_155_approved',true),'') <> 'yes' THEN RAISE EXCEPTION 'Release 1.5.5 deployment gate: complete rehearsal and recovery checks before setting bowls.release_155_approved=yes'; END IF; END $$;

DO $preflight$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='invitation_private' AND f.proname='check_initial_password' AND pg_get_function_identity_arguments(f.oid)='p_user uuid, p_club uuid, p_password text' AND md5(pg_get_functiondef(f.oid))='cefc30089976eae0d6a15752d78f49d1' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'invitation_private.check_initial_password(p_user uuid, p_club uuid, p_password text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='accept_invite' AND pg_get_function_identity_arguments(f.oid)='p_token uuid' AND md5(pg_get_functiondef(f.oid))='76489e2917021d4f8eeb98b114ab4513' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.accept_invite(p_token uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='add_member_to_club_by_email' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid, p_email text, p_role club_role' AND md5(pg_get_functiondef(f.oid))='185ce3b427c55917bec305e3964be6e7' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.add_member_to_club_by_email(p_club_id uuid, p_email text, p_role club_role)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='add_team_members_to_pool' AND pg_get_function_identity_arguments(f.oid)='p_team_id uuid, p_member_profile_ids uuid[]' AND md5(pg_get_functiondef(f.oid))='b1591efec65ebe455c426d24728f2c39' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.add_team_members_to_pool(p_team_id uuid, p_member_profile_ids uuid[])'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='admin_add_member_by_email' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid, p_email text, p_role club_role, p_is_active boolean' AND md5(pg_get_functiondef(f.oid))='b669ebb79911558ec30dd1b946dd2c22' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.admin_add_member_by_email(p_club_id uuid, p_email text, p_role club_role, p_is_active boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='admin_find_orphaned_records' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='91b244551a24565923be7478162625a2' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.admin_find_orphaned_records()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='admin_force_delete_fixture' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_confirm text' AND md5(pg_get_functiondef(f.oid))='fe009ac34478574a1386163c05e84bd3' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.admin_force_delete_fixture(p_fixture_id uuid, p_confirm text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='admin_update_membership' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean' AND md5(pg_get_functiondef(f.oid))='8e2abf112e2c64d03a2b5239a8e8b2fc' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.admin_update_membership(p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='apply_email_action_response' AND pg_get_function_identity_arguments(f.oid)='p_response_code text, p_command text, p_sender_email text, p_graph_message_id text, p_received_at timestamp with time zone' AND md5(pg_get_functiondef(f.oid))='a083471be1d3cbadb46a249356aaefe0' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.apply_email_action_response(p_response_code text, p_command text, p_sender_email text, p_graph_message_id text, p_received_at timestamp with time zone)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='apply_email_action_response' AND pg_get_function_identity_arguments(f.oid)='p_response_code text, p_command text, p_sender_email text, p_response_token text, p_graph_message_id text, p_received_at timestamp with time zone' AND md5(pg_get_functiondef(f.oid))='3f732c16aa1cfb064bd4bf6a11afe511' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.apply_email_action_response(p_response_code text, p_command text, p_sender_email text, p_response_token text, p_graph_message_id text, p_received_at timestamp with time zone)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='attach_publication_team_sheet' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_team_selection_id uuid, p_expected_composition_version integer, p_attachment jsonb' AND md5(pg_get_functiondef(f.oid))='78b94d1fd37309aad6852cd5680afe93' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.attach_publication_team_sheet(p_fixture_id uuid, p_team_selection_id uuid, p_expected_composition_version integer, p_attachment jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='can_manage_fixture' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='515c1496db4549d9aabfb2ce667bd5fd' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.can_manage_fixture(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='can_manage_team_selection' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='6a84f44971385d6f503c685780c98d6e' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.can_manage_team_selection(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='can_read_member_profile' AND pg_get_function_identity_arguments(f.oid)='p_target_profile_id uuid' AND md5(pg_get_functiondef(f.oid))='4ffb37a481c998ab7da65f059fd54bca' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.can_read_member_profile(p_target_profile_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='cancel_and_reschedule_fixture_safe' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone, p_reason text' AND md5(pg_get_functiondef(f.oid))='955c73dc86e4fbf3ae76443e21932cee' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.cancel_and_reschedule_fixture_safe(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone, p_reason text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='cancel_fixture_safe' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_reason text' AND md5(pg_get_functiondef(f.oid))='e4ff512a96727070f45bca2670ea84e0' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.cancel_fixture_safe(p_fixture_id uuid, p_reason text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='check_green_area_rink_capacity' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='718f7dffeb8174f7668ca7d526fce11f' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.check_green_area_rink_capacity()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='claim_member_invitation' AND pg_get_function_identity_arguments(f.oid)='p_id uuid, p_club uuid, p_caller uuid' AND md5(pg_get_functiondef(f.oid))='59c259256ff424f955028d6cef779765' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.claim_member_invitation(p_id uuid, p_club uuid, p_caller uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='communications_fixture_manager_status' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='21c2c06ae8435879cece9025d83d8457' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.communications_fixture_manager_status(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='communications_health_check' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='5f051e715ee779df910134e9be8d8b01' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.communications_health_check(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='communications_health_check_v2' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='67d5b4fdf1e6bbe12aecab85c5a46b52' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.communications_health_check_v2(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='communications_health_detail' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='180cd739cb06ab2e908b973377517556' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.communications_health_detail(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='communications_health_detail_v2' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='a4d4c29d2344774fbb624fa13d1499e2' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.communications_health_detail_v2(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='communications_require_superuser' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='1a4c77b41f947186ef19205e7c68f7eb' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.communications_require_superuser()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='confirm_team_changes' AND pg_get_function_identity_arguments(f.oid)='p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb' AND md5(pg_get_functiondef(f.oid))='254ff8996585fde1aedd70f2ff4c226e' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.confirm_team_changes(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='create_fixture_with_setup' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb' AND md5(pg_get_functiondef(f.oid))='3068c9c5fa1eea2defe09d743e82024d' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.create_fixture_with_setup(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='create_fixture_with_setup_v2' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_dress_code text, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb' AND md5(pg_get_functiondef(f.oid))='fecf3c1fb5235a1d2d586213ec4baf0b' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.create_fixture_with_setup_v2(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_dress_code text, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='create_green_rink_maintenance_safe' AND pg_get_function_identity_arguments(f.oid)='p_green_area_id uuid, p_rink_number integer, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_reason text, p_notes text' AND md5(pg_get_functiondef(f.oid))='6ccb7b051c3e3a7be69d6c3b7e45d50b' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.create_green_rink_maintenance_safe(p_green_area_id uuid, p_rink_number integer, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_reason text, p_notes text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='debug_member_identity_links' AND pg_get_function_identity_arguments(f.oid)='p_email text, p_club_id uuid' AND md5(pg_get_functiondef(f.oid))='21557f32418ad025b27b9b3fca1f961c' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.debug_member_identity_links(p_email text, p_club_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='debug_my_profile' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='8065d5fd8a51efb5e9aa9ee82e75a7b2' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.debug_my_profile()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='delete_fixture' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='4245202d39bb07e3c04f9d9b85f12e05' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.delete_fixture(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='delete_marker_volunteer_from_view' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='f891a0bd8f4a4b6f7a28d764c94c7c63' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.delete_marker_volunteer_from_view()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='enforce_non_guest_fixture_notification_actor' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='08a8b333f60a70aff9a6e3f9ddc45b25' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.enforce_non_guest_fixture_notification_actor()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='enforce_operational_mailing_list_member_eligibility' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='891e90c3c0f73b0fa05ddce7310cbfe3' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.enforce_operational_mailing_list_member_eligibility()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='get_authorized_team_sheet_data' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='fa3ebccb35c8ea99abb31bb7b1c85d4a' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.get_authorized_team_sheet_data(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='get_club_member_picker_list' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid, p_section text, p_team_id uuid, p_fixture_id uuid, p_rsvp_statuses text[], p_search text, p_use_fixture_section boolean' AND md5(pg_get_functiondef(f.oid))='e8e9f03717a432e04ad778f63c7d10fb' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.get_club_member_picker_list(p_club_id uuid, p_section text, p_team_id uuid, p_fixture_id uuid, p_rsvp_statuses text[], p_search text, p_use_fixture_section boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='get_email_queue_cron_status' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='0d7d2fd346c87fe408edfe5737d98d23' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.get_email_queue_cron_status()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='get_green_maintenance_impacts' AND pg_get_function_identity_arguments(f.oid)='p_green_area_id uuid, p_rink_labels text[], p_start_at timestamp with time zone, p_end_at timestamp with time zone' AND md5(pg_get_functiondef(f.oid))='a16517deb27f5420e82b568f42815a19' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.get_green_maintenance_impacts(p_green_area_id uuid, p_rink_labels text[], p_start_at timestamp with time zone, p_end_at timestamp with time zone)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='get_green_rink_availability' AND pg_get_function_identity_arguments(f.oid)='p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='1c7e74f7c7b559eb5fc3ab35fe27e770' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.get_green_rink_availability(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='get_notification_queue_cron_status' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='38bf253e729df51677ed7b67960a860e' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.get_notification_queue_cron_status()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='get_queue_admin_stats' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='3790213b18ef41e6c6767e7ba1901011' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.get_queue_admin_stats()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='green_area_must_be_home_venue' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='84f4ece76bd30bdc05d680639d60a752' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.green_area_must_be_home_venue()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='handle_new_user' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='0f692a1cdb93c9893f7c5cf3b580f4e7' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.handle_new_user()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='is_app_superuser' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='048d52cc3ae9278b0347ae403954d23a' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.is_app_superuser()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='is_club_admin' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid' AND md5(pg_get_functiondef(f.oid))='dd76124e58fe0803c374669aa30fb4e8' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.is_club_admin(p_club_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='is_fixture_captain' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='2915139180a84ad752532e147cecd1d2' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.is_fixture_captain(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='issue_email_action_response_token' AND pg_get_function_identity_arguments(f.oid)='p_request_id uuid, p_email_queue_id uuid, p_response_token_hash text' AND md5(pg_get_functiondef(f.oid))='2760727da31c7d287070685d04e486a0' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.issue_email_action_response_token(p_request_id uuid, p_email_queue_id uuid, p_response_token_hash text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='my_active_club_ids' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='455a3c47072002c89d62a5e00e492c1b' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.my_active_club_ids()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='my_member_profile_id' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='e942d62cae5b1c3b20343d87fbdf7a4a' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.my_member_profile_id()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='my_member_profile_id_norls' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='0afee4f1c9281ec425231dbe87022823' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.my_member_profile_id_norls()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='my_self_subscribable_mailing_lists' AND pg_get_function_identity_arguments(f.oid)='p_club_id uuid' AND md5(pg_get_functiondef(f.oid))='f47253ca4ad50e4b59fe4c963bd7d169' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.my_self_subscribable_mailing_lists(p_club_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='prepare_team_selection_email_action' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='1fc93186ac5399548809d0d529f30770' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.prepare_team_selection_email_action()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='process_fixture_notification_queue' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='1a4aa278b1eebae5dc34b3c30b0ec770' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.process_fixture_notification_queue(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='process_fixture_post_publish_changes' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone, p_context jsonb' AND md5(pg_get_functiondef(f.oid))='5aed9aaf72133d9dd15f504bc4304e32' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.process_fixture_post_publish_changes(p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone, p_context jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='process_fixture_post_publish_communications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_changed_by_member_profile_id uuid' AND md5(pg_get_functiondef(f.oid))='7076e8cd3782909d5a756f7434a80acf' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.process_fixture_post_publish_communications(p_fixture_id uuid, p_changed_by_member_profile_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='process_notification_queue' AND pg_get_function_identity_arguments(f.oid)='p_limit integer' AND md5(pg_get_functiondef(f.oid))='117254ef03c795409d03b49b1388c1fe' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.process_notification_queue(p_limit integer)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='process_selected_notification_queue_rows' AND pg_get_function_identity_arguments(f.oid)='p_queue_ids uuid[]' AND md5(pg_get_functiondef(f.oid))='69551b3ed6673ffaf39839688efa10eb' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.process_selected_notification_queue_rows(p_queue_ids uuid[])'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='publish_team_selection_safe' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean' AND md5(pg_get_functiondef(f.oid))='93ff7c0f588d94abcf77199bea5cfca8' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.publish_team_selection_safe(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_fixture_moved_notifications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone' AND md5(pg_get_functiondef(f.oid))='58c01ef6ab786a7aed3ffb0ed0c93276' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_fixture_moved_notifications(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_fixture_opponent_changed_notifications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid' AND md5(pg_get_functiondef(f.oid))='f42546c9f0401be7ce8822d1ea263ead' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_fixture_opponent_changed_notifications(p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_fixture_selected_notifications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_attachments jsonb' AND md5(pg_get_functiondef(f.oid))='61a3ec4468bdd0fc77bfeb7ab7ed5a03' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_fixture_selected_notifications(p_fixture_id uuid, p_attachments jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_mailing_list_message' AND pg_get_function_identity_arguments(f.oid)='p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean, p_send_email boolean' AND md5(pg_get_functiondef(f.oid))='7703c5f92b45b661b6e98a8f7a9b137c' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_mailing_list_message(p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean, p_send_email boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_open_marker_request_communications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='0869c0039ace2416961c1850d74aeb06' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_open_marker_request_communications(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_post_publication_player_change' AND pg_get_function_identity_arguments(f.oid)='p_team_selection_member_id uuid, p_event_type text, p_actor_member_profile_id uuid' AND md5(pg_get_functiondef(f.oid))='f4b0265ed4563e52f9ed4242b62e67c0' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_post_publication_player_change(p_team_selection_member_id uuid, p_event_type text, p_actor_member_profile_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_team_acceptance_change' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='314b4fe38510e2e20babb43d1306e08f' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_team_acceptance_change()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='queue_team_publication_communications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean' AND md5(pg_get_functiondef(f.oid))='d096c1c5015413fe2afc2d912ef6cf5a' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.queue_team_publication_communications(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='reconcile_preselect_communications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='121395315a41e0774628a57f378abbf8' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.reconcile_preselect_communications(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='remap_green_rink_labels' AND pg_get_function_identity_arguments(f.oid)='p_green_area_id uuid, p_old_labels text[], p_new_labels text[]' AND md5(pg_get_functiondef(f.oid))='ff42ef50ac4ccbe18ec129d14a475523' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.remap_green_rink_labels(p_green_area_id uuid, p_old_labels text[], p_new_labels text[])'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='repair_fixture_publication_communications' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='d0f6c92cbd199c4f3eaf43c6ceb78b6a' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.repair_fixture_publication_communications(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='reschedule_cancelled_fixture_safe' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone' AND md5(pg_get_functiondef(f.oid))='32bb93b3a1ca41a7d5951eee347312d4' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.reschedule_cancelled_fixture_safe(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='reset_fixture_publication_test' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='0606e9f8e7de73e06dc126cea567722c' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.reset_fixture_publication_test(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='retry_fixture_failed_emails' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid' AND md5(pg_get_functiondef(f.oid))='9a06856e1b5f472f86b5bf4f73208bf2' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.retry_fixture_failed_emails(p_fixture_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='save_fixture_rink_assignments' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_team_selection_id uuid, p_assignments jsonb' AND md5(pg_get_functiondef(f.oid))='b3de69c2bff32dbfcfc2968d7307a505' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.save_fixture_rink_assignments(p_fixture_id uuid, p_team_selection_id uuid, p_assignments jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='save_preselect_fixture_state' AND pg_get_function_identity_arguments(f.oid)='p_fixture_id uuid, p_assignments jsonb' AND md5(pg_get_functiondef(f.oid))='3917246d1747200d010733abc3e2de3e' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.save_preselect_fixture_state(p_fixture_id uuid, p_assignments jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_club_created_by' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='331008ebaca0dec81eac473c03cd7c78' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_club_created_by()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_email_queue_cron_enabled' AND pg_get_function_identity_arguments(f.oid)='p_enabled boolean' AND md5(pg_get_functiondef(f.oid))='81fd96a721c029216830aa1602154585' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_email_queue_cron_enabled(p_enabled boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_fixture_time_range' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='90ae03d35e8fdf73c6d4673fd6a5a2f9' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_fixture_time_range()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_mailing_updated_at' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='b9f253892d59943905df6c358c83b517' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_mailing_updated_at()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_my_mailing_list_membership' AND pg_get_function_identity_arguments(f.oid)='p_mailing_list_id uuid, p_join boolean' AND md5(pg_get_functiondef(f.oid))='f93b1f817da0953722514cfb1af93387' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_my_mailing_list_membership(p_mailing_list_id uuid, p_join boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_notification_queue_cron_enabled' AND pg_get_function_identity_arguments(f.oid)='p_enabled boolean' AND md5(pg_get_functiondef(f.oid))='c9ff17fab9ec1138adef298e11d5d55b' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_notification_queue_cron_enabled(p_enabled boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_rsvp_member_profile' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='88c7bb6c3cb40b45388a3851cabd8422' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_rsvp_member_profile()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_team_selection_member_active' AND pg_get_function_identity_arguments(f.oid)='p_team_selection_id uuid, p_member_profile_id uuid, p_is_selected boolean' AND md5(pg_get_functiondef(f.oid))='17ee1d201099a53699b6261fdc95228b' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_team_selection_member_active(p_team_selection_id uuid, p_member_profile_id uuid, p_is_selected boolean)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_team_selection_member_role' AND pg_get_function_identity_arguments(f.oid)='p_team_selection_id uuid, p_member_profile_id uuid, p_role text' AND md5(pg_get_functiondef(f.oid))='be73077bbe35c2fa8553da536b4611ed' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_team_selection_member_role(p_team_selection_id uuid, p_member_profile_id uuid, p_role text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='set_updated_at' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='8de7ae383447503e8949149bfb3f0efb' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.set_updated_at()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='swap_fixture_rink_labels' AND pg_get_function_identity_arguments(f.oid)='p_a_fixture_rink_id uuid, p_b_fixture_rink_id uuid' AND md5(pg_get_functiondef(f.oid))='62c31739a41b8fa8ee32900d7dae4e2e' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.swap_fixture_rink_labels(p_a_fixture_rink_id uuid, p_b_fixture_rink_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='team_admin_add_member' AND pg_get_function_identity_arguments(f.oid)='p_team_selection_id uuid, p_member_profile_id uuid' AND md5(pg_get_functiondef(f.oid))='44aa74393d23f10c88bec6081edb8408' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.team_admin_add_member(p_team_selection_id uuid, p_member_profile_id uuid)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='team_admin_set_acceptance' AND pg_get_function_identity_arguments(f.oid)='p_team_selection_member_id uuid, p_acceptance text' AND md5(pg_get_functiondef(f.oid))='b9eec6f10a69cb2fb3e4b7bed583544c' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.team_admin_set_acceptance(p_team_selection_member_id uuid, p_acceptance text)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='touch_updated_at' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='47cea50a4d1fac74602a83760d7d0dea' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.touch_updated_at()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='update_club_venue_full' AND pg_get_function_identity_arguments(f.oid)='p_venue_id uuid, p_club_id uuid, p_name text, p_is_home_venue boolean, p_town_city text, p_postcode text, p_contact_name text, p_contact_phone text, p_contact_email text, p_address_line1 text, p_address_line2 text, p_directions_url text, p_website_url text, p_google_maps_url text, p_google_place_id text, p_latitude double precision, p_longitude double precision, p_club_officers jsonb' AND md5(pg_get_functiondef(f.oid))='ee09bc065242509fe80478135e386d75' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.update_club_venue_full(p_venue_id uuid, p_club_id uuid, p_name text, p_is_home_venue boolean, p_town_city text, p_postcode text, p_contact_name text, p_contact_phone text, p_contact_email text, p_address_line1 text, p_address_line2 text, p_directions_url text, p_website_url text, p_google_maps_url text, p_google_place_id text, p_latitude double precision, p_longitude double precision, p_club_officers jsonb)'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='validate_fixture_links' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='f3a4ccb436b4e98c0be2786f679d5053' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.validate_fixture_links()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='validate_fixture_rink' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='b4ea5a7cbbc37126bb5a70b8818ecbb7' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.validate_fixture_rink()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='validate_fixture_rink_assignment' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='af80dd1f8b659ab2b022d6db1c0d1be3' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.validate_fixture_rink_assignment()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='validate_green_rink_maintenance' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='b72dbb98489d22a8b41d606879f492e8' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.validate_green_rink_maintenance()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='validate_mailing_list_member_club' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='406b334fe41c9c7638b505f0ed944167' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.validate_mailing_list_member_club()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='validate_required_team_sheet_email_attachment' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='56f8a536ef12f539edbc4946daa83197' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['postgres=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.validate_required_team_sheet_email_attachment()'; END IF;
IF NOT EXISTS (SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace WHERE n.nspname='public' AND f.proname='validate_volunteer_task_mailing_list' AND pg_get_function_identity_arguments(f.oid)='' AND md5(pg_get_functiondef(f.oid))='65bcd564946ae457a0a85da072d91539' AND (SELECT array_agg(v::text ORDER BY v::text) FROM unnest(coalesce(f.proacl,acldefault('f',f.proowner))) v) = ARRAY['=X/postgres','anon=X/postgres','authenticated=X/postgres','postgres=X/postgres','service_role=X/postgres']::text[]) THEN RAISE EXCEPTION 'Production function drift: %', 'public.validate_volunteer_task_mailing_list()'; END IF;
END $preflight$;

CREATE SCHEMA IF NOT EXISTS audit_private AUTHORIZATION postgres;

REVOKE ALL ON SCHEMA audit_private FROM PUBLIC, anon, authenticated, service_role;

CREATE SCHEMA notification_security AUTHORIZATION postgres;

REVOKE ALL ON SCHEMA notification_security FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA notification_security TO authenticated;

CREATE TABLE "audit_private"."import_runs" (
  "id" uuid DEFAULT gen_random_uuid() NOT NULL,
  "actor" uuid NOT NULL,
  "club_id" uuid NOT NULL,
  "filename" text NOT NULL,
  "new_members_active" boolean NOT NULL,
  "started_at" timestamp with time zone DEFAULT now() NOT NULL,
  "finished_at" timestamp with time zone
);

CREATE TABLE "public"."audit_journal" (
  "id" bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  "occurred_at" timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
  "operation_id" bigint DEFAULT txid_current() NOT NULL,
  "actor_user_id" uuid,
  "actor_name" text NOT NULL,
  "origin" text NOT NULL,
  "club_id" uuid,
  "club_name" text,
  "record_type" text NOT NULL,
  "record_id" text,
  "record_label" text NOT NULL,
  "fixture_id" uuid,
  "action" text NOT NULL,
  "reason" text,
  "before_values" jsonb,
  "after_values" jsonb,
  "outcome" text DEFAULT 'completed'::text NOT NULL
);

CREATE TABLE "public"."email_written_replies" (
  "id" uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
  "mailbox" text NOT NULL,
  "internet_message_id" text NOT NULL,
  "graph_message_id" text NOT NULL,
  "request_id" uuid,
  "received_at" timestamp with time zone NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE "public"."email_written_reply_reminders" (
  "target_record_id" uuid NOT NULL,
  "reply_id" uuid NOT NULL,
  "delivery_status" text DEFAULT 'claimed'::text NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE "public"."email_written_reply_settings" (
  "mailbox" text NOT NULL,
  "enabled" boolean DEFAULT false NOT NULL,
  "enabled_at" timestamp with time zone DEFAULT now() NOT NULL,
  "reminder_recipients" text[] DEFAULT '{}'::text[] NOT NULL
);

ALTER TABLE "public"."fixtures" ADD COLUMN "archive_reason" text;

ALTER TABLE "public"."fixtures" ADD COLUMN "archived_at" timestamp with time zone;

ALTER TABLE "public"."fixtures" ADD COLUMN "created_by_user_id" uuid;

ALTER TABLE "audit_private"."import_runs" ADD CONSTRAINT "import_runs_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."audit_journal" ADD CONSTRAINT "audit_journal_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."email_written_replies" ADD CONSTRAINT "email_written_replies_mailbox_internet_message_id_key" UNIQUE (mailbox, internet_message_id);

ALTER TABLE "public"."email_written_replies" ADD CONSTRAINT "email_written_replies_pkey" PRIMARY KEY (id);

ALTER TABLE "public"."email_written_reply_reminders" ADD CONSTRAINT "email_written_reply_reminders_delivery_status_check" CHECK (delivery_status = ANY (ARRAY['claimed'::text, 'accepted'::text, 'failed_or_unknown'::text]));

ALTER TABLE "public"."email_written_reply_reminders" ADD CONSTRAINT "email_written_reply_reminders_pkey" PRIMARY KEY (target_record_id);

ALTER TABLE "public"."email_written_reply_settings" ADD CONSTRAINT "email_written_reply_settings_pkey" PRIMARY KEY (mailbox);

ALTER TABLE "public"."email_written_replies" ADD CONSTRAINT "email_written_replies_request_id_fkey" FOREIGN KEY (request_id) REFERENCES email_action_requests(id) ON DELETE SET NULL;

ALTER TABLE "public"."email_written_reply_reminders" ADD CONSTRAINT "email_written_reply_reminders_reply_id_fkey" FOREIGN KEY (reply_id) REFERENCES email_written_replies(id) ON DELETE CASCADE;

CREATE INDEX audit_journal_actor_time_idx ON public.audit_journal USING btree (actor_user_id, occurred_at DESC);

CREATE INDEX audit_journal_club_time_idx ON public.audit_journal USING btree (club_id, occurred_at DESC);

CREATE INDEX audit_journal_fixture_idx ON public.audit_journal USING btree (fixture_id);

CREATE INDEX audit_journal_record_idx ON public.audit_journal USING btree (record_type, record_id);

CREATE INDEX audit_journal_time_idx ON public.audit_journal USING btree (occurred_at DESC, id DESC);

CREATE INDEX capacity_cm_member_active_club_idx ON public.club_memberships USING btree (member_profile_id, club_id) WHERE (is_active = true);

CREATE INDEX email_written_replies_request_idx ON public.email_written_replies USING btree (request_id);

CREATE INDEX email_written_reply_reminders_reply_idx ON public.email_written_reply_reminders USING btree (reply_id);

CREATE INDEX user_push_tokens_owner_idx ON public.user_push_tokens USING btree (user_id);

CREATE OR REPLACE FUNCTION audit_private.capture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 b jsonb; a jsonb; r jsonb; keys text[] := string_to_array(TG_ARGV[0],',');
 cid uuid; fid uuid; rid text; actor uuid := auth.uid(); actor_label text;
 label text; club_label text; event text := lower(TG_OP); source text;
begin
 if TG_OP<>'INSERT' then b:=audit_private.pick(to_jsonb(old),keys); end if;
 if TG_OP<>'DELETE' then a:=audit_private.pick(to_jsonb(new),keys); end if;
 if TG_OP='UPDATE' and b=a then return new; end if;
 r:=coalesce(a,b); rid:=coalesce(r->>'id',r->>'user_id');
 cid:=(r->>'club_id')::uuid; fid:=(r->>'fixture_id')::uuid;
 if TG_TABLE_NAME='fixtures' then fid:=rid::uuid; end if;
 if TG_TABLE_NAME='clubs' then cid:=rid::uuid; end if;
 if TG_TABLE_NAME='team_members' then
   select t.club_id,t.name into cid,label from public.teams t where t.id=(r->>'team_id')::uuid;
 end if;
 if TG_TABLE_NAME='team_selection_members' then
   select s.fixture_id into fid from public.team_selections s where s.id=(r->>'team_selection_id')::uuid;
 end if;
 if fid is not null then
   select f.club_id,coalesce(nullif(f.team_name,''),'Fixture')||' / '||f.start_at::text
   into cid,label from public.fixtures f where f.id=fid;
 end if;
 cid:=coalesce(cid,(r->>'club_id')::uuid);
 if TG_TABLE_NAME='member_profiles' then label:=concat_ws(' ',r->>'first_name',r->>'last_name'); end if;
 if r->>'member_profile_id' is not null then
   select concat_ws(' / ',label,concat_ws(' ',p.first_name,p.last_name)) into label
   from public.member_profiles p where p.id=(r->>'member_profile_id')::uuid;
 end if;
 label:=coalesce(nullif(label,''),nullif(r->>'name',''),nullif(r->>'title',''),nullif(r->>'team_name',''),TG_TABLE_NAME||' '||rid::text);
 select c.name into club_label from public.clubs c where c.id=cid;
 source:=case when actor is not null then 'app' when coalesce(auth.role(),'')='service_role' then 'service' else 'database maintenance' end;
 -- These fields are populated by verified server workflows, not inferred from the recipient.
 if actor is null and auth.role()='service_role' and TG_TABLE_NAME='member_invitation_attempts' then
   actor:=(coalesce(to_jsonb(new),to_jsonb(old))->>'created_by')::uuid;
 end if;
 select concat_ws(' ',p.first_name,p.last_name) into actor_label from public.member_profiles p where p.user_id=actor limit 1;
 actor_label:=coalesce(nullif(actor_label,''),actor::text,source||' (individual not identified)');
 if TG_TABLE_NAME='fixtures' and TG_OP='UPDATE' then
   if b->>'archived_at' is distinct from a->>'archived_at' then event:=case when a->>'archived_at' is null then 'restored' else 'archived' end;
   elsif b->>'cancelled_at' is distinct from a->>'cancelled_at' and a->>'cancelled_at' is not null then event:='cancelled';
   elsif b->>'rescheduled_at' is distinct from a->>'rescheduled_at' or b->>'rescheduled_to_fixture_id' is distinct from a->>'rescheduled_to_fixture_id' or b->>'start_at' is distinct from a->>'start_at' or b->>'end_at' is distinct from a->>'end_at' then event:='rescheduled'; end if;
 end if;
 if TG_TABLE_NAME='team_selections' and TG_OP in ('INSERT','UPDATE') and (TG_OP='INSERT' or b->>'status' is distinct from a->>'status') then
   if a->>'status'='published' then event:='published'; elsif b->>'status'='published' then event:='publication withdrawn'; end if;
 end if;
 insert into public.audit_journal(actor_user_id,actor_name,origin,club_id,club_name,record_type,record_id,record_label,fixture_id,action,reason,before_values,after_values,outcome)
 values(actor,actor_label,source,cid,club_label,TG_TABLE_NAME,rid,label,fid,event,
 coalesce(nullif(current_setting('app.audit_reason',true),''),r->>'cancellation_reason'),b,a,
 case when r->>'status' in ('failed','error') then 'failed' else 'completed' end);
 if TG_OP='DELETE' then return old; end if; return new;
end $function$;

REVOKE ALL ON FUNCTION "audit_private"."capture"() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION audit_private.capture_fixture_rsvp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  b jsonb;
  a jsonb;
  r jsonb;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_club_id uuid;
  v_club_name text;
  v_fixture_id uuid;
  v_fixture_label text;
  v_member_name text;
  v_action text := lower(TG_OP);
  v_origin text;
begin
  if TG_OP <> 'INSERT' then
    b := audit_private.pick(to_jsonb(old), array[
      'id','fixture_id','member_profile_id','status','responded_at'
    ]);
  end if;
  if TG_OP <> 'DELETE' then
    a := audit_private.pick(to_jsonb(new), array[
      'id','fixture_id','member_profile_id','status','responded_at'
    ]);
  end if;
  if TG_OP = 'UPDATE' and b = a then return new; end if;

  r := coalesce(a,b);
  v_fixture_id := (r->>'fixture_id')::uuid;
  select f.club_id,
         coalesce(nullif(f.team_name,''),nullif(f.opponent_name,''),'Fixture') ||
           ' / ' || f.start_at::text
    into v_club_id,v_fixture_label
    from public.fixtures f where f.id = v_fixture_id;
  select nullif(trim(concat_ws(' ',p.first_name,p.last_name)),'')
    into v_member_name
    from public.member_profiles p where p.id = (r->>'member_profile_id')::uuid;
  select c.name into v_club_name from public.clubs c where c.id = v_club_id;

  v_origin := case
    when v_actor is not null then 'app'
    when coalesce(auth.role(),'') = 'service_role' then 'service'
    else 'database maintenance'
  end;
  select nullif(trim(concat_ws(' ',p.first_name,p.last_name)),'')
    into v_actor_name
    from public.member_profiles p where p.user_id = v_actor limit 1;
  v_actor_name := coalesce(v_actor_name,v_actor::text,v_origin || ' (individual not identified)');

  insert into public.audit_journal(
    actor_user_id,actor_name,origin,club_id,club_name,record_type,
    record_id,record_label,fixture_id,action,reason,before_values,after_values,outcome
  ) values (
    v_actor,v_actor_name,v_origin,v_club_id,v_club_name,'fixture_rsvps',
    r->>'id',concat_ws(' / ',v_fixture_label,v_member_name),v_fixture_id,v_action,
    nullif(current_setting('app.audit_reason',true),''),b,a,'completed'
  );

  if TG_OP = 'DELETE' then return old; end if;
  return new;
end $function$;

REVOKE ALL ON FUNCTION "audit_private"."capture_fixture_rsvp"() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION audit_private.guard_archived_fixture()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE'
    and old.cancelled_at is null
    and new.cancelled_at is not null
    and length(trim(coalesce(new.cancellation_reason,''))) < 5
  then
    raise exception 'A cancellation reason of at least five characters is required';
  end if;
  return new;
end $function$;

REVOKE ALL ON FUNCTION "audit_private"."guard_archived_fixture"() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION audit_private.guard_fixture_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if current_user = 'postgres'
    and current_setting('app.audit_delete_mode', true) in ('ordinary','force')
  then return old; end if;
  raise exception 'Use the audited fixture deletion action';
end $function$;

REVOKE ALL ON FUNCTION "audit_private"."guard_fixture_delete"() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION audit_private.immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
begin raise exception 'Audit entries cannot be changed or removed'; end $function$;

REVOKE ALL ON FUNCTION "audit_private"."immutable"() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION audit_private.pick(v jsonb, keys text[])
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(v) where key=any(keys)
$function$;

REVOKE ALL ON FUNCTION "audit_private"."pick"(v jsonb, keys text[]) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION audit_private.set_fixture_creator()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    new.created_by_user_id := auth.uid();
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Fixture creator cannot be changed';
  end if;
  return new;
end $function$;

REVOKE ALL ON FUNCTION "audit_private"."set_fixture_creator"() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION invitation_private.check_initial_password(p_user uuid, p_club uuid, p_password text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from invitation_private.imported_accounts i join auth.users u on u.id=i.user_id
    where i.user_id=p_user and i.club_id=p_club and u.last_sign_in_at is null
      and i.password_fingerprint=md5(u.encrypted_password)
      and length(p_password)>0
      and extensions.crypt(p_password,u.encrypted_password)=u.encrypted_password
  );
$function$;

REVOKE ALL ON FUNCTION "invitation_private"."check_initial_password"(p_user uuid, p_club uuid, p_password text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "invitation_private"."check_initial_password"(p_user uuid, p_club uuid, p_password text) TO "service_role";

CREATE OR REPLACE FUNCTION notification_security.can_enqueue(q notification_queue)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare actor uuid; club uuid; f public.fixtures; manager boolean; super boolean;
begin
 if auth.uid() is null then return false; end if;
 actor:=public.my_member_profile_id();
 if actor is null or q.member_profile_id is distinct from actor
    or q.target_member_profile_id is null or q.status is distinct from 'pending'
    or q.attempts<>0 or q.last_error is not null or q.processed_at is not null
    or q.recipient_email is not null then return false; end if;
 super:=public.is_app_superuser();
 if q.event_type='guest_membership_approved' then
  if q.fixture_id is not null or q.team_selection_id is not null then return false; end if;
  begin club:=(q.payload->>'club_id')::uuid; exception when invalid_text_representation then return false; end;
  return coalesce((super or public.is_club_admin(club)) and exists(
   select 1 from public.club_memberships where club_id=club and member_profile_id=q.target_member_profile_id
    and is_active and role::text='member'),false);
 end if;
 if q.event_type not in ('fixture_message','acceptance_reminder','fixture_selected') then return false; end if;
 select * into f from public.fixtures where id=q.fixture_id;
 if not found then return false; end if;
 if not super and not exists(select 1 from public.club_memberships
  where club_id=f.club_id and member_profile_id=actor and is_active and role::text<>'guest') then return false; end if;
 if not exists(select 1 from public.club_memberships where club_id=f.club_id
  and member_profile_id=q.target_member_profile_id and is_active) then return false; end if;
 if q.team_selection_id is not null and not exists(select 1 from public.team_selections
  where id=q.team_selection_id and fixture_id=f.id) then return false; end if;
 manager:=super or actor in (f.captain_member_profile_id,f.vice_captain_member_profile_id)
  or exists(select 1 from public.club_memberships where club_id=f.club_id and member_profile_id=actor
   and is_active and role::text in ('admin','selector'));
 if q.event_type='fixture_selected' then
  return coalesce((manager or actor=q.target_member_profile_id) and exists(
   select 1 from public.fixture_rink_assignments where fixture_id=f.id and member_profile_id=q.target_member_profile_id),false);
 end if;
 if not coalesce(manager,false) then return false; end if;
 if q.event_type='acceptance_reminder' then
  return exists(select 1 from public.team_selection_members where team_selection_id=q.team_selection_id
   and member_profile_id=q.target_member_profile_id and acceptance::text='pending');
 end if;
 return coalesce(q.target_member_profile_id in (f.captain_member_profile_id,f.vice_captain_member_profile_id)
  or exists(select 1 from public.team_selection_members where team_selection_id=q.team_selection_id
   and member_profile_id=q.target_member_profile_id),false);
end;
$function$;

REVOKE ALL ON FUNCTION "notification_security"."can_enqueue"(q notification_queue) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "notification_security"."can_enqueue"(q notification_queue) TO "authenticated";

CREATE OR REPLACE FUNCTION public.accept_invite(p_token uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_invite public.club_invites%rowtype;
 v_user_id uuid:=auth.uid();
 v_user_email text;
 v_member_profile_id uuid;
begin
 if v_user_id is null then raise exception 'Not authenticated'; end if;
 select * into v_invite from public.club_invites where token=p_token for update;
 if not found then raise exception 'Invalid invite token'; end if;
 if v_invite.used_at is not null or v_invite.status<>'pending' then
  raise exception 'Invite already used or not pending';
 end if;
 select email into v_user_email from auth.users where id=v_user_id;
 if v_user_email is null then raise exception 'User email not found'; end if;
 if lower(v_user_email)<>lower(v_invite.email) then
  raise exception 'Invite email does not match logged-in user';
 end if;
 select id into v_member_profile_id from public.member_profiles where user_id=v_user_id;
 if v_member_profile_id is null then
  insert into public.member_profiles(user_id,display_name,first_name,last_name)
  values(v_user_id,coalesce(nullif(trim(concat_ws(' ',v_invite.first_name,v_invite.last_name)),''),v_user_email),v_invite.first_name,v_invite.last_name)
  returning id into v_member_profile_id;
 end if;
 insert into public.club_memberships(club_id,member_profile_id,role)
 values(v_invite.club_id,v_member_profile_id,v_invite.role::public.club_role)
 on conflict(club_id,member_profile_id) do nothing;
 update public.club_invites set used_at=now(),used_by=v_user_id,status='used'
 where id=v_invite.id;
 return true;
end $function$;

REVOKE ALL ON FUNCTION "public"."accept_invite"(p_token uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."accept_invite"(p_token uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."accept_invite"(p_token uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.add_member_to_club_by_email(p_club_id uuid, p_email text, p_role club_role DEFAULT 'member'::club_role)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_user_id uuid;
  v_profile_id uuid;
begin
  -- Only club admins can add members
  if not public.is_club_admin(p_club_id) then
    raise exception 'Not authorized';
  end if;

  -- Find auth user
  select id into v_user_id
  from auth.users
  where lower(email) = lower(p_email)
  limit 1;

  if v_user_id is null then
    raise exception 'No auth user found for email %', p_email;
  end if;

  -- Find or create member profile for that auth user
  select id into v_profile_id
  from public.member_profiles
  where user_id = v_user_id
  limit 1;

  if v_profile_id is null then
    insert into public.member_profiles (user_id, display_name)
    values (v_user_id, split_part(p_email, '@', 1))
    returning id into v_profile_id;
  end if;

  -- Add membership (or reactivate/update role)
  insert into public.club_memberships (club_id, member_profile_id, role, is_active)
  values (p_club_id, v_profile_id, p_role, true)
  on conflict (club_id, member_profile_id)
  do update set
    role = excluded.role,
    is_active = true;

  return v_profile_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."add_member_to_club_by_email"(p_club_id uuid, p_email text, p_role club_role) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."add_member_to_club_by_email"(p_club_id uuid, p_email text, p_role club_role) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."add_member_to_club_by_email"(p_club_id uuid, p_email text, p_role club_role) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."add_member_to_club_by_email"(p_club_id uuid, p_email text, p_role club_role) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."add_member_to_club_by_email"(p_club_id uuid, p_email text, p_role club_role) TO "service_role";

CREATE OR REPLACE FUNCTION public.add_team_members_to_pool(p_team_id uuid, p_member_profile_ids uuid[])
 RETURNS SETOF team_members
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  with requested_ids as (
    select distinct requested.member_profile_id
    from unnest(coalesce(p_member_profile_ids, array[]::uuid[]))
      as requested(member_profile_id)
    where requested.member_profile_id is not null
  ),
  requested_members as (
    select requested.member_profile_id
    from requested_ids requested
    join public.teams team
      on team.id = p_team_id
    join public.club_memberships membership
      on membership.club_id = team.club_id
     and membership.member_profile_id = requested.member_profile_id
     and membership.is_active = true
     and lower(membership.role::text) <> 'guest'
  ),
  activated_members as (
    insert into public.team_members as existing_team_member (
      team_id,
      member_profile_id,
      is_active
    )
    select
      p_team_id,
      requested.member_profile_id,
      true
    from requested_members requested
    on conflict (team_id, member_profile_id) do update
      set is_active = true
      where existing_team_member.is_active = false
    returning existing_team_member.*
  )
  select activated.*
  from activated_members activated

  union all

  select team_member.*
  from public.team_members team_member
  join requested_members requested
    on requested.member_profile_id = team_member.member_profile_id
  where team_member.team_id = p_team_id
    and team_member.is_active = true
    and not exists (
      select 1
      from activated_members activated
      where activated.id = team_member.id
    );
$function$;

REVOKE ALL ON FUNCTION "public"."add_team_members_to_pool"(p_team_id uuid, p_member_profile_ids uuid[]) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."add_team_members_to_pool"(p_team_id uuid, p_member_profile_ids uuid[]) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."add_team_members_to_pool"(p_team_id uuid, p_member_profile_ids uuid[]) TO "service_role";

CREATE OR REPLACE FUNCTION public.admin_add_member_by_email(p_club_id uuid, p_email text, p_role club_role DEFAULT 'member'::club_role, p_is_active boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid;
  v_profile_id uuid;
begin
  if not public.is_club_admin(p_club_id) then
    raise exception 'not admin';
  end if;

  select id into v_user_id
  from auth.users
  where lower(email) = lower(p_email)
  limit 1;

  if v_user_id is null then
    raise exception 'No auth user found for email %', p_email;
  end if;

  select id into v_profile_id
  from public.member_profiles
  where user_id = v_user_id
  limit 1;

  if v_profile_id is null then
    insert into public.member_profiles(user_id, display_name)
    values (v_user_id, split_part(p_email, '@', 1))
    returning id into v_profile_id;
  end if;

  insert into public.club_memberships(club_id, member_profile_id, role, is_active)
  values (p_club_id, v_profile_id, p_role, p_is_active)
  on conflict (club_id, member_profile_id)
  do update set role = excluded.role, is_active = excluded.is_active;

end;
$function$;

REVOKE ALL ON FUNCTION "public"."admin_add_member_by_email"(p_club_id uuid, p_email text, p_role club_role, p_is_active boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."admin_add_member_by_email"(p_club_id uuid, p_email text, p_role club_role, p_is_active boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."admin_add_member_by_email"(p_club_id uuid, p_email text, p_role club_role, p_is_active boolean) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."admin_add_member_by_email"(p_club_id uuid, p_email text, p_role club_role, p_is_active boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."admin_add_member_by_email"(p_club_id uuid, p_email text, p_role club_role, p_is_active boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.admin_find_orphaned_records()
 RETURNS TABLE(item text, orphan_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Allow SQL Editor / postgres/admin execution
  if auth.uid() is not null then
    if not exists (
      select 1
      from app_superusers su
      where su.user_id = auth.uid()
    ) then
      raise exception 'Only superusers can check orphaned records';
    end if;
  end if;

  item := 'fixture_rink_assignments missing fixture';
  select count(*) into orphan_count
  from fixture_rink_assignments fra
  where not exists (
    select 1 from fixtures f where f.id = fra.fixture_id
  );
  return next;

  item := 'fixture_rinks missing fixture';
  select count(*) into orphan_count
  from fixture_rinks fr
  where not exists (
    select 1 from fixtures f where f.id = fr.fixture_id
  );
  return next;

  item := 'fixture_rsvps missing fixture';
  select count(*) into orphan_count
  from fixture_rsvps r
  where not exists (
    select 1 from fixtures f where f.id = r.fixture_id
  );
  return next;

  item := 'team_selections missing fixture';
  select count(*) into orphan_count
  from team_selections ts
  where not exists (
    select 1 from fixtures f where f.id = ts.fixture_id
  );
  return next;

  item := 'team_selection_members missing team_selection';
  select count(*) into orphan_count
  from team_selection_members tsm
  where not exists (
    select 1 from team_selections ts where ts.id = tsm.team_selection_id
  );
  return next;

  item := 'club_schedule_items missing linked fixture';
  select count(*) into orphan_count
  from club_schedule_items csi
  where csi.linked_fixture_id is not null
    and not exists (
      select 1 from fixtures f where f.id = csi.linked_fixture_id
    );
  return next;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."admin_find_orphaned_records"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."admin_find_orphaned_records"() TO "service_role";

CREATE OR REPLACE FUNCTION public.admin_force_delete_fixture(p_fixture_id uuid, p_confirm text DEFAULT NULL::text)
 RETURNS TABLE(item text, deleted_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin raise exception 'Update the app to force delete with a reason'; end $function$;

REVOKE ALL ON FUNCTION "public"."admin_force_delete_fixture"(p_fixture_id uuid, p_confirm text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_force_delete_fixture(p_fixture_id uuid, p_reason text, p_confirm text)
 RETURNS TABLE(item text, deleted_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f public.fixtures;
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_club_name text;
  v_preview jsonb;
  v_count integer;
begin
  if v_actor is null or not exists(
    select 1 from public.app_superusers s where s.user_id = v_actor
  ) then raise exception 'Superuser access required'; end if;
  if p_confirm is distinct from 'DELETE FIXTURE' then
    raise exception 'Type DELETE FIXTURE to confirm'; end if;
  select * into f from public.fixtures where id = p_fixture_id for update;
  if not found then raise exception 'Fixture not found'; end if;
  v_preview := public.fixture_deletion_preview(p_fixture_id);
  select nullif(trim(concat_ws(' ',m.first_name,m.last_name)), '')
    into v_actor_name from public.member_profiles m where m.user_id = v_actor limit 1;
  select c.name into v_club_name from public.clubs c where c.id = f.club_id;

  -- This entry and the automatic DELETE entry share one transaction.
  insert into public.audit_journal(
    actor_user_id, actor_name, origin, club_id, club_name,
    record_type, record_id, record_label, fixture_id, action,
    reason, before_values, after_values)
  values(
    v_actor, coalesce(v_actor_name,v_actor::text), 'app', f.club_id, v_club_name,
    'fixtures', f.id::text,
    coalesce(nullif(f.team_name,''),nullif(f.opponent_name,''),'Fixture') || ' / ' || f.start_at::text,
    f.id, 'force deletion authorized', nullif(trim(coalesce(p_reason,'')),''),
    audit_private.pick(to_jsonb(f), array[
      'id','club_id','team_id','team_name','start_at','end_at','venue_id',
      'opponent_venue_id','opponent_name','section','competition_type_id',
      'captain_member_profile_id','vice_captain_member_profile_id',
      'cancelled_at','cancellation_reason','archived_at','archive_reason',
      'created_by_user_id'
    ]), v_preview
  );
  perform set_config('app.audit_reason', coalesce(trim(p_reason),''), true);
  perform set_config('app.audit_delete_mode', 'force', true);

  delete from public.club_schedule_items where linked_fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'club_schedule_items'; deleted_count := v_count; return next;
  delete from public.fixture_email_log where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'fixture_email_log'; deleted_count := v_count; return next;
  delete from public.notification_queue where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'notification_queue'; deleted_count := v_count; return next;
  delete from public.email_queue where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'email_queue'; deleted_count := v_count; return next;
  delete from public.app_notifications where fixture_id = f.id;
  get diagnostics v_count = row_count;
  item := 'app_notifications'; deleted_count := v_count; return next;
  -- Remaining fixture-linked rows have database-managed ON DELETE actions.
  delete from public.fixtures where id = f.id;
  get diagnostics v_count = row_count;
  item := 'fixtures'; deleted_count := v_count; return next;
end $function$;

REVOKE ALL ON FUNCTION "public"."admin_force_delete_fixture"(p_fixture_id uuid, p_reason text, p_confirm text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."admin_force_delete_fixture"(p_fixture_id uuid, p_reason text, p_confirm text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."admin_force_delete_fixture"(p_fixture_id uuid, p_reason text, p_confirm text) TO "service_role";

CREATE OR REPLACE FUNCTION public.admin_update_membership(p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_club_admin(p_club_id) then
    raise exception 'not admin';
  end if;

  update public.club_memberships
  set role = p_role,
      is_active = p_is_active
  where club_id = p_club_id
    and member_profile_id = p_member_profile_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."admin_update_membership"(p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."admin_update_membership"(p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."admin_update_membership"(p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."admin_update_membership"(p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."admin_update_membership"(p_club_id uuid, p_member_profile_id uuid, p_role club_role, p_is_active boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.apply_email_action_response(p_response_code text, p_command text, p_sender_email text, p_graph_message_id text, p_received_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select public.apply_email_action_response(
    p_response_code,
    p_command,
    p_sender_email,
    null::text,
    p_graph_message_id,
    p_received_at
  );
$function$;

REVOKE ALL ON FUNCTION "public"."apply_email_action_response"(p_response_code text, p_command text, p_sender_email text, p_graph_message_id text, p_received_at timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."apply_email_action_response"(p_response_code text, p_command text, p_sender_email text, p_graph_message_id text, p_received_at timestamp with time zone) TO "service_role";

CREATE OR REPLACE FUNCTION public.apply_email_action_response(p_response_code text, p_command text, p_sender_email text, p_response_token text, p_graph_message_id text, p_received_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_request public.email_action_requests%rowtype;
  v_command text := upper(btrim(coalesce(p_command, '')));
  v_sender text := lower(btrim(coalesce(p_sender_email, '')));
  v_code_hash text;
  v_token_hash text;
  v_acceptance public.acceptance_status;
  v_target_valid boolean := false;
  v_result_detail text;
begin
  if nullif(btrim(coalesce(p_graph_message_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'status', 'invalid_message_id');
  end if;

  if exists (
    select 1
    from public.email_action_response_log
    where graph_message_id = p_graph_message_id
  ) then
    return jsonb_build_object('ok', true, 'status', 'duplicate');
  end if;

  if nullif(btrim(coalesce(p_response_code, '')), '') is null then
    insert into public.email_action_response_log(
      graph_message_id, sender_email, command, result_status,
      result_detail, received_at
    ) values (
      p_graph_message_id, v_sender, v_command, 'invalid_code',
      'Response code was empty', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_code');
  end if;

  v_code_hash := encode(
    extensions.digest(upper(btrim(p_response_code)), 'sha256'),
    'hex'
  );

  select *
  into v_request
  from public.email_action_requests
  where response_code_hash = v_code_hash
  for update;

  if not found then
    insert into public.email_action_response_log(
      graph_message_id, sender_email, command, result_status,
      result_detail, received_at
    ) values (
      p_graph_message_id, v_sender, v_command, 'invalid_code',
      'No action request matched the supplied response code', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_code');
  end if;

  if v_request.status in ('cancelled', 'expired') then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      v_request.status, 'The action request is no longer active', p_received_at
    );

    return jsonb_build_object('ok', false, 'status', v_request.status);
  end if;

  if v_request.response_protocol_version >= 2
     and v_request.status = 'responded' then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'already_responded', 'The single-use action request has already been completed',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'already_responded');
  end if;

  if v_request.expires_at is not null and now() >= v_request.expires_at then
    update public.email_action_requests
       set status = 'expired', updated_at = now()
     where id = v_request.id;

    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'expired', 'The response arrived after the fixture response deadline',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'expired');
  end if;

  if v_request.response_protocol_version >= 2 then
    if v_request.response_token_hash is null then
      insert into public.email_action_response_log(
        request_id, graph_message_id, sender_email, command,
        result_status, result_detail, received_at
      ) values (
        v_request.id, p_graph_message_id, v_sender, v_command,
        'token_not_issued', 'The response token has not been issued for delivery',
        p_received_at
      );

      return jsonb_build_object('ok', false, 'status', 'token_not_issued');
    end if;

    if nullif(btrim(coalesce(p_response_token, '')), '') is null then
      insert into public.email_action_response_log(
        request_id, graph_message_id, sender_email, command,
        result_status, result_detail, received_at
      ) values (
        v_request.id, p_graph_message_id, v_sender, v_command,
        'invalid_token', 'The signed response token was missing',
        p_received_at
      );

      return jsonb_build_object('ok', false, 'status', 'invalid_token');
    end if;

    v_token_hash := encode(
      extensions.digest(upper(btrim(p_response_token)), 'sha256'),
      'hex'
    );

    if v_token_hash <> v_request.response_token_hash then
      insert into public.email_action_response_log(
        request_id, graph_message_id, sender_email, command,
        result_status, result_detail, received_at
      ) values (
        v_request.id, p_graph_message_id, v_sender, v_command,
        'invalid_token', 'The signed response token did not match the action request',
        p_received_at
      );

      return jsonb_build_object('ok', false, 'status', 'invalid_token');
    end if;
  elsif v_sender = ''
     or v_sender <> lower(btrim(v_request.recipient_email)) then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'sender_mismatch',
      'Legacy response sender did not match the selected member email address',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'sender_mismatch');
  end if;

  if not (v_command = any(v_request.allowed_actions)) then
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'invalid_command', 'Command is not allowed for this action request',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'invalid_command');
  end if;

  if v_request.action_type = 'team_selection' then
    select exists (
      select 1
      from public.team_selection_members tsm
      join public.team_selections ts
        on ts.id = tsm.team_selection_id
      join public.fixtures f
        on f.id = ts.fixture_id
      where tsm.id = v_request.target_record_id
        and tsm.member_profile_id = v_request.member_profile_id
        and tsm.role::text in ('player', 'opponent')
        and coalesce(tsm.is_selected, false) = true
        and ts.status = 'published'
        and f.cancelled_at is null
        and f.id = v_request.fixture_id
        and exists (
          select 1
          from public.fixture_rink_assignments fra
          join public.fixture_rinks fr
            on fr.id = fra.fixture_rink_id
           and fr.fixture_id = f.id
          where fra.fixture_id = f.id
            and fra.member_profile_id = tsm.member_profile_id
            and (
              fra.position between 1 and fr.players_per_rink
              or fra.position between 101 and (100 + fr.players_per_rink)
            )
        )
    ) into v_target_valid;

    v_result_detail := 'Team selection acceptance was updated';

  elsif v_request.action_type = 'marker_assignment' then
    select exists (
      select 1
      from public.team_selection_members tsm
      join public.team_selections ts
        on ts.id = tsm.team_selection_id
      join public.fixtures f
        on f.id = ts.fixture_id
      where tsm.id = v_request.target_record_id
        and tsm.member_profile_id = v_request.member_profile_id
        and tsm.role::text = 'marker'
        and coalesce(tsm.is_selected, false) = true
        and ts.status = 'published'
        and f.cancelled_at is null
        and f.id = v_request.fixture_id
        and exists (
          select 1
          from public.fixture_rink_assignments fra
          where fra.fixture_id = f.id
            and fra.member_profile_id = tsm.member_profile_id
            and fra.position = 201
        )
    ) into v_target_valid;

    v_result_detail := 'Marker assignment acceptance was updated';

  else
    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'unsupported_action_type', 'No response handler is installed for this action type',
      p_received_at
    );

    return jsonb_build_object('ok', false, 'status', 'unsupported_action_type');
  end if;

  if not v_target_valid then
    update public.email_action_requests
       set status = 'cancelled', updated_at = now()
     where id = v_request.id;

    insert into public.email_action_response_log(
      request_id, graph_message_id, sender_email, command,
      result_status, result_detail, received_at
    ) values (
      v_request.id, p_graph_message_id, v_sender, v_command,
      'selection_no_longer_active',
      case
        when v_request.action_type = 'marker_assignment'
          then 'The member is no longer the active named marker for this published fixture'
        else 'The player or member opponent is no longer actively selected for this published fixture'
      end,
      p_received_at
    );

    return jsonb_build_object(
      'ok', false,
      'status', 'selection_no_longer_active'
    );
  end if;

  v_acceptance := case v_command
    when 'ACCEPT' then 'accepted'::public.acceptance_status
    when 'DECLINE' then 'declined'::public.acceptance_status
  end;

  update public.team_selection_members
     set acceptance = v_acceptance,
         responded_at = p_received_at,
         acceptance_by = v_request.member_profile_id
   where id = v_request.target_record_id;

  update public.email_action_requests
     set status = 'responded',
         last_action = v_command,
         last_responded_at = p_received_at,
         last_sender_email = v_sender,
         last_graph_message_id = p_graph_message_id,
         updated_at = now()
   where id = v_request.id;

  insert into public.email_action_response_log(
    request_id, graph_message_id, sender_email, command,
    result_status, result_detail, received_at
  ) values (
    v_request.id, p_graph_message_id, v_sender, v_command,
    'processed', v_result_detail, p_received_at
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'processed',
    'action_type', v_request.action_type,
    'action', v_command,
    'fixture_id', v_request.fixture_id,
    'team_selection_member_id', v_request.target_record_id
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."apply_email_action_response"(p_response_code text, p_command text, p_sender_email text, p_response_token text, p_graph_message_id text, p_received_at timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."apply_email_action_response"(p_response_code text, p_command text, p_sender_email text, p_response_token text, p_graph_message_id text, p_received_at timestamp with time zone) TO "service_role";

CREATE OR REPLACE FUNCTION public.attach_publication_team_sheet(p_fixture_id uuid, p_team_selection_id uuid, p_expected_composition_version integer, p_attachment jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
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

  IF jsonb_typeof(p_attachment) IS DISTINCT FROM 'object'
     OR NULLIF(BTRIM(p_attachment->>'name'), '') IS NULL
     OR p_attachment->>'contentType' IS DISTINCT FROM 'application/pdf'
     OR NULLIF(BTRIM(p_attachment->>'contentBytes'), '') IS NULL
     OR NOT (p_attachment ? 'compositionVersion')
     OR (p_attachment->>'compositionVersion')::integer
        IS DISTINCT FROM v_actual_composition_version THEN
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
      'reserve_promoted',
      'fixture_message'
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
    AND (eq.event_type <> 'fixture_message' OR eq.payload->>'team_sheet_required' = 'true')
    AND eq.status IN ('pending', 'failed')
    AND eq.sent_at IS NULL
    AND eq.event_type IN (
      'team_published_player',
      'team_published_reserve',
      'team_published_captain',
      'team_published_vice',
      'fixture_selected',
      'reserve_promoted',
      'fixture_message'
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

REVOKE ALL ON FUNCTION "public"."attach_publication_team_sheet"(p_fixture_id uuid, p_team_selection_id uuid, p_expected_composition_version integer, p_attachment jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."attach_publication_team_sheet"(p_fixture_id uuid, p_team_selection_id uuid, p_expected_composition_version integer, p_attachment jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."attach_publication_team_sheet"(p_fixture_id uuid, p_team_selection_id uuid, p_expected_composition_version integer, p_attachment jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.audit_filter_options()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null or not exists(select 1 from public.app_superusers where user_id=auth.uid()) then raise exception 'Superuser access required'; end if;
 return jsonb_build_object(
 'actors',(select coalesce(jsonb_agg(x),'[]') from (select distinct actor_user_id,actor_name from public.audit_journal where actor_user_id is not null) x),
 'clubs',(select coalesce(jsonb_agg(x),'[]') from (select id,name from public.clubs order by name) x));
end $function$;

REVOKE ALL ON FUNCTION "public"."audit_filter_options"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."audit_filter_options"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."audit_filter_options"() TO "service_role";

CREATE OR REPLACE FUNCTION public.audit_member_import(p_actor uuid, p_club uuid, p_filename text, p_active boolean, p_run uuid DEFAULT NULL::uuid, p_summary jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare run_id uuid; actor_label text; club_label text; summary jsonb;
begin
 if not exists(select 1 from public.app_superusers where user_id=p_actor) and not exists(
   select 1 from public.club_memberships m join public.member_profiles p on p.id=m.member_profile_id
   where p.user_id=p_actor and m.club_id=p_club and m.is_active and m.role::text='admin'
 ) then raise exception 'Import administrator required'; end if;
 if p_run is null then
   insert into audit_private.import_runs(actor,club_id,filename,new_members_active)
   values(p_actor,p_club,left(p_filename,250),p_active) returning id into run_id;
 else
   update audit_private.import_runs set finished_at=now() where id=p_run and actor=p_actor and club_id=p_club and finished_at is null returning id into run_id;
   if run_id is null then raise exception 'Import audit run not found'; end if;
 end if;
 summary:=audit_private.pick(coalesce(p_summary,'{}'),array['created','linked','existing_memberships','errors','manual_review','total']);
 select concat_ws(' ',first_name,last_name) into actor_label from public.member_profiles where user_id=p_actor limit 1;
 select name into club_label from public.clubs where id=p_club;
 insert into public.audit_journal(actor_user_id,actor_name,origin,club_id,club_name,record_type,record_id,record_label,action,after_values,outcome)
 values(p_actor,coalesce(actor_label,p_actor::text),'import',p_club,club_label,'member_import',run_id::text,left(p_filename,250),
 case when p_run is null then 'started' else 'finished' end,
 summary||jsonb_build_object('new_members_active',p_active),case when p_run is null then 'started' when coalesce((summary->>'errors')::integer,0)>0 then 'completed with errors' else 'completed' end);
 return run_id;
end $function$;

REVOKE ALL ON FUNCTION "public"."audit_member_import"(p_actor uuid, p_club uuid, p_filename text, p_active boolean, p_run uuid, p_summary jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."audit_member_import"(p_actor uuid, p_club uuid, p_filename text, p_active boolean, p_run uuid, p_summary jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.can_manage_fixture(p_fixture_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
  select
    coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or exists (
      select 1
      from public.app_superusers su
      where su.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.fixtures f
      join public.club_memberships cm
        on cm.club_id = f.club_id
       and cm.member_profile_id = public.my_member_profile_id()
       and cm.is_active = true
       and lower(cm.role::text) <> 'guest'
      where f.id = p_fixture_id
        and (
          lower(cm.role::text) in ('admin', 'selector')
          or f.captain_member_profile_id = cm.member_profile_id
          or f.vice_captain_member_profile_id = cm.member_profile_id
        )
    );
$function$;

REVOKE ALL ON FUNCTION "public"."can_manage_fixture"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."can_manage_fixture"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."can_manage_fixture"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.can_manage_team_selection(p_fixture_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
  select public.can_manage_fixture(p_fixture_id)
      or exists (
        select 1
          from public.fixtures f
          join public.club_memberships cm
            on cm.club_id = f.club_id
           and cm.member_profile_id = public.my_member_profile_id()
         where f.id = p_fixture_id
           and cm.is_active = true
           and lower(cm.role::text) = 'captain'
      );
$function$;

REVOKE ALL ON FUNCTION "public"."can_manage_team_selection"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."can_manage_team_selection"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."can_manage_team_selection"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.can_read_member_profile(p_target_profile_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.club_memberships cm_me
    join public.club_memberships cm_other
      on cm_other.club_id = cm_me.club_id
    where cm_me.member_profile_id = public.my_member_profile_id_norls()
      and cm_other.member_profile_id = p_target_profile_id
      and cm_me.is_active = true
      and cm_other.is_active = true
  )
$function$;

REVOKE ALL ON FUNCTION "public"."can_read_member_profile"(p_target_profile_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."can_read_member_profile"(p_target_profile_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."can_read_member_profile"(p_target_profile_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."can_read_member_profile"(p_target_profile_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."can_read_member_profile"(p_target_profile_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.cancel_and_reschedule_fixture_safe(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_replacement_fixture_id uuid;
begin
  perform public.cancel_fixture_safe(
    p_fixture_id => p_fixture_id,
    p_reason => p_reason
  );

  v_replacement_fixture_id := public.reschedule_cancelled_fixture_safe(
    p_fixture_id => p_fixture_id,
    p_new_start_at => p_new_start_at,
    p_new_end_at => p_new_end_at
  );

  return v_replacement_fixture_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."cancel_and_reschedule_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone, p_reason text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."cancel_and_reschedule_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone, p_reason text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."cancel_and_reschedule_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone, p_reason text) TO "service_role";

CREATE OR REPLACE FUNCTION public.cancel_fixture_safe(p_fixture_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_club_id uuid;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_fixture_label text;
  v_home_away text;
  v_venue_name text;
  v_opponent_name text;
  v_team_selection_id uuid;
  v_is_admin boolean := false;
  v_is_super boolean := false;
  v_is_captain_or_vice boolean := false;
  v_count integer := 0;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  select
    f.club_id,
    f.start_at,
    f.end_at,
    coalesce(nullif(f.team_name, ''), nullif(ct.name, ''), 'Fixture'),
    case when f.is_home then 'Home' else 'Away' end,
    coalesce(v.name, ''),
    coalesce(ov.name, ''),
    (f.captain_member_profile_id = v_current_member
      or f.vice_captain_member_profile_id = v_current_member)
  into
    v_club_id,
    v_start_at,
    v_end_at,
    v_fixture_label,
    v_home_away,
    v_venue_name,
    v_opponent_name,
    v_is_captain_or_vice
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_current_member
      and cm.is_active = true
      and cm.role in ('admin', 'selector')
  ) into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  ) into v_is_super;

  if not public.can_manage_fixture(p_fixture_id) then
    raise exception 'You do not have permission to cancel this fixture.';
  end if;

  if exists (
    select 1
    from public.fixtures f
    where f.id = p_fixture_id
      and f.cancelled_at is not null
  ) then
    raise exception 'Fixture is already cancelled.';
  end if;

  select ts.id
  into v_team_selection_id
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc nulls last
  limit 1;

  --------------------------------------------------------------------
  -- Suppress undelivered operational communications for this fixture.
  -- Cancellation is a lifecycle event and is deliberately preserved.
  --------------------------------------------------------------------

  update public.email_queue eq
  set status = 'cancelled'
  where eq.fixture_id = p_fixture_id
    and eq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and eq.status in ('pending', 'failed')
    and eq.sent_at is null;

  update public.notification_queue nq
  set status = 'cancelled'
  where nq.fixture_id = p_fixture_id
    and nq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and nq.status = 'pending';

  update public.fixtures
  set
    cancelled_at = now(),
    cancelled_by_member_profile_id = v_current_member,
    cancellation_reason = nullif(btrim(p_reason), '')
  where id = p_fixture_id;

  insert into public.fixture_lifecycle_events (
    fixture_id,
    event_type,
    old_start_at,
    old_end_at,
    reason,
    created_by_member_profile_id
  )
  values (
    p_fixture_id,
    'cancelled',
    v_start_at,
    v_end_at,
    nullif(btrim(p_reason), ''),
    v_current_member
  );

  with recipients as (
    select f.captain_member_profile_id as member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.captain_member_profile_id is not null

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.vice_captain_member_profile_id is not null

    union

    select tsm.member_profile_id
    from public.team_selection_members tsm
    join public.team_selections ts on ts.id = tsm.team_selection_id
    where ts.fixture_id = p_fixture_id
      and tsm.member_profile_id is not null
      and coalesce(tsm.is_selected, false) = true

    union

    select frsvp.member_profile_id
    from public.fixture_rsvps frsvp
    where frsvp.fixture_id = p_fixture_id
      and frsvp.member_profile_id is not null
      and lower(coalesce(frsvp.status::text, '')) in ('yes', 'maybe')
  ),
  inserted as (
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'fixture_cancelled',
      v_current_member,
      r.member_profile_id,
      p_fixture_id,
      v_team_selection_id,
      jsonb_strip_nulls(
        jsonb_build_object(
          'fixture_label', v_fixture_label,
          'start_at', v_start_at,
          'end_at', v_end_at,
          'home_away', v_home_away,
          'venue_name', nullif(v_venue_name, ''),
          'opponent_name', nullif(v_opponent_name, ''),
          'reason', nullif(btrim(p_reason), '')
        )
      ),
      'pending'
    from recipients r
    where r.member_profile_id is not null
      and r.member_profile_id <> v_current_member
      and not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.target_member_profile_id = r.member_profile_id
          and nq.event_type = 'fixture_cancelled'
          and nq.status in ('pending', 'sent')
      )
    returning 1
  )
  select count(*) into v_count from inserted;

  return v_count;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."cancel_fixture_safe"(p_fixture_id uuid, p_reason text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."cancel_fixture_safe"(p_fixture_id uuid, p_reason text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."cancel_fixture_safe"(p_fixture_id uuid, p_reason text) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."cancel_fixture_safe"(p_fixture_id uuid, p_reason text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."cancel_fixture_safe"(p_fixture_id uuid, p_reason text) TO "service_role";

CREATE OR REPLACE FUNCTION public.check_green_area_rink_capacity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_green_rink_count integer;
  v_overlapping_rinks integer;
  v_maintenance_rinks integer;
begin
  if new.green_area_id is null then
    return new;
  end if;

  if new.rinks_required is null or new.rinks_required < 1 then
    raise exception 'Rinks required must be at least 1 when a green area is selected';
  end if;

  select ga.rink_count into v_green_rink_count
  from public.green_areas ga
  where ga.id = new.green_area_id;

  if v_green_rink_count is null then
    raise exception 'Selected green area was not found';
  end if;

  select coalesce(sum(f.rinks_required), 0)
    into v_overlapping_rinks
  from public.fixtures f
  where f.green_area_id = new.green_area_id
    and f.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
    and f.time_range && new.time_range;

  select count(distinct m.rink_number)::integer
    into v_maintenance_rinks
  from public.green_rink_maintenance m
  where m.green_area_id = new.green_area_id
    and m.status = 'active'
    and m.time_range && new.time_range;

  if v_overlapping_rinks + v_maintenance_rinks + new.rinks_required > v_green_rink_count then
    raise exception 'Not enough rinks available for this time slot on the selected green';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."check_green_area_rink_capacity"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."check_green_area_rink_capacity"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."check_green_area_rink_capacity"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."check_green_area_rink_capacity"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."check_green_area_rink_capacity"() TO "service_role";

CREATE OR REPLACE FUNCTION public.claim_member_invitation(p_id uuid, p_club uuid, p_caller uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  attempt public.member_invitation_attempts;
  previous_id uuid;
  previous_status text;
begin
  select * into attempt from public.member_invitation_attempts
    where id=p_id and club_id=p_club and created_by=p_caller for update;
  if not found or attempt.status <> 'pending' or attempt.created_at < now()-interval '24 hours' then
    return false;
  end if;
  -- Serialize all attempts for the same membership using its existing row.
  perform 1 from public.club_memberships
    where id=attempt.membership_id and club_id=p_club and is_active=true for update;
  if not found then return false; end if;
  select id,status into previous_id,previous_status
    from public.member_invitation_attempts where membership_id=attempt.membership_id
    and status in ('sending','sent','unknown');
  if previous_id is not null then
    if previous_status <> 'sent' or previous_id is distinct from attempt.previous_sent_id then
      return false;
    end if;
    update public.member_invitation_attempts set status='superseded',updated_at=now() where id=previous_id;
  elsif attempt.previous_sent_id is not null then
    return false;
  end if;
  update public.member_invitation_attempts set status='sending',updated_at=now() where id=p_id;
  return true;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."claim_member_invitation"(p_id uuid, p_club uuid, p_caller uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."claim_member_invitation"(p_id uuid, p_club uuid, p_caller uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.claim_written_selection_reply(p_mailbox text, p_internet_message_id text, p_graph_message_id text, p_received_at timestamp with time zone, p_response_code text, p_sender_email text, p_original_subject text, p_excerpt text, p_response_token_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  cfg public.email_written_reply_settings%rowtype;
  r public.email_action_requests%rowtype;
  reply_id uuid;
  reviewer_ids uuid[];
  claimed uuid;
  member_name text;
begin
  select * into cfg from public.email_written_reply_settings where mailbox=p_mailbox;
  if not found or not cfg.enabled or p_received_at is null or p_received_at < cfg.enabled_at
    or p_received_at > now()+interval '5 minutes' or coalesce(p_internet_message_id,'')='' or coalesce(p_graph_message_id,'')=''
    or coalesce(p_excerpt,'')='' then return jsonb_build_object('status','ignored'); end if;
  -- Sender allowlist keeps staging tests from contacting real members.
  if not (lower(btrim(p_sender_email))=any(cfg.reminder_recipients)) then
    return jsonb_build_object('status','recipient_not_enabled');
  end if;
  select * into r from public.email_action_requests
  where response_code_hash=encode(extensions.digest(upper(btrim(p_response_code)),'sha256'),'hex')
    and lower(btrim(recipient_email))=lower(btrim(p_sender_email))
    and status='pending' and expires_at>now() and created_at<=p_received_at
  for update;
  if not found then return jsonb_build_object('status','no_current_request'); end if;
  if not ('ACCEPT'=any(r.allowed_actions) and 'DECLINE'=any(r.allowed_actions)) or
    (r.response_protocol_version=2 and (r.response_token_hash is null or p_response_token_hash is null or
      p_response_token_hash !~ '^[0-9a-f]{64}$' or p_response_token_hash<>r.response_token_hash)) or
    (r.response_protocol_version=1 and p_response_token_hash is not null) or r.response_protocol_version not in (1,2)
  then return jsonb_build_object('status','invalid_response_credentials'); end if;
  if not exists (
    select 1 from public.team_selection_members m
    join public.team_selections s on s.id=m.team_selection_id
    join public.fixtures f on f.id=s.fixture_id
    join public.email_queue q on q.id=r.source_email_queue_id
    where m.id=r.target_record_id and m.member_profile_id=r.member_profile_id
      and m.is_selected and m.acceptance='pending' and s.status='published'
      and s.id=r.team_selection_id and f.id=r.fixture_id and f.club_id=r.club_id
      and f.cancelled_at is null and f.archived_at is null and f.start_at>now()
      and q.status='sent' and q.subject=p_original_subject and q.sent_at<=p_received_at
      and lower(btrim(q.recipient_email))=lower(btrim(p_sender_email))
      and exists (
        select 1 from public.fixture_rink_assignments a
        join public.fixture_rinks fr on fr.id=a.fixture_rink_id and fr.fixture_id=f.id
        where a.fixture_id=f.id and a.member_profile_id=m.member_profile_id
          and ((r.action_type='marker_assignment' and m.role::text='marker' and a.position=201)
            or (r.action_type='team_selection' and m.role::text in ('player','opponent')
              and (a.position between 1 and fr.players_per_rink or a.position between 101 and 100+fr.players_per_rink)))
      )
  ) then return jsonb_build_object('status','selection_not_pending'); end if;
  select array_agg(distinct cm.member_profile_id) into reviewer_ids
  from public.club_memberships cm
  join public.fixtures f on f.club_id=cm.club_id and f.id=r.fixture_id
  join public.team_selections s on s.id=r.team_selection_id
  where cm.is_active
    and (not exists(select 1 from public.email_queue q where q.id=r.source_email_queue_id
      and q.payload->>'written_reply_test'='true') or cm.member_profile_id=r.member_profile_id)
    and (cm.member_profile_id=any(array[
    f.captain_member_profile_id,f.vice_captain_member_profile_id,
    s.captain_member_profile_id,s.vice_captain_member_profile_id,s.published_by_member_profile_id
  ]) or cm.role::text='admin');
  if coalesce(cardinality(reviewer_ids),0)=0 then return jsonb_build_object('status','no_reviewer'); end if;
  insert into public.email_written_replies(mailbox,internet_message_id,graph_message_id,request_id,received_at)
  values(p_mailbox,p_internet_message_id,p_graph_message_id,r.id,p_received_at)
  on conflict(mailbox,internet_message_id) do nothing returning id into reply_id;
  if reply_id is null then return jsonb_build_object('status','duplicate'); end if;
  select coalesce(nullif(display_name,''),'A selected member') into member_name from public.member_profiles where id=r.member_profile_id;
  insert into public.app_notifications(member_profile_id,type,title,body,data,fixture_id,team_selection_id)
  select reviewer,'selection_written_reply','Written selection reply needs review',
    member_name || ' sent a written reply. Their selection response is still pending.' || E'\n\n' ||
    left(regexp_replace(p_excerpt,'(BWL-[A-Fa-f0-9]{12}|RSP-[A-Fa-f0-9]{48})','[response reference]','g'),1500),
    jsonb_build_object('fixture_id',r.fixture_id,'team_selection_id',r.team_selection_id,'written_reply_id',reply_id),r.fixture_id,r.team_selection_id
  from unnest(reviewer_ids) reviewer;
  -- Atomic one-time claim; delivery failures are reviewed, never blindly resent.
  insert into public.email_written_reply_reminders(target_record_id,reply_id)
  values(r.target_record_id,reply_id) on conflict(target_record_id) do nothing returning target_record_id into claimed;
  return jsonb_build_object('status','recorded','send_reminder',claimed is not null,'reply_id',reply_id,'recipient',r.recipient_email,'response_protocol_version',r.response_protocol_version);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."claim_written_selection_reply"(p_mailbox text, p_internet_message_id text, p_graph_message_id text, p_received_at timestamp with time zone, p_response_code text, p_sender_email text, p_original_subject text, p_excerpt text, p_response_token_hash text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."claim_written_selection_reply"(p_mailbox text, p_internet_message_id text, p_graph_message_id text, p_received_at timestamp with time zone, p_response_code text, p_sender_email text, p_original_subject text, p_excerpt text, p_response_token_hash text) TO "service_role";

CREATE OR REPLACE FUNCTION public.communications_fixture_manager_status(p_fixture_id uuid)
 RETURNS TABLE(status text, next_action text, message text, progress integer, can_repair boolean, can_prepare boolean, can_send boolean, can_retry boolean, blocking_issues jsonb, diagnostics jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_member_profile_id uuid;
  v_club_id uuid;
  v_captain_id uuid;
  v_vice_captain_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  select
    f.club_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_club_id,
    v_captain_id,
    v_vice_captain_id
  from public.fixtures f
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found.', p_fixture_id;
  end if;

  v_member_profile_id := public.my_member_profile_id();

  if public.can_manage_fixture(p_fixture_id) is not true then
    raise exception 'Fixture manager access required.';
  end if;

  return query
  select *
  from public.communications_fixture_status(p_fixture_id);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."communications_fixture_manager_status"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."communications_fixture_manager_status"(p_fixture_id uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."communications_fixture_manager_status"(p_fixture_id uuid) TO "authenticated";

CREATE OR REPLACE FUNCTION public.communications_health_check(p_fixture_id uuid)
 RETURNS TABLE(item text, expected integer, actual integer, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team_selection_id uuid;
  v_selection_mode text := '';
  v_is_rescheduled boolean := false;
  v_source_fixture_id uuid;
begin
  select
    ts.id,
    lower(coalesce(ct.selection_mode::text, '')),
    f.rescheduled_from_fixture_id is not null,
    f.rescheduled_from_fixture_id
  into
    v_team_selection_id,
    v_selection_mode,
    v_is_rescheduled,
    v_source_fixture_id
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found', p_fixture_id;
  end if;

  if v_team_selection_id is null then
    raise exception 'No team selection found for fixture %', p_fixture_id;
  end if;

  if v_is_rescheduled then
    return query
    with
    managers as (
      select f.captain_member_profile_id as member_profile_id
      from public.fixtures f
      where f.id = p_fixture_id
        and f.captain_member_profile_id is not null

      union

      select f.vice_captain_member_profile_id
      from public.fixtures f
      where f.id = p_fixture_id
        and f.vice_captain_member_profile_id is not null
    ),
    selected_members as (
      select distinct tsm.member_profile_id
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id is not null
        and coalesce(tsm.is_selected, false) = true
        and not exists (
          select 1
          from managers m
          where m.member_profile_id = tsm.member_profile_id
        )
    ),
    eligible_team_members as (
      select distinct tm.member_profile_id
      from public.fixtures f
      join public.team_members tm
        on tm.team_id = f.team_id
       and tm.is_active = true
      where f.id = p_fixture_id
        and f.team_id is not null
    ),
    eligible_rsvp_members as (
      select distinct fr.member_profile_id
      from public.fixtures f
      join public.fixture_rsvps fr
        on fr.fixture_id = v_source_fixture_id
      join public.club_memberships cm
        on cm.club_id = f.club_id
       and cm.member_profile_id = fr.member_profile_id
       and cm.is_active = true
      where f.id = p_fixture_id
        and f.team_id is null
        and fr.status::text in ('yes', 'maybe')
    ),
    availability_members as (
      select member_profile_id from eligible_team_members
      union
      select member_profile_id from eligible_rsvp_members
    ),
    intended_recipients as (
      select
        m.member_profile_id,
        'manager'::text as precedence_kind
      from managers m

      union all

      select
        s.member_profile_id,
        'selected'::text
      from selected_members s

      union all

      select
        a.member_profile_id,
        'availability'::text
      from availability_members a
      where not exists (
        select 1 from managers m
        where m.member_profile_id = a.member_profile_id
      )
      and not exists (
        select 1 from selected_members s
        where s.member_profile_id = a.member_profile_id
      )
    ),
    classified_recipients as (
      select
        ir.member_profile_id,
        case
          when exists (
            select 1
            from public.fixture_rink_assignments fra
            where fra.fixture_id = p_fixture_id
              and fra.member_profile_id = ir.member_profile_id
              and fra.position = 201
          ) then 'marker'
          when exists (
            select 1
            from public.fixture_rink_assignments fra
            join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
            where fra.fixture_id = p_fixture_id
              and fra.member_profile_id = ir.member_profile_id
              and fra.position between 101 and (100 + fr.players_per_rink)
          ) then 'opponent'
          when exists (
            select 1
            from public.fixture_rink_assignments fra
            join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
            where fra.fixture_id = p_fixture_id
              and fra.member_profile_id = ir.member_profile_id
              and fra.position between 1 and fr.players_per_rink
          ) then 'player'
          when exists (
            select 1
            from public.team_selection_members tsm
            where tsm.team_selection_id = v_team_selection_id
              and tsm.member_profile_id = ir.member_profile_id
              and coalesce(tsm.is_selected, false) = true
              and lower(tsm.role::text) = 'reserve'
          ) then 'reserve'
          when ir.precedence_kind = 'manager' then 'captain'
          else 'not_selected'
        end as recipient_kind
      from intended_recipients ir
    ),
    delivery_status as (
      select
        cr.member_profile_id,
        cr.recipient_kind,
        nullif(btrim(mp.email_address), '') as email_address,
        exists (
          select 1
          from public.notification_queue nq
          where nq.fixture_id = p_fixture_id
            and nq.team_selection_id = v_team_selection_id
            and nq.target_member_profile_id = cr.member_profile_id
            and nq.status <> 'cancelled'
            and (
              nq.event_type in (
                'fixture_rescheduled_manager',
                'fixture_rescheduled_selected',
                'fixture_rescheduled_availability'
              )
              or (cr.recipient_kind in ('player', 'opponent', 'marker')
                  and nq.event_type = 'fixture_selected')
              or (cr.recipient_kind = 'player'
                  and nq.event_type = 'team_published_player')
              or (cr.recipient_kind = 'reserve'
                  and nq.event_type = 'team_published_reserve')
              or (cr.recipient_kind = 'captain'
                  and nq.event_type in ('team_published_captain', 'team_published_vice'))
              or (cr.recipient_kind = 'not_selected'
                  and nq.event_type in (
                    'team_published_not_selected',
                    'team_published_incomplete_request'
                  ))
            )
        ) as queue_exists,
        exists (
          select 1
          from public.app_notifications an
          where an.fixture_id = p_fixture_id
            and an.team_selection_id = v_team_selection_id
            and an.member_profile_id = cr.member_profile_id
            and (
              an.type in (
                'fixture_rescheduled_manager',
                'fixture_rescheduled_selected',
                'fixture_rescheduled_availability'
              )
              or (cr.recipient_kind in ('player', 'opponent', 'marker')
                  and an.type = 'fixture_selected')
              or (cr.recipient_kind = 'player'
                  and an.type = 'team_published_player')
              or (cr.recipient_kind = 'reserve'
                  and an.type = 'team_published_reserve')
              or (cr.recipient_kind = 'captain'
                  and an.type in ('team_published_captain', 'team_published_vice'))
              or (cr.recipient_kind = 'not_selected'
                  and an.type in (
                    'team_published_not_selected',
                    'team_published_incomplete_request'
                  ))
            )
        ) as app_exists,
        exists (
          select 1
          from public.email_queue eq
          where eq.fixture_id = p_fixture_id
            and eq.team_selection_id = v_team_selection_id
            and eq.member_profile_id = cr.member_profile_id
            and eq.status <> 'cancelled'
            and (
              eq.event_type in (
                'fixture_rescheduled_manager',
                'fixture_rescheduled_selected',
                'fixture_rescheduled_availability'
              )
              or (cr.recipient_kind in ('player', 'opponent', 'marker')
                  and eq.event_type = 'fixture_selected')
              or (cr.recipient_kind = 'player'
                  and eq.event_type = 'team_published_player')
              or (cr.recipient_kind = 'reserve'
                  and eq.event_type = 'team_published_reserve')
              or (cr.recipient_kind = 'captain'
                  and eq.event_type in ('team_published_captain', 'team_published_vice'))
              or (cr.recipient_kind = 'not_selected'
                  and eq.event_type in (
                    'team_published_not_selected',
                    'team_published_incomplete_request'
                  ))
            )
        ) as email_exists,
        exists (
          select 1
          from public.email_queue eq
          where eq.fixture_id = p_fixture_id
            and eq.team_selection_id = v_team_selection_id
            and eq.member_profile_id = cr.member_profile_id
            and eq.status = 'sent'
            and eq.event_type in (
              'fixture_rescheduled_manager',
              'fixture_rescheduled_selected',
              'fixture_rescheduled_availability',
              'fixture_selected',
              'team_published_player',
              'team_published_reserve',
              'team_published_captain',
              'team_published_vice',
              'team_published_not_selected',
              'team_published_incomplete_request'
            )
        ) as email_sent,
        exists (
          select 1
          from public.email_queue eq
          where eq.fixture_id = p_fixture_id
            and eq.team_selection_id = v_team_selection_id
            and eq.member_profile_id = cr.member_profile_id
            and eq.status = 'failed'
            and eq.event_type in (
              'fixture_rescheduled_manager',
              'fixture_rescheduled_selected',
              'fixture_rescheduled_availability',
              'fixture_selected',
              'team_published_player',
              'team_published_reserve',
              'team_published_captain',
              'team_published_vice',
              'team_published_not_selected',
              'team_published_incomplete_request'
            )
        ) as email_failed
      from classified_recipients cr
      join public.member_profiles mp on mp.id = cr.member_profile_id
    ),
    counts as (
      select
        count(*) filter (where recipient_kind = 'player')::integer as players_expected,
        count(*) filter (where recipient_kind = 'player' and queue_exists)::integer as players_actual,
        count(*) filter (where recipient_kind = 'opponent')::integer as opponents_expected,
        count(*) filter (where recipient_kind = 'opponent' and queue_exists)::integer as opponents_actual,
        count(*) filter (where recipient_kind = 'marker')::integer as markers_expected,
        count(*) filter (where recipient_kind = 'marker' and queue_exists)::integer as markers_actual,
        count(*) filter (where recipient_kind = 'reserve')::integer as reserves_expected,
        count(*) filter (where recipient_kind = 'reserve' and queue_exists)::integer as reserves_actual,
        count(*) filter (where recipient_kind = 'captain')::integer as captains_expected,
        count(*) filter (where recipient_kind = 'captain' and queue_exists)::integer as captains_actual,
        count(*) filter (where recipient_kind = 'not_selected')::integer as not_selected_expected,
        count(*) filter (where recipient_kind = 'not_selected' and queue_exists)::integer as not_selected_actual,
        count(*)::integer as notifications_expected,
        count(*) filter (where queue_exists)::integer as notifications_actual,
        count(*)::integer as app_expected,
        count(*) filter (where app_exists)::integer as app_actual,
        count(*) filter (where email_address is not null)::integer as emails_expected,
        count(*) filter (where email_address is not null and email_exists)::integer as emails_actual,
        count(*) filter (where email_address is not null and email_sent)::integer as emails_sent_actual,
        count(*) filter (where email_address is not null and email_failed)::integer as emails_failed_actual
      from delivery_status
    ),
    rows as (
      select 1 sort_order, 'Playing players'::text item,
        players_expected expected, players_actual actual from counts
      union all select 2, 'Opponents', opponents_expected, opponents_actual from counts
      union all select 3, 'Named markers', markers_expected, markers_actual from counts
      union all select 4, 'Marker volunteers', 0, 0
      union all select 5, 'Reserves', reserves_expected, reserves_actual from counts
      union all select 6, 'Captain/Vice copies', captains_expected, captains_actual from counts
      union all select 7, 'Not selected', not_selected_expected, not_selected_actual from counts
      union all select 8, 'Notifications queued', notifications_expected, notifications_actual from counts
      union all select 9, 'App notifications created', app_expected, app_actual from counts
      union all select 10, 'Emails queued', emails_expected, emails_actual from counts
      union all select 11, 'Emails sent', emails_expected, emails_sent_actual from counts
      union all select 12, 'Emails failed', 0, emails_failed_actual from counts
      union all select 13, 'Team sheets required', 0, 0
      union all select 14, 'Team sheets attached', 0, 0
      union all select 15, 'Team sheets sent', 0, 0
    )
    select
      rows.item,
      rows.expected,
      rows.actual,
      case
        when rows.item = 'Emails failed'
          then case when rows.actual = 0 then 'OK' else 'CHECK' end
        when rows.actual >= rows.expected then 'OK'
        else 'CHECK'
      end
    from rows
    order by rows.sort_order;

    return;
  end if;

  if v_selection_mode = 'preselect' then
    return query
    with
    current_assignments as (
      select distinct
        fra.member_profile_id,
        fr.fixture_rink_no as team_no,
        fra.position,
        case
          when fra.position = 201 then 'marker'
          when fra.position between 101 and (100 + fr.players_per_rink)
            then 'opponent'
          else 'player'
        end as recipient_kind
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id is not null
        and (
          fra.position between 1 and fr.players_per_rink
          or fra.position between 101 and (100 + fr.players_per_rink)
          or fra.position = 201
        )
    ),
    open_marker_requests as (
      select
        mr.id as marker_request_id,
        mr.requested_at,
        fr.fixture_rink_no as team_no,
        vt.mailing_list_id
      from public.fixture_marker_requests mr
      join public.fixture_rinks fr
        on fr.id = mr.fixture_rink_id
      join public.fixtures f
        on f.id = fr.fixture_id
      join public.volunteer_tasks vt
        on vt.club_id = f.club_id
       and vt.task_code = 'marker'
       and vt.is_active = true
      join public.mailing_lists ml
        on ml.id = vt.mailing_list_id
       and ml.club_id = vt.club_id
       and ml.is_active = true
      where fr.fixture_id = p_fixture_id
        and mr.status = 'open'
    ),
    current_marker_recipients as (
      select distinct
        omr.marker_request_id,
        omr.requested_at,
        omr.team_no,
        mlm.member_profile_id
      from open_marker_requests omr
      join public.mailing_list_members mlm
        on mlm.mailing_list_id = omr.mailing_list_id
       and mlm.is_active = true
      join public.mailing_lists ml
        on ml.id = mlm.mailing_list_id
      join public.club_memberships cm
        on cm.club_id = ml.club_id
       and cm.member_profile_id = mlm.member_profile_id
       and cm.is_active = true
       and lower(cm.role::text) <> 'guest'
    ),
    expected_deliveries as (
      select
        'fixture_selected'::text as event_type,
        ca.recipient_kind,
        ca.member_profile_id,
        ca.team_no,
        ca.position,
        null::uuid as marker_request_id,
        null::timestamptz as request_started_at
      from current_assignments ca

      union all

      select
        'marker_request_opened'::text,
        'marker_volunteer'::text,
        cmr.member_profile_id,
        cmr.team_no,
        null::integer,
        cmr.marker_request_id,
        cmr.requested_at
      from current_marker_recipients cmr
    ),
    delivery_status as (
      select
        ed.*,
        nullif(btrim(mp.email_address), '') as email_address,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.notification_queue nq
            where nq.fixture_id = p_fixture_id
              and nq.team_selection_id = v_team_selection_id
              and nq.event_type = 'fixture_selected'
              and nq.target_member_profile_id = ed.member_profile_id
              and nq.status <> 'cancelled'
              and (
                nullif(nq.payload ->> 'position', '') is null
                or nq.payload ->> 'position' = ed.position::text
              )
              and (
                nullif(nq.payload ->> 'team_no', '') is null
                or nq.payload ->> 'team_no' = ed.team_no::text
              )
          )
          else exists (
            select 1
            from public.notification_queue nq
            where nq.fixture_id = p_fixture_id
              and nq.event_type = 'marker_request_opened'
              and nq.target_member_profile_id = ed.member_profile_id
              and nq.status <> 'cancelled'
              and nq.payload ->> 'marker_request_id'
                    = ed.marker_request_id::text
          )
        end as queue_exists,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.app_notifications an
            where an.fixture_id = p_fixture_id
              and an.team_selection_id = v_team_selection_id
              and an.type = 'fixture_selected'
              and an.member_profile_id = ed.member_profile_id
          )
          else exists (
            select 1
            from public.app_notifications an
            where an.fixture_id = p_fixture_id
              and an.type = 'marker_request_opened'
              and an.member_profile_id = ed.member_profile_id
              and an.data ->> 'marker_request_id'
                    = ed.marker_request_id::text
          )
        end as app_exists,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.event_type = 'fixture_selected'
              and eq.member_profile_id = ed.member_profile_id
              and eq.status <> 'cancelled'
          )
          else exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.event_type = 'marker_request_opened'
              and eq.member_profile_id = ed.member_profile_id
              and eq.status <> 'cancelled'
              and eq.created_at >= ed.request_started_at
          )
        end as email_exists,

        case
          when ed.event_type = 'fixture_selected' then exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.event_type = 'fixture_selected'
              and eq.member_profile_id = ed.member_profile_id
              and eq.status = 'sent'
          )
          else exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.event_type = 'marker_request_opened'
              and eq.member_profile_id = ed.member_profile_id
              and eq.created_at >= ed.request_started_at
              and eq.status = 'sent'
          )
        end as email_sent,

        case
          when ed.event_type = 'fixture_selected' then coalesce((
            select eq.status = 'failed'
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.event_type = 'fixture_selected'
              and eq.member_profile_id = ed.member_profile_id
            order by eq.created_at desc
            limit 1
          ), false)
          else coalesce((
            select eq.status = 'failed'
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.event_type = 'marker_request_opened'
              and eq.member_profile_id = ed.member_profile_id
              and eq.created_at >= ed.request_started_at
            order by eq.created_at desc
            limit 1
          ), false)
        end as latest_email_failed
      from expected_deliveries ed
      join public.member_profiles mp
        on mp.id = ed.member_profile_id
    ),
    counts as (
      select
        count(*) filter (
          where recipient_kind = 'player'
        )::integer as players_expected,
        count(*) filter (
          where recipient_kind = 'player'
            and queue_exists
        )::integer as players_actual,

        count(*) filter (
          where recipient_kind = 'opponent'
        )::integer as opponents_expected,
        count(*) filter (
          where recipient_kind = 'opponent'
            and queue_exists
        )::integer as opponents_actual,

        count(*) filter (
          where recipient_kind = 'marker'
        )::integer as named_markers_expected,
        count(*) filter (
          where recipient_kind = 'marker'
            and queue_exists
        )::integer as named_markers_actual,

        count(*) filter (
          where recipient_kind = 'marker_volunteer'
        )::integer as marker_volunteers_expected,
        count(*) filter (
          where recipient_kind = 'marker_volunteer'
            and queue_exists
        )::integer as marker_volunteers_actual,

        count(*)::integer as notifications_expected,
        count(*) filter (
          where queue_exists
        )::integer as notifications_actual,

        count(*)::integer as app_expected,
        count(*) filter (
          where app_exists
        )::integer as app_actual,

        count(*) filter (
          where email_address is not null
        )::integer as emails_expected,
        count(*) filter (
          where email_address is not null
            and email_exists
        )::integer as emails_actual,

        count(*) filter (
          where email_address is not null
            and email_sent
        )::integer as emails_sent_actual,

        count(*) filter (
          where email_address is not null
            and latest_email_failed
        )::integer as emails_failed_actual
      from delivery_status
    ),
    rows as (
      select
        1 as sort_order,
        'Playing players'::text as item,
        players_expected as expected,
        players_actual as actual
      from counts

      union all
      select 2, 'Opponents', opponents_expected, opponents_actual
      from counts

      union all
      select 3, 'Named markers', named_markers_expected, named_markers_actual
      from counts

      union all
      select 4, 'Marker volunteers',
        marker_volunteers_expected, marker_volunteers_actual
      from counts

      union all
      select 5, 'Reserves', 0, 0

      union all
      select 6, 'Captain/Vice copies', 0, 0

      union all
      select 7, 'Not selected', 0, 0

      union all
      select 8, 'Notifications queued',
        notifications_expected, notifications_actual
      from counts

      union all
      select 9, 'App notifications created',
        app_expected, app_actual
      from counts

      union all
      select 10, 'Emails queued',
        emails_expected, emails_actual
      from counts

      union all
      select 11, 'Emails sent',
        emails_expected, emails_sent_actual
      from counts

      union all
      select 12, 'Emails failed',
        0, emails_failed_actual
      from counts

      union all
      select 13, 'Team sheets required', 0, 0

      union all
      select 14, 'Team sheets attached', 0, 0

      union all
      select 15, 'Team sheets sent', 0, 0
    )
    select
      rows.item,
      rows.expected,
      rows.actual,
      case
        when rows.item = 'Emails failed'
          then case when rows.actual = 0 then 'OK' else 'CHECK' end
        when rows.actual >= rows.expected
          then 'OK'
        else 'CHECK'
      end as status
    from rows
    order by rows.sort_order;

    return;
  end if;

  -- Existing published-team behaviour for all non-Pre-Select fixtures.
  return query
  with
  assigned as (
    select distinct fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
  ),
  reserves as (
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_team_selection_id
      and tsm.is_selected = true
      and tsm.role = 'reserve'::selection_member_role
  ),
  captains as (
    select distinct x.member_profile_id
    from public.fixtures f
    cross join lateral (
      values
        (f.captain_member_profile_id),
        (f.vice_captain_member_profile_id)
    ) x(member_profile_id)
    where f.id = p_fixture_id
      and x.member_profile_id is not null
  ),
  selected_people as (
    select member_profile_id from assigned
    union
    select member_profile_id from reserves
    union
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_team_selection_id
      and tsm.is_selected = true
      and tsm.role = 'player'::selection_member_role
  ),
  team_pool as (
    select tm.member_profile_id
    from public.fixtures f
    join public.team_members tm
      on tm.team_id = f.team_id
    where f.id = p_fixture_id
      and coalesce(tm.is_active, true) = true
  ),
  not_selected as (
    select member_profile_id from team_pool
    except
    select member_profile_id from selected_people
  ),
  expected_counts as (
    select
      (select count(*) from assigned)::integer as players,
      (select count(*) from reserves)::integer as reserves,
      (select count(*) from captains)::integer as captains,
      (select count(*) from not_selected)::integer as not_selected
  ),
  totals as (
    select
      players,
      reserves,
      captains,
      not_selected,
      players + reserves + captains + not_selected as total_comms,
      players + reserves + captains as team_sheet_comms
    from expected_counts
  ),
  rows as (
    select
      1 as sort_order,
      'Playing players'::text as item,
      players as expected,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type = 'team_published_player'
          and nq.status <> 'cancelled'
      ) as actual
    from totals

    union all
    select 2, 'Reserves', reserves,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type = 'team_published_reserve'
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 3, 'Captain/Vice copies', captains,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type in (
            'team_published_captain',
            'team_published_vice'
          )
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 4, 'Not selected', not_selected,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type in (
            'team_published_not_selected',
            'team_published_incomplete_request'
          )
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 5, 'Notifications queued', total_comms,
      (
        select count(*)::integer
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type like 'team_published%'
          and nq.status <> 'cancelled'
      )
    from totals

    union all
    select 6, 'App notifications created', total_comms,
      (
        select count(*)::integer
        from public.app_notifications an
        where an.fixture_id = p_fixture_id
          and an.team_selection_id = v_team_selection_id
          and an.type like 'team_published%'
      )
    from totals

    union all
    select 7, 'Emails queued', total_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type like 'team_published%'
          and eq.status <> 'cancelled'
      )
    from totals

    union all
    select 8, 'Emails sent', total_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type like 'team_published%'
          and eq.status = 'sent'
      )
    from totals

    union all
    select 9, 'Emails failed', 0,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type like 'team_published%'
          and eq.status = 'failed'
      )
    from totals

    union all
    select 10, 'Team sheets required', team_sheet_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type in (
            'team_published_player',
            'team_published_reserve',
            'team_published_captain',
            'team_published_vice'
          )
          and eq.status <> 'cancelled'
      )
    from totals

    union all
    select 11, 'Team sheets attached', team_sheet_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type in (
            'team_published_player',
            'team_published_reserve',
            'team_published_captain',
            'team_published_vice'
          )
          and eq.status <> 'cancelled'
          and jsonb_array_length(
            coalesce(eq.attachments, '[]'::jsonb)
          ) > 0
      )
    from totals

    union all
    select 12, 'Team sheets sent', team_sheet_comms,
      (
        select count(*)::integer
        from public.email_queue eq
        where eq.fixture_id = p_fixture_id
          and eq.team_selection_id = v_team_selection_id
          and eq.event_type in (
            'team_published_player',
            'team_published_reserve',
            'team_published_captain',
            'team_published_vice'
          )
          and eq.status = 'sent'
          and jsonb_array_length(
            coalesce(eq.attachments, '[]'::jsonb)
          ) > 0
      )
    from totals
  )
  select
    rows.item,
    rows.expected,
    rows.actual,
    case
      when rows.expected = rows.actual then 'OK'
      else 'CHECK'
    end as status
  from rows
  order by rows.sort_order;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."communications_health_check"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."communications_health_check"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.communications_health_check_v2(p_fixture_id uuid)
 RETURNS TABLE(item text, expected integer, actual integer, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
begin
  perform public.communications_require_superuser();

  return query
  with detail as materialized (
    select * from public.communications_health_detail_v2(p_fixture_id)
  ),
  rows as (
    select 1 sort_order, 'Playing players'::text item,
      count(*) filter (where category = 'Player')::integer expected,
      count(*) filter (where category = 'Player' and app_notification = 'Created')::integer actual
    from detail
    union all select 2, 'Opponents',
      count(*) filter (where category = 'Opponent')::integer,
      count(*) filter (where category = 'Opponent' and app_notification = 'Created')::integer from detail
    union all select 3, 'Named markers',
      count(*) filter (where category = 'Named Marker')::integer,
      count(*) filter (where category = 'Named Marker' and app_notification = 'Created')::integer from detail
    union all select 4, 'Marker volunteers',
      count(*) filter (where category like 'Marker Volunteer%')::integer,
      count(*) filter (where category like 'Marker Volunteer%' and app_notification = 'Created')::integer from detail
    union all select 5, 'Reserves',
      count(*) filter (where category = 'Reserve')::integer,
      count(*) filter (where category = 'Reserve' and app_notification = 'Created')::integer from detail
    union all select 6, 'Captain/Vice copies',
      count(*) filter (where category in ('Captain','Vice Captain'))::integer,
      count(*) filter (where category in ('Captain','Vice Captain') and app_notification = 'Created')::integer from detail
    union all select 7, 'Not selected',
      count(*) filter (where category = 'Not Selected')::integer,
      count(*) filter (where category = 'Not Selected' and app_notification = 'Created')::integer from detail
    union all select 8, 'App notifications created',
      count(*)::integer,
      count(*) filter (where app_notification = 'Created')::integer from detail
    union all select 9, 'Emails queued',
      count(*) filter (where email_status <> 'No Email')::integer,
      count(*) filter (where email_status not in ('No Email','Missing'))::integer from detail
    union all select 10, 'Emails sent',
      count(*) filter (where email_status <> 'No Email')::integer,
      count(*) filter (where email_status = 'sent')::integer from detail
    union all select 11, 'Emails failed', 0,
      count(*) filter (where email_status = 'failed')::integer from detail
    union all select 12, 'Team sheets required',
      count(*) filter (where team_sheet <> 'Not Required')::integer,
      count(*) filter (where team_sheet <> 'Not Required')::integer from detail
    union all select 13, 'Team sheets attached',
      count(*) filter (where team_sheet <> 'Not Required')::integer,
      count(*) filter (where team_sheet = 'Attached')::integer from detail
    union all select 14, 'Team sheets sent',
      count(*) filter (where team_sheet <> 'Not Required' and email_status <> 'No Email')::integer,
      count(*) filter (where team_sheet = 'Attached' and email_status = 'sent')::integer from detail
  )
  select rows.item, rows.expected, rows.actual,
    case when rows.item = 'Emails failed'
      then case when rows.actual = 0 then 'OK' else 'CHECK' end
      when rows.actual >= rows.expected then 'OK' else 'CHECK' end
  from rows order by rows.sort_order;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."communications_health_check_v2"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."communications_health_check_v2"(p_fixture_id uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."communications_health_check_v2"(p_fixture_id uuid) TO "authenticated";

CREATE OR REPLACE FUNCTION public.communications_health_detail(p_fixture_id uuid)
 RETURNS TABLE(member_profile_id uuid, member_name text, category text, app_notification text, email_status text, team_sheet text, email_address text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team_selection_id uuid;
  v_selection_mode text := '';
begin
  select
    ts.id,
    lower(coalesce(ct.selection_mode::text, ''))
  into
    v_team_selection_id,
    v_selection_mode
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found', p_fixture_id;
  end if;

  if v_team_selection_id is null then
    raise exception 'No team selection found for fixture %', p_fixture_id;
  end if;

  if v_selection_mode = 'preselect' then
    return query
    with
    current_assignments as (
      select distinct
        fra.member_profile_id,
        fr.fixture_rink_no as team_no,
        fra.position,
        case
          when fra.position = 201 then 'Named Marker'
          when fra.position between 101 and (100 + fr.players_per_rink)
            then 'Opponent'
          else 'Player'
        end as category
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id is not null
        and (
          fra.position between 1 and fr.players_per_rink
          or fra.position between 101 and (100 + fr.players_per_rink)
          or fra.position = 201
        )
    ),
    open_marker_requests as (
      select
        mr.id as marker_request_id,
        mr.requested_at,
        fr.fixture_rink_no as team_no,
        vt.mailing_list_id
      from public.fixture_marker_requests mr
      join public.fixture_rinks fr
        on fr.id = mr.fixture_rink_id
      join public.fixtures f
        on f.id = fr.fixture_id
      join public.volunteer_tasks vt
        on vt.club_id = f.club_id
       and vt.task_code = 'marker'
       and vt.is_active = true
      join public.mailing_lists ml
        on ml.id = vt.mailing_list_id
       and ml.club_id = vt.club_id
       and ml.is_active = true
      where fr.fixture_id = p_fixture_id
        and mr.status = 'open'
    ),
    current_marker_recipients as (
      select distinct
        omr.marker_request_id,
        omr.requested_at,
        omr.team_no,
        mlm.member_profile_id
      from open_marker_requests omr
      join public.mailing_list_members mlm
        on mlm.mailing_list_id = omr.mailing_list_id
       and mlm.is_active = true
      join public.mailing_lists ml
        on ml.id = mlm.mailing_list_id
      join public.club_memberships cm
        on cm.club_id = ml.club_id
       and cm.member_profile_id = mlm.member_profile_id
       and cm.is_active = true
    ),
    recipients as (
      select
        'fixture_selected'::text as event_type,
        ca.member_profile_id,
        ca.category,
        ca.team_no,
        ca.position,
        null::uuid as marker_request_id,
        null::timestamptz as request_started_at
      from current_assignments ca

      union all

      select
        'marker_request_opened',
        cmr.member_profile_id,
        'Marker Volunteer â€“ Team ' || cmr.team_no::text,
        cmr.team_no,
        null::integer,
        cmr.marker_request_id,
        cmr.requested_at
      from current_marker_recipients cmr
    )
    select
      r.member_profile_id,

      coalesce(
        nullif(btrim(mp.display_name), ''),
        nullif(
          btrim(
            coalesce(mp.first_name, '')
            || ' '
            || coalesce(mp.last_name, '')
          ),
          ''
        ),
        'Unknown'
      ) as member_name,

      r.category,

      case
        when r.event_type = 'fixture_selected' then
          case
            when exists (
              select 1
              from public.app_notifications an
              where an.fixture_id = p_fixture_id
                and an.team_selection_id = v_team_selection_id
                and an.member_profile_id = r.member_profile_id
                and an.type = 'fixture_selected'
            ) then 'Created'
            else 'Missing'
          end
        else
          case
            when exists (
              select 1
              from public.app_notifications an
              where an.fixture_id = p_fixture_id
                and an.member_profile_id = r.member_profile_id
                and an.type = 'marker_request_opened'
                and an.data ->> 'marker_request_id'
                      = r.marker_request_id::text
            ) then 'Created'
            else 'Missing'
          end
      end as app_notification,

      case
        when r.event_type = 'fixture_selected' then
          coalesce((
            select eq.status
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.member_profile_id = r.member_profile_id
              and eq.event_type = 'fixture_selected'
            order by eq.created_at desc
            limit 1
          ), case
                when nullif(btrim(mp.email_address), '') is null
                  then 'No Email'
                else 'Missing'
              end)
        else
          coalesce((
            select eq.status
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.member_profile_id = r.member_profile_id
              and eq.event_type = 'marker_request_opened'
              and eq.created_at >= r.request_started_at
            order by eq.created_at desc
            limit 1
          ), case
                when nullif(btrim(mp.email_address), '') is null
                  then 'No Email'
                else 'Missing'
              end)
      end as email_status,

      'Not Required'::text as team_sheet,

      mp.email_address
    from recipients r
    left join public.member_profiles mp
      on mp.id = r.member_profile_id
    order by
      case
        when r.category = 'Player' then 1
        when r.category = 'Opponent' then 2
        when r.category = 'Named Marker' then 3
        when r.category like 'Marker Volunteer%' then 4
        else 9
      end,
      member_name;

    return;
  end if;

  -- Existing published-team behaviour for all non-Pre-Select fixtures.
  return query
  with recipients as (
    select distinct
      nq.target_member_profile_id as member_profile_id,
      case
        when nq.event_type = 'team_published_player' then 'Player'
        when nq.event_type = 'team_published_reserve' then 'Reserve'
        when nq.event_type = 'team_published_captain' then 'Captain'
        when nq.event_type = 'team_published_vice' then 'Vice Captain'
        when nq.event_type = 'team_published_not_selected'
          then 'Not Selected'
        when nq.event_type = 'team_published_incomplete_request'
          then 'Players Required'
        else nq.event_type
      end as category,
      nq.event_type
    from public.notification_queue nq
    where nq.fixture_id = p_fixture_id
      and nq.team_selection_id = v_team_selection_id
      and nq.event_type like 'team_published%'
  )
  select
    r.member_profile_id,

    coalesce(
      nullif(mp.display_name, ''),
      trim(
        coalesce(mp.first_name, '')
        || ' '
        || coalesce(mp.last_name, '')
      ),
      'Unknown'
    ) as member_name,

    r.category,

    case
      when exists (
        select 1
        from public.app_notifications an
        where an.fixture_id = p_fixture_id
          and an.team_selection_id = v_team_selection_id
          and an.member_profile_id = r.member_profile_id
          and an.type = r.event_type
      ) then 'Created'
      else 'Missing'
    end as app_notification,

    coalesce((
      select eq.status
      from public.email_queue eq
      where eq.fixture_id = p_fixture_id
        and eq.team_selection_id = v_team_selection_id
        and eq.member_profile_id = r.member_profile_id
        and eq.event_type = r.event_type
      order by eq.created_at desc
      limit 1
    ), 'Missing') as email_status,

    case
      when r.event_type in (
        'team_published_player',
        'team_published_reserve',
        'team_published_captain',
        'team_published_vice'
      ) then
        case
          when exists (
            select 1
            from public.email_queue eq
            where eq.fixture_id = p_fixture_id
              and eq.team_selection_id = v_team_selection_id
              and eq.member_profile_id = r.member_profile_id
              and eq.event_type = r.event_type
              and jsonb_array_length(
                coalesce(eq.attachments, '[]'::jsonb)
              ) > 0
          ) then 'Attached'
          else 'Missing'
        end
      else 'Not Required'
    end as team_sheet,

    mp.email_address
  from recipients r
  left join public.member_profiles mp
    on mp.id = r.member_profile_id
  order by
    case r.category
      when 'Player' then 1
      when 'Reserve' then 2
      when 'Captain' then 3
      when 'Vice Captain' then 4
      when 'Not Selected' then 5
      else 9
    end,
    member_name;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."communications_health_detail"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."communications_health_detail"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.communications_health_detail_v2(p_fixture_id uuid)
 RETURNS TABLE(member_profile_id uuid, member_name text, category text, app_notification text, email_status text, team_sheet text, email_address text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_selection_id uuid;
  v_selection_mode text;
  v_composition_version integer;
begin
  perform public.communications_require_superuser();

  select ts.id, lower(coalesce(ct.selection_mode::text, '')),
         ts.composition_version
  into v_selection_id, v_selection_mode, v_composition_version
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  join lateral (
    select x.id, x.composition_version
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if v_selection_id is null then raise exception 'Team selection not found.'; end if;

  return query
  with participants as (
    select tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_selection_id and tsm.is_selected = true
    union
    select fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id and fra.member_profile_id is not null
  ),
  preselect_assignments as (
    select distinct fra.member_profile_id,
      case when fra.position = 201 then 'Named Marker'
           when fra.position between 101 and 100 + fr.players_per_rink then 'Opponent'
           else 'Player' end category,
      'fixture_selected'::text event_type,
      true team_sheet_required,
      fr.fixture_rink_no team_no,
      fra.position
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where v_selection_mode = 'preselect'
      and fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
      and (fra.position between 1 and fr.players_per_rink
        or fra.position between 101 and 100 + fr.players_per_rink
        or fra.position = 201)
  ),
  leadership as (
    select x.member_profile_id, x.category, x.event_type,
           true team_sheet_required, null::integer team_no, null::integer position
    from public.fixtures f
    cross join lateral (values
      (f.captain_member_profile_id, 'Captain'::text, 'team_published_captain'::text),
      (f.vice_captain_member_profile_id, 'Vice Captain'::text, 'team_published_vice'::text)
    ) x(member_profile_id, category, event_type)
    where f.id = p_fixture_id and x.member_profile_id is not null
      and not exists (
        select 1 from participants p where p.member_profile_id = x.member_profile_id
      )
  ),
  marker_volunteers as (
    select distinct mlm.member_profile_id,
      'Marker Volunteer - Team ' || fr.fixture_rink_no::text category,
      'marker_request_opened'::text event_type,
      false team_sheet_required,
      fr.fixture_rink_no team_no,
      null::integer position
    from public.fixture_marker_requests mr
    join public.fixture_rinks fr on fr.id = mr.fixture_rink_id
    join public.fixtures f on f.id = fr.fixture_id
    join public.volunteer_tasks vt on vt.club_id = f.club_id
      and vt.task_code = 'marker' and vt.is_active = true
    join public.mailing_list_members mlm on mlm.mailing_list_id = vt.mailing_list_id
      and mlm.is_active = true
    join public.club_memberships cm on cm.club_id = f.club_id
      and cm.member_profile_id = mlm.member_profile_id and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
    where v_selection_mode = 'preselect'
      and fr.fixture_id = p_fixture_id and mr.status = 'open'
      and not exists (
        select 1 from participants p where p.member_profile_id = mlm.member_profile_id
      )
  ),
  ordinary_players as (
    select distinct fra.member_profile_id, 'Player'::text category,
      'team_published_player'::text event_type, true team_sheet_required,
      null::integer team_no, null::integer position
    from public.fixture_rink_assignments fra
    join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
    where v_selection_mode <> 'preselect' and fra.fixture_id = p_fixture_id
      and fra.member_profile_id is not null
      and fra.position between 1 and fr.players_per_rink
  ),
  ordinary_reserves as (
    select distinct tsm.member_profile_id, 'Reserve'::text category,
      'team_published_reserve'::text event_type, true team_sheet_required,
      null::integer team_no, null::integer position
    from public.team_selection_members tsm
    where v_selection_mode <> 'preselect'
      and tsm.team_selection_id = v_selection_id
      and tsm.is_selected = true and lower(tsm.role::text) = 'reserve'
      and not exists (
        select 1 from ordinary_players p where p.member_profile_id = tsm.member_profile_id
      )
  ),
  ordinary_not_selected as (
    select distinct tm.member_profile_id, 'Not Selected'::text category,
      'team_published_not_selected'::text event_type, false team_sheet_required,
      null::integer team_no, null::integer position
    from public.fixtures f
    join public.team_members tm on tm.team_id = f.team_id and tm.is_active = true
    where v_selection_mode <> 'preselect' and f.id = p_fixture_id
      and not exists (
        select 1 from participants p where p.member_profile_id = tm.member_profile_id
      )
  ),
  expected as (
    select * from preselect_assignments
    union all select * from leadership
    union all select * from marker_volunteers
    union all select * from ordinary_players
    union all select * from ordinary_reserves
    union all select * from ordinary_not_selected
  )
  select e.member_profile_id,
    coalesce(nullif(btrim(mp.display_name), ''),
      nullif(btrim(coalesce(mp.first_name, '') || ' ' || coalesce(mp.last_name, '')), ''),
      'Unknown') member_name,
    e.category,
    case when app.id is null then 'Missing' else 'Created' end app_notification,
    case when nullif(btrim(mp.email_address), '') is null then 'No Email'
         else coalesce(mail.status, 'Missing') end email_status,
    case when not e.team_sheet_required then 'Not Required'
         when mail.id is null then 'Missing'
         when case
          when jsonb_typeof(coalesce(mail.attachments, '[]'::jsonb)) = 'array'
          then jsonb_array_length(coalesce(mail.attachments, '[]'::jsonb)) = 1
          and mail.attachments->0->>'contentType' = 'application/pdf'
          and nullif(mail.attachments->0->>'contentBytes', '') is not null
          and length(mail.attachments->0->>'contentBytes') <= 2700000
          and mail.attachments->0->>'contentBytes' like 'JVBERi%'
          and nullif(mail.attachments->0->>'compositionVersion', '') is not null
          and (
            mail.status = 'sent'
            or mail.attachments->0->>'compositionVersion' = v_composition_version::text
          )
          else false
         end then 'Attached' else 'Missing' end team_sheet,
    mp.email_address
  from expected e
  left join public.member_profiles mp on mp.id = e.member_profile_id
  left join lateral (
    select an.id from public.app_notifications an
    where an.fixture_id = p_fixture_id
      and an.team_selection_id = v_selection_id
      and an.member_profile_id = e.member_profile_id
      and (an.type = e.event_type
        or (e.category = 'Player' and an.type in ('fixture_selected','reserve_promoted')))
    order by an.created_at desc limit 1
  ) app on true
  left join lateral (
    select eq.id, eq.status::text, eq.attachments
    from public.email_queue eq
    where eq.fixture_id = p_fixture_id
      and eq.team_selection_id = v_selection_id
      and eq.member_profile_id = e.member_profile_id
      and eq.status <> 'cancelled'
      and (eq.event_type = e.event_type
        or (e.category = 'Player' and eq.event_type in ('fixture_selected','reserve_promoted')))
    order by eq.created_at desc limit 1
  ) mail on true
  order by case e.category when 'Player' then 1 when 'Opponent' then 2
    when 'Named Marker' then 3 when 'Reserve' then 4 when 'Captain' then 5
    when 'Vice Captain' then 6 when 'Not Selected' then 8 else 7 end,
    member_name;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."communications_health_detail_v2"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."communications_health_detail_v2"(p_fixture_id uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."communications_health_detail_v2"(p_fixture_id uuid) TO "authenticated";

CREATE OR REPLACE FUNCTION public.communications_require_superuser()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
begin
  if auth.uid() is null or not exists (
    select 1 from public.app_superusers su where su.user_id = auth.uid()
  ) then
    raise exception 'Superuser access required.';
  end if;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."communications_require_superuser"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."communications_require_superuser"() TO "service_role";

CREATE OR REPLACE FUNCTION public.confirm_team_changes(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_current_version bigint;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_before_positioned uuid[] := array[]::uuid[];
  v_before_reserves uuid[] := array[]::uuid[];
  v_after_positioned uuid[] := array[]::uuid[];
  v_added uuid[] := array[]::uuid[];
  v_removed uuid[] := array[]::uuid[];
  v_before_assignments jsonb := '{}'::jsonb;
  v_after_assignments jsonb := '{}'::jsonb;
  v_member_id uuid;
  v_event_type text;
  v_added_count integer := 0;
  v_removed_count integer := 0;
  v_promoted_count integer := 0;
  v_moved_count integer := 0;
  v_reserve_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;

  v_actor := public.my_member_profile_id();
  if v_actor is null then
    raise exception 'Member profile not found.';
  end if;

  if jsonb_typeof(coalesce(p_members, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Team change payload must contain arrays.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select
    ts.fixture_id,
    f.club_id,
    ts.composition_version,
    lower(btrim(coalesce(ct.selection_mode, ''))),
    f.team_id,
    coalesce(f.requires_rsvp, false)
  into
    v_fixture_id,
    v_club_id,
    v_current_version,
    v_selection_mode,
    v_team_id,
    v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
    and ts.status = 'published'::public.selection_status
  for update of ts;

  if not found then
    raise exception 'Published team selection not found.';
  end if;

  if v_selection_mode = 'preselect'
     or (v_team_id is null and not v_requires_rsvp) then
    raise exception 'Confirm Team Changes is only available for published Team or RSVP fixtures.';
  end if;

  if not (
    public.is_app_superuser()
    or (
      exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = v_actor
          and cm.is_active = true
          and lower(cm.role::text) <> 'guest'
      )
      and (
        public.can_manage_team_selection(v_fixture_id)
        or exists (
          select 1 from public.fixtures f
          where f.id = v_fixture_id
            and v_actor in (
              f.captain_member_profile_id,
              f.vice_captain_member_profile_id
            )
        )
      )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where m.member_profile_id is null
       or lower(btrim(coalesce(m.role, ''))) not in ('player', 'reserve')
       or coalesce(m.is_selected, false) = false
  ) then
    raise exception 'Invalid desired team member state.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    group by m.member_profile_id
    having count(*) > 1
  ) then
    raise exception 'A member cannot appear more than once in the desired team.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where not exists (
      select 1 from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = m.member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
    )
  ) then
    raise exception 'Target member is not an active non-Guest member of this club';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    left join public.fixture_rinks fr
      on fr.id = a.fixture_rink_id and fr.fixture_id = v_fixture_id
    where a.member_profile_id is null
       or fr.id is null
       or a.position not between 1 and fr.players_per_rink
       or not exists (
         select 1
         from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
           as m(member_profile_id uuid, role text, is_selected boolean)
         where m.member_profile_id = a.member_profile_id
           and lower(btrim(m.role)) = 'player'
           and m.is_selected = true
       )
  ) then
    raise exception 'Invalid player-position assignment.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.member_profile_id
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.fixture_rink_id, a.position
    having count(*) > 1
  ) then
    raise exception 'Duplicate desired player-position assignment.';
  end if;

  perform 1 from public.team_selection_members
  where team_selection_id = p_team_selection_id for update;
  perform 1 from public.fixture_rink_assignments
  where fixture_id = v_fixture_id for update;

  if not exists (
    (
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
      except
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
    )
    union all
    (
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      except
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
    )
  ) and not exists (
    (
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
      except
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    )
    union all
    (
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
      except
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
    )
  ) then
    return jsonb_build_object(
      'composition_version', v_current_version,
      'newly_positioned', 0,
      'reserve_promotions', 0,
      'removed_from_player_positions', 0,
      'position_only_moves', 0,
      'communications_queued', 0,
      'no_change', true
    );
  end if;

  if p_expected_version is distinct from v_current_version then
    raise exception 'TEAM_COMPOSITION_VERSION_CONFLICT:%:%',
      p_expected_version, v_current_version;
  end if;

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_before_positioned, v_before_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(member_profile_id), array[]::uuid[])
  into v_before_reserves
  from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and is_selected = true
    and role = 'reserve'::public.selection_member_role;

  insert into public.team_selection_members (
    team_selection_id, member_profile_id, role, acceptance,
    responded_at, is_selected, acceptance_by
  )
  select
    p_team_selection_id,
    m.member_profile_id,
    lower(btrim(m.role))::public.selection_member_role,
    'pending'::public.acceptance_status,
    null,
    true,
    null
  from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
    as m(member_profile_id uuid, role text, is_selected boolean)
  on conflict (team_selection_id, member_profile_id) do update set
    role = excluded.role,
    is_selected = true;

  update public.team_selection_members tsm
  set is_selected = false
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role in (
      'player'::public.selection_member_role,
      'reserve'::public.selection_member_role
    )
    and not exists (
      select 1
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      where m.member_profile_id = tsm.member_profile_id
    );

  delete from public.fixture_rink_assignments fra
  using public.fixture_rinks fr
  where fra.fixture_id = v_fixture_id
    and fr.id = fra.fixture_rink_id
    and fr.fixture_id = v_fixture_id
    and fra.position between 1 and fr.players_per_rink;

  insert into public.fixture_rink_assignments (
    fixture_id, fixture_rink_id, member_profile_id, position
  )
  select v_fixture_id, a.fixture_rink_id, a.member_profile_id, a.position
  from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
    as a(fixture_rink_id uuid, position integer, member_profile_id uuid);

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_after_positioned, v_after_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(x), array[]::uuid[]) into v_added
  from unnest(v_after_positioned) x where not (x = any(v_before_positioned));
  select coalesce(array_agg(x), array[]::uuid[]) into v_removed
  from unnest(v_before_positioned) x where not (x = any(v_after_positioned));

  update public.team_selection_members
  set acceptance = 'pending'::public.acceptance_status,
      responded_at = null,
      acceptance_by = null
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added);

  delete from public.notification_queue
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added)
    and event_type = 'team_acceptance_changed'
    and status = 'pending'
    and payload->>'new_acceptance' = 'pending';

  update public.email_action_requests
  set status = 'cancelled', updated_at = now()
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and status in ('pending', 'responded');

  update public.notification_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and target_member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status = 'pending';

  update public.email_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status in ('pending', 'failed')
    and sent_at is null;

  foreach v_member_id in array v_added loop
    v_event_type := case
      when v_member_id = any(v_before_reserves) then 'reserve_promoted'
      else 'fixture_selected'
    end;
    perform public.queue_post_publication_player_change(
      (select id from public.team_selection_members
       where team_selection_id = p_team_selection_id
         and member_profile_id = v_member_id),
      v_event_type,
      v_actor
    );
    v_added_count := v_added_count + 1;
    if v_event_type = 'reserve_promoted' then
      v_promoted_count := v_promoted_count + 1;
    end if;
  end loop;


  -- Communicate the final reserve state once, rather than a removal notice.
  -- Existing attachment handling blocks delivery until the current PDF exists.
  insert into public.notification_queue (
    event_type, member_profile_id, target_member_profile_id,
    fixture_id, team_selection_id, payload, status
  )
  select
    'team_published_reserve', v_actor, tsm.member_profile_id,
    v_fixture_id, p_team_selection_id,
    jsonb_build_object(
      'fixture_label', coalesce(nullif(btrim(f.team_name), ''), 'Fixture'),
      'fixture_date', f.start_at,
      'start_at', f.start_at,
      'home_away', case when f.is_home then 'Home' else 'Away' end,
      'venue_name', coalesce(v.name, ov.name, ''),
      'role', 'reserve',
      'new_role', 'reserve',
      'team_sheet_required', true
    ),
    'pending'
  from public.team_selection_members tsm
  join public.fixtures f on f.id = v_fixture_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'reserve'::public.selection_member_role
    and not (tsm.member_profile_id = any(v_before_reserves));
  get diagnostics v_reserve_count = row_count;

  v_removed_count := coalesce(array_length(v_removed, 1), 0);
  select count(*) into v_moved_count
  from unnest(v_after_positioned) x
  where x = any(v_before_positioned)
    and v_before_assignments->(x::text) is distinct from v_after_assignments->(x::text);

  update public.team_selections
  set composition_version = composition_version + 1
  where id = p_team_selection_id
  returning composition_version into v_current_version;

  return jsonb_build_object(
    'composition_version', v_current_version,
    'newly_positioned', v_added_count,
    'reserve_promotions', v_promoted_count,
    'removed_from_player_positions', v_removed_count,
    'position_only_moves', v_moved_count,
    'communications_queued', v_added_count + v_reserve_count
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."confirm_team_changes"(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."confirm_team_changes"(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."confirm_team_changes"(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.confirm_team_changes(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb, p_rinks jsonb, p_original_rinks jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fixture public.fixtures%rowtype;
  v_rinks jsonb;
  v_saved_rinks jsonb;
  v_expected_rinks jsonb;
  v_structure_changed boolean;
  v_before_selected uuid[];
  v_dropped_count integer := 0;
  v_withdrawn jsonb := '{}'::jsonb;
  v_withdrawn_count integer := 0;
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_current_version bigint;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_before_positioned uuid[] := array[]::uuid[];
  v_before_reserves uuid[] := array[]::uuid[];
  v_after_positioned uuid[] := array[]::uuid[];
  v_added uuid[] := array[]::uuid[];
  v_removed uuid[] := array[]::uuid[];
  v_before_assignments jsonb := '{}'::jsonb;
  v_after_assignments jsonb := '{}'::jsonb;
  v_member_id uuid;
  v_event_type text;
  v_added_count integer := 0;
  v_removed_count integer := 0;
  v_promoted_count integer := 0;
  v_moved_count integer := 0;
  v_reserve_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;

  v_actor := public.my_member_profile_id();
  if v_actor is null then
    raise exception 'Member profile not found.';
  end if;

  if jsonb_typeof(coalesce(p_members, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception 'Team change payload must contain arrays.';
  end if;

  -- Match the existing structure editor's fixture-before-selection lock order.
  select f.* into v_fixture from public.fixtures f
  join public.team_selections ts on ts.fixture_id=f.id
  where ts.id=p_team_selection_id for update of f;
  if not found or v_fixture.cancelled_at is not null then
    raise exception 'Active fixture not found.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select
    ts.fixture_id,
    f.club_id,
    ts.composition_version,
    lower(btrim(coalesce(ct.selection_mode, ''))),
    f.team_id,
    coalesce(f.requires_rsvp, false)
  into
    v_fixture_id,
    v_club_id,
    v_current_version,
    v_selection_mode,
    v_team_id,
    v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
    and ts.status = 'published'::public.selection_status
  for update of ts;

  if not found then
    raise exception 'Published team selection not found.';
  end if;

  if v_selection_mode = 'preselect'
     or (v_team_id is null and not v_requires_rsvp) then
    raise exception 'Confirm Team Changes is only available for published Team or RSVP fixtures.';
  end if;

  if not (
    public.is_app_superuser()
    or (
      exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = v_actor
          and cm.is_active = true
          and lower(cm.role::text) <> 'guest'
      )
      and (
        public.can_manage_team_selection(v_fixture_id)
        or exists (
          select 1 from public.fixtures f
          where f.id = v_fixture_id
            and v_actor in (
              f.captain_member_profile_id,
              f.vice_captain_member_profile_id
            )
        )
      )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  if jsonb_typeof(p_rinks) is distinct from 'array'
     or jsonb_typeof(p_original_rinks) is distinct from 'array'
     or jsonb_array_length(p_rinks)=0 then
    raise exception 'At least one desired team is required.';
  end if;
  if exists(select 1 from jsonb_to_recordset(p_rinks)
    as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text)
    where r.id is null or r.fixture_rink_no is null or r.fixture_rink_no<1
      or r.players_per_rink is distinct from case r.format
        when 'singles' then 1 when 'pairs' then 2 when 'aussie_pairs' then 2
        when 'triples' then 3 when 'rinks' then 4 when 'fours' then 4 end
      or r.format is null or r.format not in ('singles','pairs','aussie_pairs','triples','rinks','fours')
      or exists(select 1 from public.fixture_rinks fr where fr.id=r.id and fr.fixture_id<>v_fixture_id)) then
    raise exception 'Invalid desired team structure.';
  end if;
  if (select count(distinct r.id) from jsonb_to_recordset(p_rinks) as r(id uuid))<>jsonb_array_length(p_rinks)
     or (select count(distinct r.fixture_rink_no) from jsonb_to_recordset(p_rinks) as r(fixture_rink_no integer))<>jsonb_array_length(p_rinks)
     or (select max(r.fixture_rink_no) from jsonb_to_recordset(p_rinks) as r(fixture_rink_no integer))<>jsonb_array_length(p_rinks)
     or exists(select 1 from jsonb_to_recordset(p_rinks) as r(home_rink_label text)
       where nullif(btrim(r.home_rink_label),'') is not null
       group by btrim(r.home_rink_label) having count(*)>1) then
    raise exception 'Duplicate or invalid team numbers or physical rinks.';
  end if;
  select jsonb_agg(jsonb_build_object('id',r.id,'fixture_rink_no',r.fixture_rink_no,
      'format',r.format,'players_per_rink',r.players_per_rink,
      'home_rink_label',nullif(btrim(r.home_rink_label),'')) order by r.id)
  into v_rinks from jsonb_to_recordset(p_rinks)
    as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text);
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'fixture_rink_no',r.fixture_rink_no,
      'format',r.format,'players_per_rink',r.players_per_rink,
      'home_rink_label',nullif(btrim(r.home_rink_label),'')) order by r.id),'[]'::jsonb)
  into v_saved_rinks from public.fixture_rinks r where r.fixture_id=v_fixture_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'fixture_rink_no',r.fixture_rink_no,
      'format',r.format,'players_per_rink',r.players_per_rink,
      'home_rink_label',nullif(btrim(r.home_rink_label),'')) order by r.id),'[]'::jsonb)
  into v_expected_rinks from jsonb_to_recordset(p_original_rinks)
    as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text);
  v_structure_changed := v_rinks is distinct from v_saved_rinks;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where m.member_profile_id is null
       or lower(btrim(coalesce(m.role, ''))) not in ('player', 'reserve')
       or coalesce(m.is_selected, false) = false
  ) then
    raise exception 'Invalid desired team member state.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    group by m.member_profile_id
    having count(*) > 1
  ) then
    raise exception 'A member cannot appear more than once in the desired team.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
      as m(member_profile_id uuid, role text, is_selected boolean)
    where not exists (
      select 1 from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = m.member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
    )
  ) then
    raise exception 'Target member is not an active non-Guest member of this club';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    left join jsonb_to_recordset(v_rinks) as fr(id uuid,players_per_rink integer)
      on fr.id = a.fixture_rink_id
    where a.member_profile_id is null
       or fr.id is null
       or a.position is null
       or a.position not between 1 and fr.players_per_rink
       or not exists (
         select 1
         from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
           as m(member_profile_id uuid, role text, is_selected boolean)
         where m.member_profile_id = a.member_profile_id
           and lower(btrim(m.role)) = 'player'
           and m.is_selected = true
       )
  ) then
    raise exception 'Invalid player-position assignment.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.member_profile_id
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
      as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    group by a.fixture_rink_id, a.position
    having count(*) > 1
  ) then
    raise exception 'Duplicate desired player-position assignment.';
  end if;

  perform 1 from public.team_selection_members
  where team_selection_id = p_team_selection_id for update;
  perform 1 from public.fixture_rink_assignments
  where fixture_id = v_fixture_id for update;

  if not v_structure_changed and not exists (
    (
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
      except
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
    )
    union all
    (
      select m.member_profile_id, lower(btrim(m.role))
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      except
      select tsm.member_profile_id, tsm.role::text
      from public.team_selection_members tsm
      where tsm.team_selection_id = p_team_selection_id
        and tsm.is_selected = true
        and tsm.role in (
          'player'::public.selection_member_role,
          'reserve'::public.selection_member_role
        )
    )
  ) and not exists (
    (
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
      except
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
    )
    union all
    (
      select a.fixture_rink_id, a.position, a.member_profile_id
      from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
        as a(fixture_rink_id uuid, position integer, member_profile_id uuid)
      except
      select fra.fixture_rink_id, fra.position, fra.member_profile_id
      from public.fixture_rink_assignments fra
      join public.fixture_rinks fr
        on fr.id = fra.fixture_rink_id
       and fr.fixture_id = v_fixture_id
      where fra.fixture_id = v_fixture_id
        and fra.position between 1 and fr.players_per_rink
    )
  ) then
    return jsonb_build_object(
      'composition_version', v_current_version,
      'newly_positioned', 0,
      'reserve_promotions', 0,
      'removed_from_player_positions', 0,
      'position_only_moves', 0,
      'communications_queued', 0,
      'no_change', true
    );
  end if;

  if p_expected_version is distinct from v_current_version
     or v_saved_rinks is distinct from v_expected_rinks then
    raise exception 'TEAM_COMPOSITION_VERSION_CONFLICT:%:%',
      p_expected_version, v_current_version;
  end if;

  -- Validate capacity/availability once for the final structure, not each intermediate edit.
  if v_structure_changed and v_fixture.green_area_id is not null then
    perform 1 from public.green_areas where id=v_fixture.green_area_id for update;
  end if;
  if v_structure_changed and exists(select 1 from jsonb_to_recordset(v_rinks) as r(home_rink_label text)
      where r.home_rink_label is not null) then
    if not v_fixture.is_home or v_fixture.green_area_id is null then
      raise exception 'Only a home fixture can be assigned a physical rink.';
    end if;
    if exists(select 1 from jsonb_to_recordset(v_rinks) as r(home_rink_label text)
      where r.home_rink_label is not null and not exists(
        select 1 from public.get_green_rink_availability(v_fixture.green_area_id,
          v_fixture.start_at,v_fixture.end_at,v_fixture.id) a
        where a.rink_label=r.home_rink_label and not a.is_booked)) then
      raise exception 'That physical rink is not available.';
    end if;
  end if;
  select coalesce(array_agg(member_profile_id),array[]::uuid[]) into v_before_selected
  from public.team_selection_members where team_selection_id=p_team_selection_id
    and is_selected and role in ('player','reserve');

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_before_positioned, v_before_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(member_profile_id), array[]::uuid[])
  into v_before_reserves
  from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and is_selected = true
    and role = 'reserve'::public.selection_member_role;

  if exists(select 1 from unnest(v_before_positioned) m(id)
      join jsonb_to_recordset(p_members) as desired(member_profile_id uuid,role text)
        on desired.member_profile_id=m.id and desired.role='player'
      where not exists(select 1 from jsonb_to_recordset(p_assignments)
        as a(member_profile_id uuid) where a.member_profile_id=m.id)) then
    raise exception 'Resolve unpositioned players: assign a position, make reserve or remove before confirming.';
  end if;

  -- Capture members of deleted teams before changing their positions or team numbers.
  select coalesce(jsonb_object_agg(a.key, r.fixture_rink_no), '{}'::jsonb)
    into v_withdrawn
  from jsonb_each(v_before_assignments) a
  join public.fixture_rinks r on r.id=(a.value->>'fixture_rink_id')::uuid
    and r.fixture_id=v_fixture_id
  where not exists(select 1 from jsonb_to_recordset(v_rinks) as desired(id uuid)
    where desired.id=r.id);

  insert into public.team_selection_members (
    team_selection_id, member_profile_id, role, acceptance,
    responded_at, is_selected, acceptance_by
  )
  select
    p_team_selection_id,
    m.member_profile_id,
    lower(btrim(m.role))::public.selection_member_role,
    'pending'::public.acceptance_status,
    null,
    true,
    null
  from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
    as m(member_profile_id uuid, role text, is_selected boolean)
  on conflict (team_selection_id, member_profile_id) do update set
    role = excluded.role,
    is_selected = true;

  update public.team_selection_members tsm
  set is_selected = false
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role in (
      'player'::public.selection_member_role,
      'reserve'::public.selection_member_role
    )
    and not exists (
      select 1
      from jsonb_to_recordset(coalesce(p_members, '[]'::jsonb))
        as m(member_profile_id uuid, role text, is_selected boolean)
      where m.member_profile_id = tsm.member_profile_id
    );

  delete from public.fixture_rink_assignments fra
  using public.fixture_rinks fr
  where fra.fixture_id = v_fixture_id
    and fr.id = fra.fixture_rink_id
    and fr.fixture_id = v_fixture_id
    and fra.position between 1 and fr.players_per_rink;

  if v_structure_changed then
    delete from public.fixture_rinks fr where fr.fixture_id=v_fixture_id
      and not exists(select 1 from jsonb_to_recordset(v_rinks) as r(id uuid) where r.id=fr.id);
    -- Temporary numbers avoid collisions while deleted teams are renumbered.
    update public.fixture_rinks set fixture_rink_no=fixture_rink_no+1000000
      where fixture_id=v_fixture_id;
    insert into public.fixture_rinks(id,fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label)
    select r.id,v_fixture_id,r.fixture_rink_no,r.format,r.players_per_rink,r.home_rink_label
    from jsonb_to_recordset(v_rinks)
      as r(id uuid,fixture_rink_no integer,format text,players_per_rink integer,home_rink_label text)
    on conflict(id) do update set fixture_rink_no=excluded.fixture_rink_no,
      format=excluded.format,players_per_rink=excluded.players_per_rink,home_rink_label=excluded.home_rink_label;
    update public.fixtures set rinks_required=jsonb_array_length(v_rinks),
      players_per_rink=(select max(r.players_per_rink) from jsonb_to_recordset(v_rinks) as r(players_per_rink integer))
      where id=v_fixture_id;
  end if;

  insert into public.fixture_rink_assignments (
    fixture_id, fixture_rink_id, member_profile_id, position
  )
  select v_fixture_id, a.fixture_rink_id, a.member_profile_id, a.position
  from jsonb_to_recordset(coalesce(p_assignments, '[]'::jsonb))
    as a(fixture_rink_id uuid, position integer, member_profile_id uuid);

  select
    coalesce(array_agg(distinct tsm.member_profile_id), array[]::uuid[]),
    coalesce(jsonb_object_agg(
      tsm.member_profile_id::text,
      jsonb_build_object('fixture_rink_id', fra.fixture_rink_id, 'position', fra.position)
    ), '{}'::jsonb)
  into v_after_positioned, v_after_assignments
  from public.team_selection_members tsm
  join public.fixture_rink_assignments fra
    on fra.fixture_id = v_fixture_id
   and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id and fr.fixture_id = v_fixture_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'player'::public.selection_member_role
    and fra.position between 1 and fr.players_per_rink;

  select coalesce(array_agg(x), array[]::uuid[]) into v_added
  from unnest(v_after_positioned) x where not (x = any(v_before_positioned));
  select coalesce(array_agg(x), array[]::uuid[]) into v_removed
  from unnest(v_before_positioned) x where not (x = any(v_after_positioned));

  update public.team_selection_members
  set acceptance = 'pending'::public.acceptance_status,
      responded_at = null,
      acceptance_by = null
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added);

  delete from public.notification_queue
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_added)
    and event_type = 'team_acceptance_changed'
    and status = 'pending'
    and payload->>'new_acceptance' = 'pending';

  update public.email_action_requests
  set status = 'cancelled', updated_at = now()
  where team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and status in ('pending', 'responded');

  update public.notification_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and target_member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status = 'pending';

  update public.email_queue
  set status = 'cancelled'
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and member_profile_id = any(v_removed)
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
    and status in ('pending', 'failed')
    and sent_at is null;

  foreach v_member_id in array v_added loop
    v_event_type := case
      when v_member_id = any(v_before_reserves) then 'reserve_promoted'
      else 'fixture_selected'
    end;
    perform public.queue_post_publication_player_change(
      (select id from public.team_selection_members
       where team_selection_id = p_team_selection_id
         and member_profile_id = v_member_id),
      v_event_type,
      v_actor
    );
    v_added_count := v_added_count + 1;
    if v_event_type = 'reserve_promoted' then
      v_promoted_count := v_promoted_count + 1;
    end if;
  end loop;


  -- Communicate the final reserve state once, rather than a removal notice.
  -- Existing attachment handling blocks delivery until the current PDF exists.
  insert into public.notification_queue (
    event_type, member_profile_id, target_member_profile_id,
    fixture_id, team_selection_id, payload, status
  )
  select
    'team_published_reserve', v_actor, tsm.member_profile_id,
    v_fixture_id, p_team_selection_id,
    jsonb_build_object(
      'fixture_label', coalesce(nullif(btrim(f.team_name), ''), 'Fixture'),
      'fixture_date', f.start_at,
      'start_at', f.start_at,
      'home_away', case when f.is_home then 'Home' else 'Away' end,
      'venue_name', coalesce(v.name, ov.name, ''),
      'role', 'reserve',
      'new_role', 'reserve',
      'team_sheet_required', true
    ),
    'pending'
  from public.team_selection_members tsm
  join public.fixtures f on f.id = v_fixture_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'reserve'::public.selection_member_role
    and not (tsm.member_profile_id = any(v_before_reserves))
    and not (v_withdrawn ? tsm.member_profile_id::text);
  get diagnostics v_reserve_count = row_count;

  -- Cancel unsent selection/reserve messages for people absent from the final team.
  update public.notification_queue nq set status='cancelled'
  where nq.team_selection_id=p_team_selection_id and nq.status in ('pending','failed')
    and nq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve')
    and nq.target_member_profile_id=any(v_before_selected)
    and not exists(select 1 from jsonb_to_recordset(p_members) as m(member_profile_id uuid)
      where m.member_profile_id=nq.target_member_profile_id);
  update public.email_queue eq set status='cancelled'
  where eq.team_selection_id=p_team_selection_id and eq.status in ('pending','failed') and eq.sent_at is null
    and eq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve')
    and eq.member_profile_id=any(v_before_selected)
    and not exists(select 1 from jsonb_to_recordset(p_members) as m(member_profile_id uuid)
      where m.member_profile_id=eq.member_profile_id);

  -- Only explicitly removed members get a dropped notice. Reserves receive their final reserve event above.
  insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,
    fixture_id,team_selection_id,payload,status)
  select 'fixture_message',v_actor,m.id,v_fixture_id,p_team_selection_id,
    jsonb_build_object('title','Team selection changed',
      'message','You are no longer selected for this fixture.',
      'fixture_label',coalesce(nullif(v_fixture.team_name,''),'Fixture'),
      'fixture_date',v_fixture.start_at,'change_kind','removed_from_selection'), 'pending'
  from unnest(v_before_selected) m(id)
  where not (v_withdrawn ? m.id::text)
    and not exists(select 1 from jsonb_to_recordset(p_members) as x(member_profile_id uuid)
    where x.member_profile_id=m.id);
  get diagnostics v_dropped_count = row_count;

  -- Supersede older unsent status messages with one final withdrawal outcome.
  update public.notification_queue nq set status='cancelled'
  where nq.team_selection_id=p_team_selection_id and nq.status in ('pending','failed')
    and v_withdrawn ? nq.target_member_profile_id::text
    and (nq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve')
      or (nq.event_type='fixture_message' and nq.payload->>'change_kind'='team_withdrawn'));
  update public.email_queue eq set status='cancelled'
  where eq.team_selection_id=p_team_selection_id and eq.status in ('pending','failed') and eq.sent_at is null
    and v_withdrawn ? eq.member_profile_id::text
    and eq.event_type in ('fixture_selected','reserve_promoted','team_published_player','team_published_reserve');

  -- Use the existing fixture-message delivery path, with an explicit change kind.
  -- Its required-sheet flag blocks retained/reserve delivery until the PDF is rebuilt.
  insert into public.notification_queue(event_type,member_profile_id,target_member_profile_id,
    fixture_id,team_selection_id,payload,status)
  select 'fixture_message',v_actor,w.key::uuid,v_fixture_id,p_team_selection_id,
    jsonb_build_object(
      'title','Team withdrawn',
      'message',format('Your team (Team %s) has been withdrawn from this fixture. ',w.value) ||
        case when m.role='reserve' then 'You are now a reserve.'
          when m.role='player' then format('You have been reassigned to Team %s.',r.fixture_rink_no)
          else 'You are no longer required to play.' end ||
        ' The fixture is still going ahead.',
      'fixture_label',coalesce(nullif(v_fixture.team_name,''),'Fixture'),
      'fixture_date',v_fixture.start_at,
      'change_kind','team_withdrawn',
      'previous_team_number',w.value::integer,
      'final_role',coalesce(m.role,'removed'),
      'final_team_number',r.fixture_rink_no,
      'team_sheet_required',coalesce(m.role in ('player','reserve'),false)
    ),'pending'
  from jsonb_each_text(v_withdrawn) w
  left join jsonb_to_recordset(p_members) as m(member_profile_id uuid,role text)
    on m.member_profile_id=w.key::uuid
  left join jsonb_to_recordset(p_assignments) as a(member_profile_id uuid,fixture_rink_id uuid)
    on a.member_profile_id=w.key::uuid
  left join public.fixture_rinks r on r.id=a.fixture_rink_id and r.fixture_id=v_fixture_id;
  get diagnostics v_withdrawn_count = row_count;

  v_removed_count := coalesce(array_length(v_removed, 1), 0);
  select count(*) into v_moved_count
  from unnest(v_after_positioned) x
  where x = any(v_before_positioned)
    and v_before_assignments->(x::text) is distinct from v_after_assignments->(x::text);

  update public.team_selections
  set composition_version = composition_version + 1
  where id = p_team_selection_id
  returning composition_version into v_current_version;

  return jsonb_build_object(
    'composition_version', v_current_version,
    'newly_positioned', v_added_count,
    'reserve_promotions', v_promoted_count,
    'removed_from_player_positions', v_removed_count,
    'position_only_moves', v_moved_count,
    'communications_queued', v_added_count + v_reserve_count + v_dropped_count + v_withdrawn_count,
    'team_withdrawal_messages', v_withdrawn_count,
    'dropped', v_dropped_count,
    'structure_changed', v_structure_changed
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."confirm_team_changes"(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb, p_rinks jsonb, p_original_rinks jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."confirm_team_changes"(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb, p_rinks jsonb, p_original_rinks jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."confirm_team_changes"(p_team_selection_id uuid, p_expected_version bigint, p_members jsonb, p_assignments jsonb, p_rinks jsonb, p_original_rinks jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.create_fixture_with_setup(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_team_id uuid DEFAULT NULL::uuid, p_team_name text DEFAULT NULL::text, p_requires_rsvp boolean DEFAULT true, p_venue_id uuid DEFAULT NULL::uuid, p_opponent_venue_id uuid DEFAULT NULL::uuid, p_green_area_id uuid DEFAULT NULL::uuid, p_orientation text DEFAULT NULL::text, p_captain_member_profile_id uuid DEFAULT NULL::uuid, p_vice_captain_member_profile_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_create_team_selection boolean DEFAULT false, p_team_selection_status text DEFAULT 'published'::text, p_home_rink_labels jsonb DEFAULT '[]'::jsonb, p_rink_assignments jsonb DEFAULT '[]'::jsonb, p_team_selection_members jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "public"."create_fixture_with_setup"(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."create_fixture_with_setup"(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb) TO "authenticated";

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
$function$;

REVOKE ALL ON FUNCTION "public"."create_fixture_with_setup_v2"(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_dress_code text, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."create_fixture_with_setup_v2"(p_club_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_section text, p_rinks_required integer, p_players_per_rink integer, p_format text, p_competition_type_id uuid, p_dress_code text, p_team_id uuid, p_team_name text, p_requires_rsvp boolean, p_venue_id uuid, p_opponent_venue_id uuid, p_green_area_id uuid, p_orientation text, p_captain_member_profile_id uuid, p_vice_captain_member_profile_id uuid, p_notes text, p_create_team_selection boolean, p_team_selection_status text, p_home_rink_labels jsonb, p_rink_assignments jsonb, p_team_selection_members jsonb) TO "authenticated";

CREATE OR REPLACE FUNCTION public.create_green_rink_maintenance_safe(p_green_area_id uuid, p_rink_number integer, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_reason text DEFAULT 'Maintenance'::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_green public.green_areas%rowtype;
  v_rink_label text;
  v_impact_count integer;
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select * into v_green
  from public.green_areas
  where id = p_green_area_id;

  if not found then
    raise exception 'Green area was not found.';
  end if;

  if not (
    public.is_club_admin(v_green.club_id)
    or exists (
      select 1 from public.app_superusers su where su.user_id = auth.uid()
    )
  ) then
    raise exception 'Club administrator access is required.';
  end if;

  if p_rink_number < 1 or p_rink_number > v_green.rink_count then
    raise exception 'Rink number % is not valid for this green.', p_rink_number;
  end if;

  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'A valid maintenance start/end time is required.';
  end if;

  if exists (
    select 1
    from public.green_rink_maintenance m
    where m.green_area_id = p_green_area_id
      and m.rink_number = p_rink_number
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
  ) then
    raise exception 'This rink already has maintenance during part of the selected period.';
  end if;

  v_rink_label := case
    when v_green.scheme_type = 'custom_list' then v_green.custom_labels[p_rink_number]
    when v_green.scheme_type = 'alpha' then coalesce(v_green.scheme_prefix, '') || chr(64 + p_rink_number)
    else coalesce(v_green.scheme_prefix, '') || case
      when coalesce(v_green.scheme_padding, 0) > 0
        then lpad(p_rink_number::text, v_green.scheme_padding, '0')
      else p_rink_number::text
    end
  end;

  select count(*)::integer
    into v_impact_count
  from public.get_green_maintenance_impacts(
    p_green_area_id,
    array[v_rink_label],
    p_start_at,
    p_end_at
  );

  if v_impact_count > 0 then
    raise exception 'MAINTENANCE_IMPACT:%', v_impact_count;
  end if;

  insert into public.green_rink_maintenance (
    club_id,
    green_area_id,
    rink_number,
    start_at,
    end_at,
    reason,
    notes,
    created_by_member_profile_id
  ) values (
    v_green.club_id,
    p_green_area_id,
    p_rink_number,
    p_start_at,
    p_end_at,
    coalesce(nullif(btrim(p_reason), ''), 'Maintenance'),
    nullif(btrim(coalesce(p_notes, '')), ''),
    public.my_member_profile_id()
  )
  returning id into v_id;

  return v_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."create_green_rink_maintenance_safe"(p_green_area_id uuid, p_rink_number integer, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_reason text, p_notes text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."create_green_rink_maintenance_safe"(p_green_area_id uuid, p_rink_number integer, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_reason text, p_notes text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."create_green_rink_maintenance_safe"(p_green_area_id uuid, p_rink_number integer, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_reason text, p_notes text) TO "service_role";

CREATE OR REPLACE FUNCTION public.create_repeated_fixture_from_source(p_source_fixture_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean DEFAULT NULL::boolean, p_opponent_venue_id uuid DEFAULT NULL::uuid, p_preferred_rink_labels text[] DEFAULT '{}'::text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

REVOKE ALL ON FUNCTION "public"."create_repeated_fixture_from_source"(p_source_fixture_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_opponent_venue_id uuid, p_preferred_rink_labels text[]) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."create_repeated_fixture_from_source"(p_source_fixture_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_opponent_venue_id uuid, p_preferred_rink_labels text[]) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."create_repeated_fixture_from_source"(p_source_fixture_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_is_home boolean, p_opponent_venue_id uuid, p_preferred_rink_labels text[]) TO "service_role";

CREATE OR REPLACE FUNCTION public.debug_member_identity_links(p_email text DEFAULT NULL::text, p_club_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(auth_user_id uuid, auth_email text, member_profile_id uuid, profile_email text, first_name text, last_name text, display_name text, club_membership_id uuid, club_id uuid, role text, is_active boolean, membership_created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  select
    au.id as auth_user_id,
    au.email as auth_email,

    mp.id as member_profile_id,
    mp.email_address as profile_email,
    mp.first_name,
    mp.last_name,
    mp.display_name,

    cm.id as club_membership_id,
    cm.club_id,
    cm.role::text,
    cm.is_active,
    cm.created_at as membership_created_at

  from auth.users au
  left join public.member_profiles mp
    on lower(mp.email_address) = lower(au.email)
    or mp.user_id = au.id
  left join public.club_memberships cm
    on cm.member_profile_id = mp.id

  where
    (p_email is null or lower(au.email) = lower(p_email))
    and
    (p_club_id is null or cm.club_id = p_club_id)

  order by
    au.email,
    mp.last_name,
    mp.first_name,
    cm.created_at;
$function$;

REVOKE ALL ON FUNCTION "public"."debug_member_identity_links"(p_email text, p_club_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."debug_member_identity_links"(p_email text, p_club_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.debug_my_profile()
 RETURNS TABLE(member_profile_id uuid, is_admin boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    mp.id,
    exists (
      select 1
      from club_memberships cm
      where cm.member_profile_id = mp.id
        and cm.role = 'admin'
    )
  from member_profiles mp
  where mp.user_id = auth.uid()
$function$;

REVOKE ALL ON FUNCTION "public"."debug_my_profile"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."debug_my_profile"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."debug_my_profile"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."debug_my_profile"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."debug_my_profile"() TO "service_role";

CREATE OR REPLACE FUNCTION public.delete_fixture(p_fixture_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.delete_fixture(p_fixture_id, null::text)
$function$;

REVOKE ALL ON FUNCTION "public"."delete_fixture"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."delete_fixture"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."delete_fixture"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.delete_fixture(p_fixture_id uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_preview jsonb;
begin
  perform 1 from public.fixtures where id = p_fixture_id for update;
  if not found then raise exception 'Fixture not found'; end if;
  v_preview := public.fixture_deletion_preview(p_fixture_id);
  if not (v_preview->>'can_delete')::boolean then
    raise exception 'Deletion is blocked because %',
      v_preview->'blockers';
  end if;
  perform set_config('app.audit_reason', coalesce(trim(p_reason),''), true);
  perform set_config('app.audit_delete_mode', 'ordinary', true);
  delete from public.club_schedule_items where linked_fixture_id = p_fixture_id;
  delete from public.fixtures where id = p_fixture_id;
  return true;
end $function$;

REVOKE ALL ON FUNCTION "public"."delete_fixture"(p_fixture_id uuid, p_reason text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."delete_fixture"(p_fixture_id uuid, p_reason text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."delete_fixture"(p_fixture_id uuid, p_reason text) TO "service_role";

CREATE OR REPLACE FUNCTION public.delete_marker_volunteer_from_view()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.club_member_volunteer_roles
  where id = old.volunteer_role_id
    and lower(btrim(volunteer_role)) = 'marker';

  return old;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."delete_marker_volunteer_from_view"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."delete_marker_volunteer_from_view"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."delete_marker_volunteer_from_view"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."delete_marker_volunteer_from_view"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."delete_marker_volunteer_from_view"() TO "service_role";

CREATE OR REPLACE FUNCTION public.enforce_non_guest_fixture_notification_actor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
begin
  if auth.uid() is not null
     and new.fixture_id is not null
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not exists (
       select 1
       from public.app_superusers su
       where su.user_id = auth.uid()
     )
     and not exists (
       select 1
       from public.fixtures f
       join public.club_memberships cm
         on cm.club_id = f.club_id
        and cm.member_profile_id = public.my_member_profile_id()
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
       where f.id = new.fixture_id
     ) then
    raise exception 'Guest members cannot create fixture communications.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."enforce_non_guest_fixture_notification_actor"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."enforce_non_guest_fixture_notification_actor"() TO "service_role";

CREATE OR REPLACE FUNCTION public.enforce_operational_mailing_list_member_eligibility()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if coalesce(new.is_active, false)
     and not exists (
       select 1
       from public.mailing_lists ml
       join public.club_memberships cm
         on cm.club_id = ml.club_id
        and cm.member_profile_id = new.member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
       where ml.id = new.mailing_list_id
     ) then
    raise exception
      'Operational mailing-list membership requires an active non-Guest club member.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."enforce_operational_mailing_list_member_eligibility"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."enforce_operational_mailing_list_member_eligibility"() TO "service_role";

CREATE OR REPLACE FUNCTION public.fixture_deletion_preview(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f public.fixtures;
  v_actor uuid := auth.uid();
  v_is_super boolean;
  v_is_manager boolean;
  v_is_creator boolean;
  v_rsvps integer;
  v_selected integer;
  v_assigned integer;
  v_marker_requests integer;
  v_email_queue integer;
  v_notification_queue integer;
  v_app_notifications integer;
  v_email_log integer;
  v_email_actions integer;
  v_communication_audit integer;
  v_diary integer;
  v_ever_published boolean;
  v_has_players boolean;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into f from public.fixtures where id = p_fixture_id;
  if not found then raise exception 'Fixture not found'; end if;

  select exists(select 1 from public.app_superusers s where s.user_id = v_actor)
    into v_is_super;
  select public.can_manage_fixture(f.id) into v_is_manager;
  select f.created_by_user_id = v_actor and exists(
    select 1 from public.club_memberships cm
    join public.member_profiles mp on mp.id = cm.member_profile_id
    where mp.user_id = v_actor and cm.club_id = f.club_id and cm.is_active
      and cm.role::text <> 'guest'
  ) into v_is_creator;
  v_is_creator := coalesce(v_is_creator, false);
  if not (v_is_super or v_is_manager or v_is_creator) then
    raise exception 'Not authorized to delete this fixture';
  end if;

  select count(*) into v_rsvps from public.fixture_rsvps where fixture_id = f.id;
  select count(*) into v_selected from public.team_selection_members m
    join public.team_selections s on s.id = m.team_selection_id
    where s.fixture_id = f.id;
  select count(*) into v_assigned from public.fixture_rink_assignments
    where fixture_id = f.id and member_profile_id is not null;
  select count(*) into v_marker_requests from public.fixture_marker_requests mr
    join public.fixture_rinks fr on fr.id = mr.fixture_rink_id
    where fr.fixture_id = f.id;
  select count(*) into v_email_queue from public.email_queue where fixture_id = f.id;
  select count(*) into v_notification_queue from public.notification_queue where fixture_id = f.id;
  select count(*) into v_app_notifications from public.app_notifications where fixture_id = f.id;
  select count(*) into v_email_log from public.fixture_email_log where fixture_id = f.id;
  select count(*) into v_email_actions from public.email_action_requests where fixture_id = f.id;
  select count(*) into v_communication_audit from public.fixture_communication_audit where fixture_id = f.id;
  select count(*) into v_diary from public.club_schedule_items where linked_fixture_id = f.id;
  select
    exists(select 1 from public.team_selections s where s.fixture_id = f.id
      and (s.status::text = 'published' or s.published_at is not null))
    or exists(select 1 from public.audit_journal j where j.fixture_id = f.id
      and j.record_type = 'team_selections' and j.action = 'published')
    into v_ever_published;

  v_has_players := v_rsvps > 0 or v_selected > 0
    or v_assigned > 0 or v_marker_requests > 0;

  return jsonb_build_object(
    'can_delete', not v_has_players,
    'can_force_delete', v_is_super and v_has_players,
    'is_superuser', v_is_super,
    'is_creator', v_is_creator,
    'has_players', v_has_players,
    'ever_published', v_ever_published,
    'rsvps', v_rsvps, 'selected_members', v_selected,
    'rink_assignments', v_assigned, 'marker_requests', v_marker_requests,
    'email_queue', v_email_queue, 'notification_queue', v_notification_queue,
    'app_notifications', v_app_notifications, 'fixture_email_log', v_email_log,
    'email_actions', v_email_actions, 'communication_audit', v_communication_audit,
    'diary_items', v_diary,
    'blockers', to_jsonb(array_remove(array[
      case when v_has_players then 'players are attached' end
    ]::text[], null))
  );
end $function$;

REVOKE ALL ON FUNCTION "public"."fixture_deletion_preview"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."fixture_deletion_preview"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."fixture_deletion_preview"(p_fixture_id uuid) TO "service_role";

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

REVOKE ALL ON FUNCTION "public"."get_authorized_team_sheet_data"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_authorized_team_sheet_data"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_authorized_team_sheet_data"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_club_member_picker_list(p_club_id uuid, p_section text DEFAULT 'open'::text, p_team_id uuid DEFAULT NULL::uuid, p_fixture_id uuid DEFAULT NULL::uuid, p_rsvp_statuses text[] DEFAULT NULL::text[], p_search text DEFAULT NULL::text, p_use_fixture_section boolean DEFAULT true)
 RETURNS TABLE(member_profile_id uuid, display_name text, picker_name text, email_address text, phone text, sex_at_birth text, preferred_position text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
with fixture_context as (
  select
    case
      when p_fixture_id is not null and p_use_fixture_section = true then
        (
          select lower(f.section::text)
          from public.fixtures f
          where f.id = p_fixture_id
          limit 1
        )
      else
        lower(coalesce(p_section, 'open'))
    end as effective_section
)

select
  mp.id as member_profile_id,
  coalesce(
    nullif(trim(mp.display_name), ''),
    nullif(trim(concat_ws(' ', mp.first_name, mp.last_name)), ''),
    'Unnamed member'
  ) as display_name,
  case
    when nullif(trim(mp.last_name), '') is not null then
      trim(concat_ws(', ',
        nullif(trim(mp.last_name), ''),
        nullif(trim(mp.first_name), '')
      ))
    else
      coalesce(
        nullif(trim(mp.display_name), ''),
        nullif(trim(concat_ws(' ', mp.first_name, mp.last_name)), ''),
        'Unnamed member'
      )
  end as picker_name,
  mp.email_address,
  mp.phone,
  mp.sex_at_birth,
  mp.preferred_position

from public.member_profiles mp
cross join fixture_context fc

where
  (
    current_setting('role',true) = 'service_role'
    or (session_user='postgres' and coalesce(current_setting('role',true),'none') in ('none','postgres'))
    or (auth.uid() is not null and (
      public.is_app_superuser()
      or exists(select 1 from public.club_memberships caller
        where caller.club_id=p_club_id and caller.member_profile_id=public.my_member_profile_id()
          and caller.is_active)
    ))
  )
  and (p_fixture_id is null or exists(select 1 from public.fixtures requested_fixture where requested_fixture.id=p_fixture_id and requested_fixture.club_id=p_club_id))
  and (p_team_id is null or exists(select 1 from public.teams requested_team where requested_team.id=p_team_id and requested_team.club_id=p_club_id))
  and exists (
  select 1
  from public.club_memberships cm
  where cm.club_id = p_club_id
    and cm.member_profile_id = mp.id
    and cm.is_active = true
    and lower(cm.role::text) <> 'guest'
)

  and (
    fc.effective_section in ('open', 'mixed')
    or (
      fc.effective_section in ('men', 'mens')
      and lower(coalesce(mp.sex_at_birth, '')) = 'male'
    )
    or (
      fc.effective_section in ('ladies', 'women')
      and lower(coalesce(mp.sex_at_birth, '')) = 'female'
    )
  )

  and (
    p_team_id is null
    or exists (
      select 1
      from public.team_members tm
      where tm.team_id = p_team_id
        and tm.member_profile_id = mp.id
    )
  )

  and (
    p_fixture_id is null
    or p_rsvp_statuses is null
    or exists (
      select 1
      from public.fixture_rsvps fr
      where fr.fixture_id = p_fixture_id
        and fr.member_profile_id = mp.id
        and fr.status::text = any(p_rsvp_statuses)
    )
  )

  and (
    p_search is null
    or trim(p_search) = ''
    or (
      coalesce(mp.display_name, '') ilike '%' || p_search || '%'
      or concat_ws(' ', mp.first_name, mp.last_name) ilike '%' || p_search || '%'
      or coalesce(mp.email_address, '') ilike '%' || p_search || '%'
      or coalesce(mp.phone, '') ilike '%' || p_search || '%'
    )
  )

order by
  lower(coalesce(mp.last_name, '')),
  lower(coalesce(mp.first_name, '')),
  lower(coalesce(mp.display_name, ''));
$function$;

REVOKE ALL ON FUNCTION "public"."get_club_member_picker_list"(p_club_id uuid, p_section text, p_team_id uuid, p_fixture_id uuid, p_rsvp_statuses text[], p_search text, p_use_fixture_section boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_club_member_picker_list"(p_club_id uuid, p_section text, p_team_id uuid, p_fixture_id uuid, p_rsvp_statuses text[], p_search text, p_use_fixture_section boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_club_member_picker_list"(p_club_id uuid, p_section text, p_team_id uuid, p_fixture_id uuid, p_rsvp_statuses text[], p_search text, p_use_fixture_section boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_email_queue_cron_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
declare v_job cron.job;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select * into v_job from cron.job
    where jobname='bowls-process-email-queue' limit 1;
  if not found then return jsonb_build_object('found',false,'active',false); end if;
  return jsonb_build_object('found',true,'job_id',v_job.jobid,
    'job_name',v_job.jobname,'schedule',v_job.schedule,'active',v_job.active);
end $function$;

REVOKE ALL ON FUNCTION "public"."get_email_queue_cron_status"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_email_queue_cron_status"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_email_queue_cron_status"() TO "service_role";

CREATE OR REPLACE FUNCTION public.get_email_responses_cron_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
declare v_job cron.job; v_state public.email_inbox_sync_state;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select * into v_job from cron.job where jobname='bowls-process-email-responses' limit 1;
  select * into v_state from public.email_inbox_sync_state order by updated_at desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    'found',v_job.jobid is not null,'active',coalesce(v_job.active,false),
    'job_id',v_job.jobid,'job_name',v_job.jobname,'schedule',v_job.schedule,
    'mailbox',v_state.mailbox,'last_checked_at',v_state.last_checked_at,
    'last_success_at',v_state.last_success_at,'last_error',v_state.last_error
  ));
end $function$;

REVOKE ALL ON FUNCTION "public"."get_email_responses_cron_status"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_email_responses_cron_status"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_email_responses_cron_status"() TO "service_role";

CREATE OR REPLACE FUNCTION public.get_green_maintenance_impacts(p_green_area_id uuid, p_rink_labels text[], p_start_at timestamp with time zone, p_end_at timestamp with time zone)
 RETURNS TABLE(source_kind text, source_id uuid, linked_fixture_id uuid, title text, item_start_at timestamp with time zone, item_end_at timestamp with time zone, rinks_required integer, allocated_rinks integer, directly_uses_maintenance_rink boolean, capacity_conflict boolean, affected_rink_labels text[], available_rinks integer, peak_committed_rinks integer, capacity_shortfall integer, impact_reason text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rink_count integer;
begin
  if p_green_area_id is null then
    raise exception 'Green area id is required.';
  end if;

  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'A valid maintenance start/end time is required.';
  end if;

  select ga.rink_count
    into v_rink_count
  from public.green_areas ga
  where ga.id = p_green_area_id;

  if v_rink_count is null then
    raise exception 'Green area was not found.';
  end if;

  if not exists (
    select 1
    from unnest(coalesce(p_rink_labels, array[]::text[])) as u(x)
    where nullif(btrim(x), '') is not null
  ) then
    raise exception 'At least one rink label is required.';
  end if;

  return query
  with generated_labels as (
    select
      i as rink_number,
      case
        when ga.scheme_type = 'custom_list' then ga.custom_labels[i]
        when ga.scheme_type = 'alpha' then coalesce(ga.scheme_prefix, '') || chr(64 + i)
        else
          coalesce(ga.scheme_prefix, '') ||
          case
            when coalesce(ga.scheme_padding, 0) > 0
              then lpad(i::text, ga.scheme_padding, '0')
            else i::text
          end
      end as rink_label
    from public.green_areas ga
    cross join generate_series(1, ga.rink_count) as i
    where ga.id = p_green_area_id
  ),
  requested_labels as (
    select distinct nullif(btrim(x), '') as rink_label
    from unnest(coalesce(p_rink_labels, array[]::text[])) as u(x)
    where nullif(btrim(x), '') is not null
  ),
  requested_rinks as (
    select gl.rink_number, gl.rink_label
    from requested_labels rl
    join generated_labels gl on gl.rink_label = rl.rink_label
  ),
  invalid_requested as (
    select rl.rink_label
    from requested_labels rl
    left join generated_labels gl on gl.rink_label = rl.rink_label
    where gl.rink_label is null
  ),
  fixture_items as (
    select
      'fixture'::text as source_kind,
      f.id as source_id,
      f.id as linked_fixture_id,
      case
        when nullif(btrim(f.team_name), '') is not null
             and nullif(btrim(f.opponent_name), '') is not null
          then btrim(f.team_name) || ' v ' || btrim(f.opponent_name)
        when nullif(btrim(f.opponent_name), '') is not null
          then 'v ' || btrim(f.opponent_name)
        when nullif(btrim(f.team_name), '') is not null
          then btrim(f.team_name)
        else coalesce(nullif(btrim(ct.name), ''), 'Fixture')
      end as title,
      f.start_at as item_start_at,
      coalesce(f.end_at, upper(f.time_range), f.start_at + interval '3 hours') as item_end_at,
      greatest(coalesce(f.rinks_required, 0), 0)::integer as rinks_required,
      count(fr.id) filter (where fr.home_rink_label is not null)::integer as allocated_rinks,
      coalesce(bool_or(rr.rink_label is not null), false) as directly_uses_maintenance_rink,
      coalesce(
        array_agg(distinct fr.home_rink_label)
          filter (where rr.rink_label is not null),
        array[]::text[]
      ) as affected_rink_labels
    from public.fixtures f
    left join public.competition_types ct on ct.id = f.competition_type_id
    left join public.fixture_rinks fr on fr.fixture_id = f.id
    left join requested_rinks rr on rr.rink_label = fr.home_rink_label
    where f.green_area_id = p_green_area_id
      and f.is_home = true
      and tstzrange(
            f.start_at,
            coalesce(f.end_at, upper(f.time_range), f.start_at + interval '3 hours'),
            '[)'
          ) && tstzrange(p_start_at, p_end_at, '[)')
    group by
      f.id,
      f.team_name,
      f.opponent_name,
      ct.name,
      f.start_at,
      f.end_at,
      f.time_range,
      f.rinks_required
  ),
  schedule_items as (
    select
      'schedule_item'::text as source_kind,
      csi.id as source_id,
      csi.linked_fixture_id,
      coalesce(nullif(btrim(csi.title), ''), 'Schedule item') as title,
      csi.start_at as item_start_at,
      csi.end_at as item_end_at,
      greatest(coalesce(csi.rinks_required, 0), 0)::integer as rinks_required,
      0::integer as allocated_rinks,
      false as directly_uses_maintenance_rink,
      array[]::text[] as affected_rink_labels
    from public.club_schedule_items csi
    where csi.green_area_id = p_green_area_id
      and csi.is_home = true
      and csi.needs_rinks = true
      and coalesce(csi.rinks_required, 0) > 0
      and csi.linked_fixture_id is null
      and tstzrange(csi.start_at, csi.end_at, '[)')
          && tstzrange(p_start_at, p_end_at, '[)')
  ),
  commitments as (
    select * from fixture_items
    union all
    select * from schedule_items
  ),
  existing_maintenance as (
    select m.rink_number, m.start_at, m.end_at
    from public.green_rink_maintenance m
    where m.green_area_id = p_green_area_id
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
  ),
  boundary_points as (
    select p_start_at as point
    union select p_end_at
    union
    select greatest(c.item_start_at, p_start_at) from commitments c
    union
    select least(c.item_end_at, p_end_at) from commitments c
    union
    select greatest(m.start_at, p_start_at) from existing_maintenance m
    union
    select least(m.end_at, p_end_at) from existing_maintenance m
  ),
  ordered_boundaries as (
    select point as segment_start,
           lead(point) over (order by point) as segment_end
    from boundary_points
    where point >= p_start_at and point <= p_end_at
  ),
  segments as (
    select segment_start, segment_end
    from ordered_boundaries
    where segment_end is not null and segment_start < segment_end
  ),
  segment_loads as (
    select
      s.segment_start,
      s.segment_end,
      coalesce((
        select sum(c.rinks_required)::integer
        from commitments c
        where tstzrange(c.item_start_at, c.item_end_at, '[)')
              && tstzrange(s.segment_start, s.segment_end, '[)')
      ), 0) as committed_rinks,
      (
        select count(distinct u.rink_number)::integer
        from (
          select em.rink_number
          from existing_maintenance em
          where tstzrange(em.start_at, em.end_at, '[)')
                && tstzrange(s.segment_start, s.segment_end, '[)')
          union
          select rr.rink_number
          from requested_rinks rr
        ) u
      ) as unavailable_rinks
    from segments s
  ),
  assessed as (
    select
      c.*,
      exists (
        select 1
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
          and sl.committed_rinks > greatest(v_rink_count - sl.unavailable_rinks, 0)
      ) as capacity_conflict,
      coalesce((
        select min(greatest(v_rink_count - sl.unavailable_rinks, 0))::integer
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ), greatest(v_rink_count - (select count(*)::integer from requested_rinks), 0)::integer) as available_rinks,
      coalesce((
        select max(sl.committed_rinks)::integer
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ), 0) as peak_committed_rinks,
      coalesce((
        select max(greatest(sl.committed_rinks - greatest(v_rink_count - sl.unavailable_rinks, 0), 0))::integer
        from segment_loads sl
        where tstzrange(sl.segment_start, sl.segment_end, '[)')
              && tstzrange(c.item_start_at, c.item_end_at, '[)')
      ), 0) as capacity_shortfall
    from commitments c
  )
  select
    a.source_kind,
    a.source_id,
    a.linked_fixture_id,
    a.title,
    a.item_start_at,
    a.item_end_at,
    a.rinks_required,
    a.allocated_rinks,
    a.directly_uses_maintenance_rink,
    a.capacity_conflict,
    a.affected_rink_labels,
    a.available_rinks,
    a.peak_committed_rinks,
    a.capacity_shortfall,
    case
      when a.directly_uses_maintenance_rink and a.capacity_conflict
        then 'Uses a rink being maintained and the remaining green capacity is insufficient.'
      when a.directly_uses_maintenance_rink
        then 'Uses a rink being maintained and requires rink reassignment.'
      when a.capacity_conflict
        then 'Maintenance reduces the remaining green capacity below the committed rink demand.'
      else ''
    end as impact_reason
  from assessed a
  where not exists (select 1 from invalid_requested)
    and (a.directly_uses_maintenance_rink or a.capacity_conflict)
  order by a.item_start_at, a.source_kind, a.title;

  if exists (
    with generated_labels as (
      select case
        when ga.scheme_type = 'custom_list' then ga.custom_labels[i]
        when ga.scheme_type = 'alpha' then coalesce(ga.scheme_prefix, '') || chr(64 + i)
        else coalesce(ga.scheme_prefix, '') || case
          when coalesce(ga.scheme_padding, 0) > 0 then lpad(i::text, ga.scheme_padding, '0')
          else i::text
        end
      end as rink_label
      from public.green_areas ga
      cross join generate_series(1, ga.rink_count) i
      where ga.id = p_green_area_id
    )
    select 1
    from (
      select distinct nullif(btrim(x), '') as rink_label
      from unnest(coalesce(p_rink_labels, array[]::text[])) u(x)
      where nullif(btrim(x), '') is not null
    ) r
    left join generated_labels g on g.rink_label = r.rink_label
    where g.rink_label is null
  ) then
    raise exception 'One or more maintenance rink labels are not valid for this green.';
  end if;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."get_green_maintenance_impacts"(p_green_area_id uuid, p_rink_labels text[], p_start_at timestamp with time zone, p_end_at timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_green_maintenance_impacts"(p_green_area_id uuid, p_rink_labels text[], p_start_at timestamp with time zone, p_end_at timestamp with time zone) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_green_maintenance_impacts"(p_green_area_id uuid, p_rink_labels text[], p_start_at timestamp with time zone, p_end_at timestamp with time zone) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_green_rink_availability(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(rink_label text, is_booked boolean, booked_text text, background_hex text, foreground_hex text, total_rinks integer, physically_booked_rinks integer, capacity_booked_rinks integer, free_capacity_rinks integer, fixture_rink_id uuid, booked_fixture_id uuid)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with green as (
    select *
    from public.green_areas
    where id = p_green_area_id
  ),
  labels as (
    select
      i,
      case
        when g.scheme_type = 'custom_list' then g.custom_labels[i]
        when g.scheme_type = 'alpha' then coalesce(g.scheme_prefix, '') || chr(64 + i)
        else
          coalesce(g.scheme_prefix, '') ||
          case
            when coalesce(g.scheme_padding, 0) > 0
              then lpad(i::text, g.scheme_padding, '0')
            else i::text
          end
      end as rink_label
    from green g
    cross join generate_series(1, g.rink_count) as i
  ),
  fixture_capacity as (
    select coalesce(sum(f.rinks_required), 0)::integer as booked
    from green g
    left join public.fixtures f
      on f.green_area_id = g.id
     and f.cancelled_at is null
     and f.time_range && tstzrange(p_start_at, p_end_at, '[)')
     and (p_exclude_fixture_id is null or f.id <> p_exclude_fixture_id)
  ),
  maintenance_capacity as (
    select count(distinct m.rink_number)::integer as blocked
    from public.green_rink_maintenance m
    where m.green_area_id = p_green_area_id
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
  ),
  capacity as (
    select
      g.rink_count as total_rinks,
      (fc.booked + mc.blocked)::integer as capacity_booked_rinks
    from green g
    cross join fixture_capacity fc
    cross join maintenance_capacity mc
  ),
  booked as (
    select
      fr.home_rink_label,
      (array_agg(fr.id order by f.start_at, fr.id))[1] as fixture_rink_id,
      (array_agg(fr.fixture_id order by f.start_at, fr.id))[1] as booked_fixture_id,
      string_agg(
        coalesce(ct.name, 'Fixture') || ' ' ||
        to_char(f.start_at at time zone 'Europe/London', 'HH24:MI') ||
        ' - ' ||
        to_char(f.end_at at time zone 'Europe/London', 'HH24:MI') ||
        E'\n' ||
        case
          when coalesce(ct.is_internal, false) = true then
            'Captain: ' || coalesce(
              nullif(trim(coalesce(captain.first_name, '') || ' ' || coalesce(captain.last_name, '')), ''),
              'Not set'
            )
          else coalesce(opponent.name, 'Opponent not set')
        end,
        E'\n\n'
      ) as booked_text,
      min(cs.background_hex) as background_hex,
      min(cs.foreground_hex) as foreground_hex
    from public.fixture_rinks fr
    join public.fixtures f on f.id = fr.fixture_id
    left join public.competition_types ct on ct.id = f.competition_type_id
    left join public.fixture_colour_schemes cs on cs.id = ct.colour_scheme_id
    left join public.member_profiles captain on captain.id = f.captain_member_profile_id
    left join public.venues opponent on opponent.id = f.opponent_venue_id
    where f.green_area_id = p_green_area_id
      and f.cancelled_at is null
      and fr.home_rink_label is not null
      and f.time_range && tstzrange(p_start_at, p_end_at, '[)')
      and (p_exclude_fixture_id is null or f.id <> p_exclude_fixture_id)
    group by fr.home_rink_label
  ),
  maintenance as (
    select
      l.rink_label,
      string_agg(
        coalesce(nullif(btrim(m.reason), ''), 'Maintenance') || ' ' ||
        to_char(m.start_at at time zone 'Europe/London', 'HH24:MI') || ' - ' ||
        to_char(m.end_at at time zone 'Europe/London', 'HH24:MI'),
        E'\n\n'
      ) as maintenance_text
    from public.green_rink_maintenance m
    join labels l on l.i = m.rink_number
    where m.green_area_id = p_green_area_id
      and m.status = 'active'
      and m.time_range && tstzrange(p_start_at, p_end_at, '[)')
    group by l.rink_label
  ),
  physical_count as (
    select count(distinct rink_label)::integer as physically_booked_rinks
    from (
      select home_rink_label as rink_label from booked
      union all
      select rink_label from maintenance
    ) x
  )
  select
    l.rink_label,
    (b.home_rink_label is not null or m.rink_label is not null) as is_booked,
    case
      when m.rink_label is not null then m.maintenance_text
      else coalesce(b.booked_text, '')
    end as booked_text,
    case
      when m.rink_label is not null then '#FEE2E2'
      else coalesce(b.background_hex, '#FEE2E2')
    end as background_hex,
    case
      when m.rink_label is not null then '#991B1B'
      else coalesce(b.foreground_hex, '#991B1B')
    end as foreground_hex,
    c.total_rinks,
    pc.physically_booked_rinks,
    c.capacity_booked_rinks,
    greatest(c.total_rinks - c.capacity_booked_rinks, 0)::integer as free_capacity_rinks,
    b.fixture_rink_id,
    b.booked_fixture_id
  from labels l
  cross join capacity c
  cross join physical_count pc
  left join booked b on b.home_rink_label = l.rink_label
  left join maintenance m on m.rink_label = l.rink_label
  order by l.i;
$function$;

REVOKE ALL ON FUNCTION "public"."get_green_rink_availability"(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_green_rink_availability"(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."get_green_rink_availability"(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."get_green_rink_availability"(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_green_rink_availability"(p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_notification_queue_cron_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
declare v_job cron.job;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select * into v_job from cron.job
    where jobname='bowls-process-notification-queue' limit 1;
  if not found then return jsonb_build_object('found',false,'active',false); end if;
  return jsonb_build_object('found',true,'job_id',v_job.jobid,
    'job_name',v_job.jobname,'schedule',v_job.schedule,'active',v_job.active);
end $function$;

REVOKE ALL ON FUNCTION "public"."get_notification_queue_cron_status"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_notification_queue_cron_status"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_notification_queue_cron_status"() TO "service_role";

CREATE OR REPLACE FUNCTION public.get_queue_admin_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- current_user is the function owner here; inspect the invoking SQL role instead.
  if not (
    current_setting('role', true) = 'service_role'
    or (session_user = 'postgres' and coalesce(current_setting('role', true), 'none') in ('none','postgres'))
    or (auth.uid() is not null and public.is_app_superuser())
  ) then
    raise exception 'Superuser or server access required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'notification_pending',
      (
        select count(*)
        from public.notification_queue
        where status = 'pending'
      ),

    'notification_failed',
      (
        select count(*)
        from public.notification_queue
        where status = 'failed'
      ),

    'email_pending',
      (
        select count(*)
        from public.email_queue
        where status = 'pending'
      ),

    'email_failed',
      (
        select count(*)
        from public.email_queue
        where status = 'failed'
      ),

    'email_sent',
      (
        select count(*)
        from public.email_queue
        where status = 'sent'
      ),

    'last_notification_error',
      (
        select last_error
        from public.notification_queue
        where status = 'failed'
          and last_error is not null
        order by created_at desc
        limit 1
      ),

    'last_email_error',
      (
        select last_error
        from public.email_queue
        where status = 'failed'
          and last_error is not null
        order by created_at desc
        limit 1
      )
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."get_queue_admin_stats"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."get_queue_admin_stats"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."get_queue_admin_stats"() TO "service_role";

CREATE OR REPLACE FUNCTION public.green_area_must_be_home_venue()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v record;
begin
  select * into v from public.venues where id = new.venue_id;

  if v is null then
    raise exception 'Invalid venue_id';
  end if;

  -- Only allow green areas on home venues
  if v.is_home_venue is distinct from true then
    raise exception 'Green areas can only be created for home venues';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."green_area_must_be_home_venue"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."green_area_must_be_home_venue"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."green_area_must_be_home_venue"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."green_area_must_be_home_venue"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."green_area_must_be_home_venue"() TO "service_role";

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
  insert into public.member_profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', new.email, 'New member'));
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."handle_new_user"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."handle_new_user"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."handle_new_user"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."handle_new_user"() TO "service_role";

CREATE OR REPLACE FUNCTION public.is_app_superuser()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  );
$function$;

REVOKE ALL ON FUNCTION "public"."is_app_superuser"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."is_app_superuser"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."is_app_superuser"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."is_app_superuser"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."is_app_superuser"() TO "service_role";

CREATE OR REPLACE FUNCTION public.is_club_admin(p_club_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.club_memberships cm
    join public.member_profiles mp on mp.id = cm.member_profile_id
    where cm.club_id = p_club_id
      and cm.is_active = true
      and cm.role = 'admin'
      and mp.user_id = auth.uid()
  )
$function$;

REVOKE ALL ON FUNCTION "public"."is_club_admin"(p_club_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."is_club_admin"(p_club_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."is_club_admin"(p_club_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."is_club_admin"(p_club_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."is_club_admin"(p_club_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.is_fixture_captain(p_fixture_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  select exists (
    select 1
    from public.fixtures f
    where f.id = p_fixture_id
      and f.captain_member_profile_id = public.my_member_profile_id()
  )
$function$;

REVOKE ALL ON FUNCTION "public"."is_fixture_captain"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."is_fixture_captain"(p_fixture_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."is_fixture_captain"(p_fixture_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."is_fixture_captain"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."is_fixture_captain"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.issue_email_action_response_token(p_request_id uuid, p_email_queue_id uuid, p_response_token_hash text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_updated integer;
begin
  if p_request_id is null
     or p_email_queue_id is null
     or coalesce(p_response_token_hash, '') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  update public.email_action_requests ear
     set response_token_hash = p_response_token_hash,
         updated_at = now()
   where ear.id = p_request_id
     and ear.source_email_queue_id = p_email_queue_id
     and ear.response_protocol_version = 2
     and ear.response_token_hash is null
     and ear.status = 'pending'
     and exists (
       select 1
       from public.email_queue eq
       where eq.id = p_email_queue_id
         and eq.status = 'processing'
         and eq.sent_at is null
     );

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."issue_email_action_response_token"(p_request_id uuid, p_email_queue_id uuid, p_response_token_hash text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."issue_email_action_response_token"(p_request_id uuid, p_email_queue_id uuid, p_response_token_hash text) TO "service_role";

CREATE OR REPLACE FUNCTION public.manage_fixture_team_structure(p_fixture_id uuid, p_action text, p_fixture_rink_id uuid DEFAULT NULL::uuid, p_format text DEFAULT NULL::text, p_home_rink_label text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_fixture public.fixtures%rowtype;
  v_rink public.fixture_rinks%rowtype;
  v_actor_member_profile_id uuid;
  v_is_superuser boolean := false;
  v_has_permission boolean := false;
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_format text := lower(btrim(coalesce(p_format, '')));
  v_new_players integer;
  v_old_players integer;
  v_next_team integer;
  v_middle_count integer;
  v_i integer;
  v_new_rink_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select f.* into v_fixture
  from public.fixtures f
  where f.id = p_fixture_id
  for update;

  if not found then raise exception 'Fixture not found.'; end if;
  if v_fixture.cancelled_at is not null then
    raise exception 'A cancelled fixture cannot be structurally changed.';
  end if;

  select public.my_member_profile_id() into v_actor_member_profile_id;
  select exists(select 1 from public.app_superusers s where s.user_id=auth.uid())
    into v_is_superuser;
  select v_is_superuser or exists(
    select 1 from public.club_memberships cm
    where cm.club_id=v_fixture.club_id
      and cm.member_profile_id=v_actor_member_profile_id
      and cm.is_active=true
      and lower(cm.role::text)<>'guest'
      and (lower(cm.role::text) in ('admin','selector')
        or v_actor_member_profile_id=v_fixture.captain_member_profile_id
        or v_actor_member_profile_id=v_fixture.vice_captain_member_profile_id)
  ) into v_has_permission;
  if not v_has_permission then
    raise exception 'You do not have permission to change the team structure.';
  end if;

  if v_action not in ('add','update','delete') then
    raise exception 'Unsupported team structure action.';
  end if;

  if v_action in ('add','update') then
    v_new_players := case v_format
      when 'singles' then 1 when 'pairs' then 2 when 'aussie_pairs' then 2
      when 'triples' then 3 when 'fours' then 4 when 'rinks' then 4
      else null end;
    if v_new_players is null then raise exception 'Unsupported team format.'; end if;

    if nullif(btrim(coalesce(p_home_rink_label,'')),'') is not null then
      if not v_fixture.is_home or v_fixture.green_area_id is null then
        raise exception 'Only a home fixture can be assigned a physical rink.';
      end if;
      if exists(
        select 1 from public.fixture_rinks fr
        where fr.fixture_id=p_fixture_id
          and fr.id is distinct from p_fixture_rink_id
          and fr.home_rink_label=p_home_rink_label
      ) then raise exception 'That physical rink is already assigned to another team.'; end if;
      if not exists(
        select 1 from public.get_green_rink_availability(
          v_fixture.green_area_id,v_fixture.start_at,v_fixture.end_at,p_fixture_id
        ) a where a.rink_label=p_home_rink_label and a.is_booked=false
      ) then raise exception 'That physical rink is not available.'; end if;
    end if;
  end if;

  if v_action='add' then
    select coalesce(max(fr.fixture_rink_no),0)+1 into v_next_team
    from public.fixture_rinks fr where fr.fixture_id=p_fixture_id;
    insert into public.fixture_rinks(
      fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label,marker_required
    ) values(
      p_fixture_id,v_next_team,v_format,v_new_players,
      nullif(btrim(coalesce(p_home_rink_label,'')),''),false
    ) returning id into v_new_rink_id;
  else
    select fr.* into v_rink from public.fixture_rinks fr
    where fr.id=p_fixture_rink_id and fr.fixture_id=p_fixture_id for update;
    if not found then raise exception 'The selected team was not found.'; end if;

    if v_action='delete' then
      if (select count(*) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id) <= 1 then
        raise exception 'A rink-based fixture must retain at least one team.';
      end if;
      delete from public.fixture_rinks where id=v_rink.id;
      with numbered as (
        select id,row_number() over(order by fixture_rink_no,id)::integer n
        from public.fixture_rinks where fixture_id=p_fixture_id
      )
      update public.fixture_rinks fr set fixture_rink_no=numbered.n
      from numbered where numbered.id=fr.id;
    else
      v_old_players := v_rink.players_per_rink;
      create temporary table desired_structure_assignments(
        member_profile_id uuid, display_name text, old_position integer,
        new_position integer
      ) on commit drop;

      if v_new_players = v_old_players then
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,a.position
        from public.fixture_rink_assignments a
        where a.fixture_rink_id=v_rink.id and a.position between 1 and v_old_players;
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,a.position
        from public.fixture_rink_assignments a
        where a.fixture_rink_id=v_rink.id and a.position between 101 and 100+v_old_players;
      else
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,1
        from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=1;
        insert into desired_structure_assignments
        select a.member_profile_id,a.display_name,a.position,101
        from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=101;

        if v_old_players>1 and v_new_players>1 then
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,v_new_players
          from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=v_old_players;
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,100+v_new_players
          from public.fixture_rink_assignments a where a.fixture_rink_id=v_rink.id and a.position=100+v_old_players;
        end if;

        v_middle_count := least(greatest(v_old_players-2,0),greatest(v_new_players-2,0));
        for v_i in 1..v_middle_count loop
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,
            case when v_new_players<v_old_players then 1+v_i else a.position end
          from public.fixture_rink_assignments a
          where a.fixture_rink_id=v_rink.id
            and a.position=(case when v_new_players<v_old_players
              then v_old_players-v_middle_count+v_i-1 else 1+v_i end);
          insert into desired_structure_assignments
          select a.member_profile_id,a.display_name,a.position,
            case when v_new_players<v_old_players then 101+v_i else a.position end
          from public.fixture_rink_assignments a
          where a.fixture_rink_id=v_rink.id
            and a.position=100+(case when v_new_players<v_old_players
              then v_old_players-v_middle_count+v_i-1 else 1+v_i end);
        end loop;
      end if;

      delete from public.fixture_rink_assignments a
      where a.fixture_rink_id=v_rink.id
        and (a.position between 1 and 4 or a.position between 101 and 104);
      update public.fixture_rinks set format=v_format,players_per_rink=v_new_players,
        home_rink_label=nullif(btrim(coalesce(p_home_rink_label,'')),'')
      where id=v_rink.id;
      insert into public.fixture_rink_assignments(
        fixture_id,fixture_rink_id,member_profile_id,display_name,position
      )
      select p_fixture_id,v_rink.id,d.member_profile_id,d.display_name,d.new_position
      from desired_structure_assignments d;
    end if;
  end if;

  update public.fixtures f set
    rinks_required=(select count(*) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id),
    players_per_rink=coalesce((select max(fr.players_per_rink) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id),1)
  where f.id=p_fixture_id;

  return jsonb_build_object('fixture_id',p_fixture_id,'action',v_action,
    'fixture_rink_id',coalesce(v_new_rink_id,p_fixture_rink_id),
    'rinks_required',(select count(*) from public.fixture_rinks fr where fr.fixture_id=p_fixture_id));
end;
$function$;

REVOKE ALL ON FUNCTION "public"."manage_fixture_team_structure"(p_fixture_id uuid, p_action text, p_fixture_rink_id uuid, p_format text, p_home_rink_label text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."manage_fixture_team_structure"(p_fixture_id uuid, p_action text, p_fixture_rink_id uuid, p_format text, p_home_rink_label text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."manage_fixture_team_structure"(p_fixture_id uuid, p_action text, p_fixture_rink_id uuid, p_format text, p_home_rink_label text) TO "service_role";

CREATE OR REPLACE FUNCTION public.my_active_club_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 SELECT cm.club_id FROM public.club_memberships cm
 WHERE cm.member_profile_id = (SELECT public.my_member_profile_id())
 AND cm.is_active = true
$function$;

REVOKE ALL ON FUNCTION "public"."my_active_club_ids"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."my_active_club_ids"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."my_active_club_ids"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."my_active_club_ids"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."my_active_club_ids"() TO "service_role";

CREATE OR REPLACE FUNCTION public.my_member_profile_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 SELECT id FROM public.member_profiles
 WHERE user_id = (SELECT auth.uid()) LIMIT 1
$function$;

REVOKE ALL ON FUNCTION "public"."my_member_profile_id"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id"() TO "service_role";

CREATE OR REPLACE FUNCTION public.my_member_profile_id_norls()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id
  from public.member_profiles
  where user_id = auth.uid()
  limit 1
$function$;

REVOKE ALL ON FUNCTION "public"."my_member_profile_id_norls"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id_norls"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id_norls"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id_norls"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."my_member_profile_id_norls"() TO "service_role";

CREATE OR REPLACE FUNCTION public.my_self_subscribable_mailing_lists(p_club_id uuid)
 RETURNS TABLE(mailing_list_id uuid, name text, description text, system_key text, is_joined boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_member_profile_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select public.my_member_profile_id()
  into v_member_profile_id;

  if v_member_profile_id is null then
    raise exception 'No member profile was found for the signed-in user.';
  end if;

  if not exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = p_club_id
      and cm.member_profile_id = v_member_profile_id
      and cm.is_active = true
  ) then
    raise exception 'You are not an active member of this club.';
  end if;

  return query
  select
    ml.id,
    ml.name,
    ml.description,
    ml.system_key,
    exists (
      select 1
      from public.mailing_list_members mlm
      where mlm.mailing_list_id = ml.id
        and mlm.member_profile_id = v_member_profile_id
        and mlm.is_active = true
    ) as is_joined
  from public.mailing_lists ml
  where ml.club_id = p_club_id
    and ml.is_active = true
    and ml.allow_self_subscription = true
  order by ml.name;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."my_self_subscribable_mailing_lists"(p_club_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."my_self_subscribable_mailing_lists"(p_club_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."my_self_subscribable_mailing_lists"(p_club_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."my_self_subscribable_mailing_lists"(p_club_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."my_self_subscribable_mailing_lists"(p_club_id uuid) TO "service_role";

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
  if new.event_type not in ('fixture_selected', 'team_published_player', 'reserve_promoted')
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
      when new.event_type = 'fixture_selected'
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
      when new.event_type = 'fixture_selected'
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
    and coalesce(tsm.is_selected, false) = true
    and (
      (new.event_type in ('fixture_selected', 'team_published_player', 'reserve_promoted')
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
      (new.event_type = 'fixture_selected'
       and tsm.role::text = 'marker'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         where fra.fixture_id = f.id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
       ))
      or
      (new.event_type = 'fixture_selected'
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
$function$;

REVOKE ALL ON FUNCTION "public"."prepare_team_selection_email_action"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."prepare_team_selection_email_action"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."prepare_team_selection_email_action"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."prepare_team_selection_email_action"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."prepare_team_selection_email_action"() TO "service_role";

CREATE OR REPLACE FUNCTION public.process_fixture_notification_queue(p_fixture_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_ids uuid[];
begin
  perform public.communications_require_superuser();

  select coalesce(array_agg(nq.id order by nq.created_at), array[]::uuid[])
  into v_ids
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id and nq.status = 'pending';

  if cardinality(v_ids) = 0 then return 0; end if;

  perform set_config(
    'app.notification_queue_ids',
    array_to_string(v_ids, ','),
    true
  );
  return public.process_notification_queue(cardinality(v_ids));
end;
$function$;

REVOKE ALL ON FUNCTION "public"."process_fixture_notification_queue"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."process_fixture_notification_queue"(p_fixture_id uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."process_fixture_notification_queue"(p_fixture_id uuid) TO "authenticated";

CREATE OR REPLACE FUNCTION public.process_fixture_post_publish_changes(p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid DEFAULT NULL::uuid, p_old_start_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_old_end_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fixture record;
  v_team_selection record;

  v_actor_member_profile_id uuid;
  v_change_type text;
  v_workflow text;

  v_is_superuser boolean := false;
  v_has_permission boolean := false;

  v_action text := 'no_action';
  v_result jsonb := '{}'::jsonb;
  v_context jsonb := coalesce(p_context, '{}'::jsonb);

  v_queued_count integer := 0;
  v_marker_result jsonb := '{}'::jsonb;
  v_preselect_result jsonb := '{}'::jsonb;

  v_already_reconciled boolean := false;
  v_allow_incomplete boolean := false;
begin
  if p_fixture_id is null then
    raise exception 'Fixture id is required.';
  end if;

  v_change_type := lower(nullif(btrim(coalesce(p_change_type, '')), ''));

  if v_change_type is null then
    raise exception 'Change type is required.';
  end if;

  -- Only the server may attribute work to an explicitly supplied actor.
  if current_setting('role', true) is distinct from 'service_role' then
    if auth.uid() is null or public.my_member_profile_id() is null then
      raise exception 'A signed-in member profile is required.';
    end if;
    if p_changed_by_member_profile_id is not null
       and p_changed_by_member_profile_id is distinct from public.my_member_profile_id() then
      raise exception 'Change actor must match the signed-in member.' using errcode = '22023';
    end if;
  end if;

  if p_changed_by_member_profile_id is not null then
    v_actor_member_profile_id := p_changed_by_member_profile_id;
  else
    select public.my_member_profile_id()
    into v_actor_member_profile_id;
  end if;

  if v_actor_member_profile_id is null then
    raise exception 'A signed-in member profile is required.';
  end if;

  select
    f.id,
    f.club_id,
    f.requires_rsvp,
    f.competition_type_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id,
    ct.selection_mode,
    ct.uses_rinks,
    ct.is_internal
  into v_fixture
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found.', p_fixture_id;
  end if;

  v_workflow :=
    case
      when coalesce(v_fixture.selection_mode::text, '') = 'preselect'
        then 'preselect'
      when coalesce(v_fixture.selection_mode::text, '') = 'team'
        then 'team'
      when coalesce(v_fixture.selection_mode::text, '') = 'rsvp'
           or v_fixture.requires_rsvp = true
        then 'rsvp'
      when coalesce(v_fixture.selection_mode::text, '') in ('open_session', 'practice')
        then 'open_session'
      when coalesce(v_fixture.uses_rinks, true) = false
        then 'event'
      else 'unknown'
    end;

  select
    ts.id,
    ts.status::text as status
  into v_team_selection
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc nulls last
  limit 1;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission := public.can_manage_fixture(p_fixture_id);

  if not v_has_permission then
    raise exception 'You do not have permission to process post-publish communications for this fixture.';
  end if;

  v_already_reconciled :=
    lower(coalesce(v_context ->> 'already_reconciled', 'false')) in ('true', 't', 'yes', 'y', '1');

  v_allow_incomplete :=
    lower(coalesce(v_context ->> 'allow_incomplete', 'false')) in ('true', 't', 'yes', 'y', '1');

  /*
    Branch 1: fixture moved.

    This should only be called when the saved fixture start/end actually changed.
    It queues notifications for affected assigned members.
  */
  if v_change_type = 'fixture_moved' then
    if p_old_start_at is null then
      v_action := 'fixture_moved_missing_old_start_at';

      v_result := jsonb_build_object(
        'ok', false,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'Old start time is required for fixture_moved communications.'
      );
    else
      v_queued_count := public.queue_fixture_moved_notifications(
        p_fixture_id,
        p_old_start_at,
        p_old_end_at
      );

      v_action := 'fixture_moved_notifications_queued';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'queued_notifications', v_queued_count,
        'message', 'Fixture moved notifications were queued.'
      );
    end if;

  /*
    Branch 2: marker request opened.

    This sends to the marker mailing list, duplicate-safe per marker_request_id/volunteer.
  */
  elsif v_change_type = 'marker_request_opened' then
    v_marker_result := public.queue_open_marker_request_communications(p_fixture_id);

    v_action := 'marker_request_communications_queued';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'marker_result', coalesce(v_marker_result, '{}'::jsonb),
      'message', 'Marker request communications were queued.'
    );

  /*
    Branch 3: published.

    For normal team publication, queue publication communications.
    For Pre-Select, reconcile selected players/markers using the preselect communication routine.

    This is intentionally not destructive. It does not delete/rebuild sent emails.
  */
  elsif v_change_type = 'published' then
    if v_team_selection.id is null then
      v_action := 'published_no_team_selection';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'No team selection exists for this published fixture.'
      );

    elsif coalesce(v_team_selection.status, '') <> 'published' then
      v_action := 'team_selection_not_published';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'team_selection_status', v_team_selection.status,
        'action', v_action,
        'message', 'Team selection is not published.'
      );

    elsif v_workflow = 'preselect' then
      v_preselect_result := public.reconcile_preselect_communications(p_fixture_id);

      v_action := 'preselect_published_reconciled';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'preselect_result', coalesce(v_preselect_result, '{}'::jsonb),
        'message', 'Published Pre-Select communications were reconciled.'
      );

    elsif v_workflow = 'team' then
      v_queued_count := public.queue_team_publication_communications(
        p_fixture_id,
        v_team_selection.id,
        v_allow_incomplete
      );

      v_action := 'team_publication_communications_queued';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'queued_notifications', v_queued_count,
        'allow_incomplete', v_allow_incomplete,
        'message', 'Team publication communications were queued.'
      );

    else
      v_action := 'published_workflow_no_action';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'No publication communication action is configured for this workflow.'
      );
    end if;

  /*
    Branch 4: preselect changed after publication.

    Important: save_preselect_fixture_state may already do this atomically.
    So Flutter can pass:
      p_context := '{"already_reconciled": true}'::jsonb
    to prevent doing it twice.
  */
  elsif v_change_type = 'preselect_changed' then
    if v_workflow <> 'preselect' then
      v_action := 'preselect_changed_wrong_workflow';

      v_result := jsonb_build_object(
        'ok', false,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'preselect_changed was requested for a non-Pre-Select fixture.'
      );

    elsif v_already_reconciled then
      v_action := 'preselect_changed_already_reconciled';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'action', v_action,
        'message', 'Pre-Select communications were already reconciled by the save operation.'
      );

    elsif v_team_selection.id is null or coalesce(v_team_selection.status, '') <> 'published' then
      v_action := 'preselect_changed_not_published';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'team_selection_status', v_team_selection.status,
        'action', v_action,
        'message', 'Pre-Select fixture is not published, so no post-publish communications were queued.'
      );

    else
      v_preselect_result := public.reconcile_preselect_communications(p_fixture_id);

      v_action := 'preselect_changed_reconciled';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'preselect_result', coalesce(v_preselect_result, '{}'::jsonb),
        'message', 'Published Pre-Select communications were reconciled.'
      );
    end if;

  /*
    Branch 5: team selection changed after publication.

    This is deliberately conservative for now.
    Team delta communications need a real before/after snapshot before we email
    players who have been added, removed, promoted from reserve, etc.
  */
  elsif v_change_type = 'team_selection_changed' then
    v_action := 'team_selection_changed_audit_only';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'team_selection_id', v_team_selection.id,
      'action', v_action,
      'message', 'Team selection change was audited. Delta communications are not enabled yet.'
    );

  /*
    Branch 6: ordinary fixture details changed.

    We are not emailing for every changed field yet.
    Later we can use p_context.changed_fields to decide if venue/time/dress code/etc.
    needs notification.
  */
  elsif v_change_type = 'fixture_details_changed' then
    v_action := 'fixture_details_changed_audit_only';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'changed_fields', coalesce(v_context -> 'changed_fields', '[]'::jsonb),
      'message', 'Fixture detail change was audited. No communications were queued.'
    );

  /*
    Branch 7: manual sync.

    Safe, non-destructive reconciliation. This is not the same as Repair Centre.
  */
  elsif v_change_type = 'manual_sync' then
    if v_workflow = 'preselect'
       and v_team_selection.id is not null
       and coalesce(v_team_selection.status, '') = 'published' then

      v_preselect_result := public.reconcile_preselect_communications(p_fixture_id);

      v_action := 'manual_preselect_sync';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'action', v_action,
        'preselect_result', coalesce(v_preselect_result, '{}'::jsonb),
        'message', 'Published Pre-Select communications were manually synchronised.'
      );

    else
      v_action := 'manual_sync_no_action';

      v_result := jsonb_build_object(
        'ok', true,
        'fixture_id', p_fixture_id,
        'workflow', v_workflow,
        'change_type', v_change_type,
        'team_selection_id', v_team_selection.id,
        'team_selection_status', v_team_selection.status,
        'action', v_action,
        'message', 'No manual communication sync action is configured for this fixture state.'
      );
    end if;

  /*
    Acceptance changes are handled by the trigger queue_team_acceptance_change().
    We fixed that trigger to coalesce repeated pending changes.
  */
  elsif v_change_type = 'acceptance_changed' then
    v_action := 'acceptance_changed_handled_by_trigger';

    v_result := jsonb_build_object(
      'ok', true,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'message', 'Acceptance changes are handled by the team acceptance trigger.'
    );

  else
    v_action := 'unknown_change_type';

    v_result := jsonb_build_object(
      'ok', false,
      'fixture_id', p_fixture_id,
      'workflow', v_workflow,
      'change_type', v_change_type,
      'action', v_action,
      'message', 'Unknown post-publish change type.'
    );
  end if;

  insert into public.fixture_communication_audit (
    fixture_id,
    club_id,
    action,
    workflow,
    changed_by_member_profile_id,
    result
  )
  values (
    p_fixture_id,
    v_fixture.club_id,
    v_action,
    v_workflow,
    v_actor_member_profile_id,
    v_result
  );

  return v_result;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."process_fixture_post_publish_changes"(p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone, p_context jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_changes"(p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone, p_context jsonb) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_changes"(p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone, p_context jsonb) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_changes"(p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone, p_context jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_changes"(p_fixture_id uuid, p_change_type text, p_changed_by_member_profile_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone, p_context jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.process_fixture_post_publish_communications(p_fixture_id uuid, p_changed_by_member_profile_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return public.process_fixture_post_publish_changes(
    p_fixture_id,
    'manual_sync',
    p_changed_by_member_profile_id,
    null,
    null,
    '{}'::jsonb
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."process_fixture_post_publish_communications"(p_fixture_id uuid, p_changed_by_member_profile_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_communications"(p_fixture_id uuid, p_changed_by_member_profile_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_communications"(p_fixture_id uuid, p_changed_by_member_profile_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_communications"(p_fixture_id uuid, p_changed_by_member_profile_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."process_fixture_post_publish_communications"(p_fixture_id uuid, p_changed_by_member_profile_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.process_notification_queue(p_limit integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  r record;
  v_title text;
  v_body text;
  v_count int := 0;
  v_player_name text;
  v_fixture_label text;
  v_fixture_date_text text;
  v_home_away text;
  v_venue_name text;
  v_start_at timestamptz;
  v_created_text text;
  v_source text;

  v_team_no text;
  v_position int;
  v_players_per_rink int;
  v_role text;
  v_position_text text;
  v_home_rink_label text;

  v_team_no_int int;
  v_fixture_context_text text;
  v_team_lines text;
  v_marker_lines text;

  v_opponent_lines text;

  v_selected_position int;
  v_selected_role text;
  v_selected_role_text text;

  v_captain_name text;
  v_captain_email text;
  v_captain_phone text;
  v_is_named_marker boolean;
begin
  -- current_user is the function owner here; inspect the invoking SQL role instead.
  if not (
    current_setting('role', true) = 'service_role'
    or (session_user = 'postgres' and coalesce(current_setting('role', true), 'none') in ('none','postgres'))
    or (auth.uid() is not null and public.is_app_superuser())
  ) then
    raise exception 'Superuser or server access required' using errcode = '42501';
  end if;
  for r in
    select *
    from notification_queue
    where status = 'pending'
      and (
        nullif(
          current_setting('app.notification_queue_ids', true),
          ''
        ) is null
        or id = any (
          string_to_array(
            current_setting('app.notification_queue_ids', true),
            ','
          )::uuid[]
        )
      )
    order by created_at
    limit p_limit
  loop
    begin
      if r.target_member_profile_id is null then
        update notification_queue
        set status = 'failed',
            attempts = attempts + 1,
            last_error = 'target_member_profile_id is null'
        where id = r.id;

        continue;
      end if;

      v_player_name := coalesce(r.payload->>'player_name', 'A player');
      v_fixture_label := coalesce(r.payload->>'fixture_label', 'Fixture');
      v_home_away := coalesce(r.payload->>'home_away', '');
      v_venue_name := coalesce(r.payload->>'venue_name', '');

      begin
        v_start_at := nullif(r.payload->>'fixture_date', '')::timestamptz;
      exception
        when others then
          v_start_at := null;
      end;

      v_fixture_date_text := case
        when v_start_at is not null then
          to_char(
            v_start_at at time zone 'Europe/London',
            'DD Mon YYYY HH24:MI'
          )
        else ''
      end;

      v_created_text := to_char(
        r.created_at,
        'DD-Mon-YYYY HH24:MI'
      );

      if r.event_type = 'team_acceptance_changed' then
        v_source := 'Team Update';
        v_title := v_source;

        v_fixture_date_text := case
          when v_start_at is not null then
            to_char(
              v_start_at at time zone 'Europe/London',
              'FMDay FMDD FMMonth YYYY "at" HH24:MI'
            )
          else ''
        end;

        select exists (
          select 1
          from public.team_selection_members tsm
          join public.fixture_rink_assignments fra
            on fra.fixture_id = r.fixture_id
           and fra.member_profile_id = tsm.member_profile_id
           and fra.position = 201
          where tsm.team_selection_id = r.team_selection_id
            and tsm.member_profile_id = r.member_profile_id
            and coalesce(tsm.is_selected, false) = true
            and lower(tsm.role::text) = 'marker'
        )
        into v_is_named_marker;

        if (r.payload->>'new_acceptance') = 'accepted' then
          v_body := v_player_name
            || case
                 when v_is_named_marker then
                   ' has accepted their marker assignment for '
                 else
                   ' has accepted their selection for '
               end
            || v_fixture_label;
        elsif (r.payload->>'new_acceptance') = 'declined' then
          v_body := v_player_name
            || case
                 when v_is_named_marker then
                   ' has declined their marker assignment for '
                 else
                   ' has declined their selection for '
               end
            || v_fixture_label;
        else
          v_body := v_player_name
            || case
                 when v_is_named_marker then
                   ' has changed their marker assignment response for '
                 else
                   ' has changed their selection response for '
               end
            || v_fixture_label;
        end if;

        if v_fixture_date_text <> '' then
          v_body := v_body || ' on ' || v_fixture_date_text;
        end if;

        v_body := v_body || '.';

        if (r.payload->>'new_acceptance') = 'declined' then
          v_body := v_body || ' Team changes may be needed.';
        end if;

        if v_home_away <> '' or v_venue_name <> '' then
          v_body := v_body
            || ' '
            || case
                 when v_home_away <> '' and v_venue_name <> '' then
                   v_home_away || ' at ' || v_venue_name
                 when v_home_away <> '' then
                   v_home_away
                 else
                   'Venue: ' || v_venue_name
               end
            || '.';
        end if;
      elsif r.event_type = 'guest_membership_request' then
        v_source := 'New Registration';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'member_name', 'A new member')
          || ' has requested guest membership for '
          || coalesce(r.payload->>'club_name', 'the club')
          || '.';

        if coalesce(nullif(r.payload->>'member_email', ''), '') <> '' then
          v_body := v_body
            || chr(10) || chr(10)
            || 'Email: '
            || (r.payload->>'member_email');
        end if;

        if coalesce(nullif(r.payload->>'member_phone', ''), '') <> '' then
          v_body := v_body
            || chr(10)
            || 'Telephone: '
            || (r.payload->>'member_phone');
        end if;
      elsif r.event_type = 'guest_membership_approved' then
        v_source := 'Membership Approved';
        v_title := v_source;

        v_body :=
          'Welcome to '
          || coalesce(r.payload->>'club_name', 'the club')
          || '.'
          || chr(10) || chr(10)
          || 'Your membership has now been approved';

        if coalesce(nullif(r.payload->>'approved_by', ''), '') <> '' then
          v_body := v_body
            || ' by '
            || (r.payload->>'approved_by');
        end if;

        v_body := v_body
          || '.'
          || chr(10) || chr(10)
          || 'You can now access the members areas of the app.';
      elsif r.event_type in (
        'team_published_player',
        'fixture_selected',
        'reserve_promoted'
      ) then
        v_source := case r.event_type
          when 'team_published_player' then 'Team Published'
          when 'reserve_promoted' then 'Team Selection Changed'
          else 'Fixture Selection'
        end;
        v_title := v_source;

        v_team_no := null;
        v_selected_position := null;
        v_players_per_rink := null;
        v_home_rink_label := null;

        select
          fr.fixture_rink_no::text,
          fra.position,
          fr.players_per_rink,
          coalesce(fr.home_rink_label, '')
        into
          v_team_no,
          v_selected_position,
          v_players_per_rink,
          v_home_rink_label
        from public.fixture_rinks fr
        join public.fixture_rink_assignments fra
          on fra.fixture_rink_id = fr.id
        where fr.fixture_id = r.fixture_id
          and fra.member_profile_id = r.target_member_profile_id
        order by
          case when fra.position between 1 and 4 then 0 else 1 end,
          fr.fixture_rink_no,
          fra.position
        limit 1;

        v_team_no := coalesce(v_team_no, r.payload->>'team_no', '');
        v_team_no_int := nullif(v_team_no, '')::int;
        v_home_rink_label := coalesce(
          v_home_rink_label,
          r.payload->>'home_rink_label',
          ''
        );
        v_selected_position := coalesce(
          v_selected_position,
          nullif(r.payload->>'position', '')::int
        );
        v_players_per_rink := coalesce(
          v_players_per_rink,
          nullif(r.payload->>'players_per_rink', '')::int
        );
        v_selected_role := coalesce(r.payload->>'role', '');

        v_selected_role_text :=
          case
            when v_selected_position = 201 then
              'Marker'

            when v_selected_position >= 100 then
              'Opponent ' || (v_selected_position - 100)::text

            when v_selected_position = 1 then
              'Lead'

            when v_selected_position = 2
                 and v_players_per_rink = 2 then
              'Skip'

            when v_selected_position = 2 then
              'Second'

            when v_selected_position = 3 then
              'Third'

            when v_selected_position = 4 then
              'Skip'

            when v_selected_position is not null then
              'Position ' || v_selected_position::text

            else
              'Selected'
          end;

        select f.start_at
        into v_start_at
        from public.fixtures f
        where f.id = r.fixture_id;

        v_start_at := coalesce(
          v_start_at,
          nullif(r.payload->>'start_at', '')::timestamptz,
          nullif(r.payload->>'fixture_date', '')::timestamptz
        );

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else ''
          end;

        select
          case
            when coalesce(ct.is_internal, false) = true then
              coalesce(
                nullif(ct.name, ''),
                nullif(f.team_name, ''),
                'Internal Fixture'
              )

            when f.is_home = true then
              'Home against '
              || coalesce(opp.name, 'Opponent not set')

            else
              'Away at '
              || coalesce(venue.name, 'Venue not set')
          end
        into v_fixture_context_text
        from public.fixtures f
        left join public.competition_types ct
          on ct.id = f.competition_type_id
        left join public.venues venue
          on venue.id = f.venue_id
        left join public.venues opp
          on opp.id = f.opponent_venue_id
        where f.id = r.fixture_id;

        select string_agg(
          line_text,
          chr(10)
          order by sort_order
        )
        into v_team_lines
        from (
          select
            fra.position as sort_order,

            case
              when fra.position = 1 then
                'Lead: '

              when fra.position = 2
                   and fr.players_per_rink = 2 then
                'Skip: '

              when fra.position = 2 then
                'Second: '

              when fra.position = 3 then
                'Third: '

              when fra.position = 4 then
                'Skip: '

              else
                'Position ' || fra.position::text || ': '
            end

            ||

            coalesce(
              nullif(mp.display_name, ''),
              nullif(
                trim(
                  coalesce(mp.first_name, '')
                  || ' '
                  || coalesce(mp.last_name, '')
                ),
                ''
              ),
              'Unknown'
            ) as line_text

          from public.fixture_rinks fr
          join public.fixture_rink_assignments fra
            on fra.fixture_rink_id = fr.id
          left join public.member_profiles mp
            on mp.id = fra.member_profile_id

          where fr.fixture_id = r.fixture_id
            and fr.fixture_rink_no = v_team_no_int
            and fra.position between 1 and 4
        ) x;

        select string_agg(
          line_text,
          chr(10)
          order by sort_order
        )
        into v_opponent_lines
        from (
          select
            fra.position as sort_order,

            'Opponent '
            || (fra.position - 100)::text
            || ': '

            ||

            coalesce(
              nullif(fra.display_name, ''),
              nullif(mp.display_name, ''),
              nullif(
                trim(
                  coalesce(mp.first_name, '')
                  || ' '
                  || coalesce(mp.last_name, '')
                ),
                ''
              ),
              'Unknown'
            ) as line_text

          from public.fixture_rinks fr
          join public.fixture_rink_assignments fra
            on fra.fixture_rink_id = fr.id
          left join public.member_profiles mp
            on mp.id = fra.member_profile_id

          where fr.fixture_id = r.fixture_id
            and fr.fixture_rink_no = v_team_no_int
            and fra.position between 101 and 199
        ) x;

        select string_agg(
          line_text,
          chr(10)
          order by sort_order
        )
        into v_marker_lines
        from (
          select
            fra.position as sort_order,

            'Marker: '

            ||

            coalesce(
              nullif(mp.display_name, ''),
              nullif(
                trim(
                  coalesce(mp.first_name, '')
                  || ' '
                  || coalesce(mp.last_name, '')
                ),
                ''
              ),
              'Unknown'
            ) as line_text

          from public.fixture_rinks fr
          join public.fixture_rink_assignments fra
            on fra.fixture_rink_id = fr.id
          left join public.member_profiles mp
            on mp.id = fra.member_profile_id

          where fr.fixture_id = r.fixture_id
            and fr.fixture_rink_no = v_team_no_int
            and fra.position = 201
        ) x;

        v_body :=
          case
            when r.event_type = 'reserve_promoted' then
              'You have been promoted from reserve to '
            else
              'You have been selected as '
          end
          || coalesce(v_selected_role_text, 'Selected')
          || ' for '
          || coalesce(
               nullif(r.payload->>'fixture_label', ''),
               nullif(r.payload->>'fixture_name', ''),
               coalesce(v_fixture_context_text, 'this fixture')
             )

          || case
               when v_fixture_date_text <> ''
                 then chr(10)
                      || v_fixture_date_text
               else ''
             end

          || chr(10)

          || coalesce(v_fixture_context_text, '')

          || chr(10)
          || chr(10)

          || coalesce(
               v_team_lines,
               'Team details unavailable'
             );

        if coalesce(v_opponent_lines, '') <> '' then
          v_body :=
            v_body
            || chr(10)
            || v_opponent_lines;
        end if;

        if coalesce(v_marker_lines, '') <> '' then
          v_body :=
            v_body
            || chr(10)
            || v_marker_lines;
        end if;

        if v_home_rink_label <> '' then
          v_body :=
            v_body
            || chr(10)
            || chr(10)
            || 'Home Rink: '
            || v_home_rink_label;
        end if;
      elsif r.event_type = 'marker_request_opened' then
        v_source := 'Marker Required';
        v_title := v_source;

        v_fixture_label := coalesce(
          nullif(r.payload->>'fixture_label', ''),
          'Pre-Select Fixture'
        );

        v_team_no := coalesce(r.payload->>'team_no', '');
        v_home_rink_label := coalesce(
          nullif(r.payload->>'home_rink_label', ''),
          ''
        );
        v_home_away := coalesce(r.payload->>'home_away', '');
        v_venue_name := coalesce(r.payload->>'venue_name', '');

        begin
          v_start_at := coalesce(
            nullif(r.payload->>'start_at', '')::timestamptz,
            nullif(r.payload->>'fixture_date', '')::timestamptz
          );
        exception
          when others then
            v_start_at := null;
        end;

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else ''
          end;

        select
          coalesce(
            nullif(btrim(mp.display_name), ''),
            nullif(
              btrim(
                coalesce(mp.first_name, '')
                || ' '
                || coalesce(mp.last_name, '')
              ),
              ''
            ),
            'Fixture captain'
          ),
          coalesce(nullif(btrim(mp.email_address), ''), 'Not recorded'),
          coalesce(nullif(btrim(mp.phone), ''), 'Not recorded')
        into
          v_captain_name,
          v_captain_email,
          v_captain_phone
        from public.fixtures f
        left join public.member_profiles mp
          on mp.id = f.captain_member_profile_id
        where f.id = r.fixture_id;

        v_body :=
          'A volunteer marker is required for '
          || v_fixture_label
          || '.';

        if v_fixture_date_text <> '' then
          v_body :=
            v_body
            || chr(10) || chr(10)
            || 'When: '
            || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Home/Away: '
            || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Venue: '
            || v_venue_name;
        end if;

        if coalesce(nullif(r.payload->>'opponent_name', ''), '') <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Opponent: '
            || (r.payload->>'opponent_name');
        end if;

        if v_team_no <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Team: '
            || v_team_no;
        end if;

        if v_home_rink_label <> '' then
          v_body :=
            v_body
            || chr(10)
            || 'Rink: '
            || v_home_rink_label;
        end if;

        v_body :=
          v_body
          || chr(10) || chr(10)
          || 'Please contact the fixture captain if you can help.'
          || chr(10)
          || 'Captain: '
          || coalesce(v_captain_name, 'Fixture captain')
          || chr(10)
          || 'Email: '
          || coalesce(v_captain_email, 'Not recorded')
          || chr(10)
          || 'Telephone: '
          || coalesce(v_captain_phone, 'Not recorded');

      elsif r.event_type = 'fixture_moved' then
        v_source := 'Fixture Moved';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_name', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been moved.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             );

        if coalesce(r.payload->>'is_home', '') = 'true' then
          v_body := v_body
            || chr(10)
            || chr(10)
            || 'Home against '
            || coalesce(r.payload->>'opponent_name', 'Opponent not set');
        else
          v_body := v_body
            || chr(10)
            || chr(10)
            || 'Away at '
            || coalesce(r.payload->>'venue_name', 'Venue not set');
        end if;

      elsif r.event_type = 'fixture_rescheduled_selected' then
        v_source := 'Fixture Rescheduled';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_label', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been rescheduled.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || chr(10)
          || case
               when r.payload->>'recipient_role' = 'marker' then
                 'Your previous marker assignment has been carried forward.'
                 || chr(10)
                 || 'Please check the new fixture and Accept or Decline your marker assignment.'
               else
                 'Your previous team selection has been carried forward.'
                 || chr(10)
                 || 'Please check the new fixture and Accept or Decline your selection.'
             end;

      elsif r.event_type = 'fixture_rescheduled_manager' then
        v_source := 'Fixture Rescheduled';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_label', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been rescheduled.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || chr(10)
          || 'The existing team has been carried forward.'
          || chr(10)
          || 'Player acceptance responses have been reset for the new date.';

      elsif r.event_type = 'fixture_rescheduled_availability' then
        v_source := 'Fixture Rescheduled';
        v_title := v_source;

        v_body :=
          coalesce(r.payload->>'fixture_label', 'Fixture')
          || chr(10)
          || chr(10)
          || 'This fixture has been rescheduled.'
          || chr(10)
          || chr(10)
          || 'Old: '
          || to_char(
               (r.payload->>'old_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || 'New: '
          || to_char(
               (r.payload->>'new_start_at')::timestamptz
                 at time zone 'Europe/London',
               'FMDay DD Mon YYYY "at" HH24:MI'
             )
          || chr(10)
          || chr(10)
          || 'Please indicate your availability for the new date.';

      elsif r.event_type = 'acceptance_reminder' then
        
        v_source := 'Selection Reminder';
        v_title := v_source;

        v_body :=
            'Please confirm whether you accept your team selection for '
            || v_fixture_label
            || '.';

        if v_fixture_date_text <> '' then
            v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
            v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;
        if v_venue_name <> '' then
            v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

      elsif r.event_type = 'team_published_reserve' then
        v_source := 'Selected as Reserve';
        v_title := v_source;

        v_body :=
          'You have been selected as a reserve for '
          || v_fixture_label
          || '.';

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

      elsif r.event_type in ('team_published_captain', 'team_published_vice') then
        v_source := 'Team Published';
        v_title := v_source;

        v_body :=
          'The team has been published for '
          || v_fixture_label
          || '.';

        if coalesce((r.payload->>'missing_players')::int, 0) > 0 then
          v_body := v_body
            || chr(10)
            || chr(10)
            || 'The team is currently short of '
            || (r.payload->>'missing_players')
            || ' player(s).';
        end if;

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

      elsif r.event_type = 'team_published_not_selected' then
        v_source := 'Team Selected';
        v_title := v_source;

        v_body :=
          'Thank you for making yourself available for '
          || v_fixture_label
          || '.'
          || chr(10)
          || chr(10)
          || 'The team has now been selected and you have not been selected on this occasion.';

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

      elsif r.event_type = 'team_published_incomplete_request' then
        v_source := 'Players Still Required';
        v_title := v_source;

        v_body :=
          'The team has been published for '
          || v_fixture_label
          || ', but we are still looking for '
          || coalesce(nullif(r.payload->>'missing_players', ''), 'more')
          || ' player(s).'
          || chr(10)
          || chr(10)
          || 'If you are available, please contact the captain.';

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

      elsif r.event_type = 'fixture_opponent_changed' then
        v_source := 'Fixture Update';
        v_title := 'Fixture opponent changed';

        v_start_at :=
          nullif(r.payload->>'start_at', '')::timestamptz;

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else
              ''
          end;

        v_body :=
          case
            when coalesce(r.payload->>'team_name', '') <> '' then
              'Home '
              || (r.payload->>'team_name')
              || ' v '
              || coalesce(
                  nullif(r.payload->>'new_opponent_name', ''),
                  'Opponent to be confirmed'
                )

            else
              'Home against '
              || coalesce(
                  nullif(r.payload->>'new_opponent_name', ''),
                  'opponent to be confirmed'
                )
          end;

        if v_fixture_date_text <> '' then
          v_body :=
            v_body
            || chr(10)
            || v_fixture_date_text;
        end if;

        v_body :=
          v_body
          || chr(10)
          || chr(10)
          || 'The opponent has changed from '
          || coalesce(
               nullif(r.payload->>'old_opponent_name', ''),
               'To be confirmed'
             )
          || ' to '
          || coalesce(
               nullif(r.payload->>'new_opponent_name', ''),
               'To be confirmed'
             )
          || '.';

      elsif r.event_type = 'fixture_cancelled' then
        v_source := 'Fixture Cancelled';
        v_title := v_source;

        v_start_at := nullif(r.payload->>'start_at', '')::timestamptz;

        v_fixture_date_text :=
          case
            when v_start_at is not null then
              to_char(
                v_start_at at time zone 'Europe/London',
                'FMDay DD Mon YYYY "at" HH24:MI'
              )
            else ''
          end;

        v_body := coalesce(nullif(r.payload->>'fixture_label', ''), 'Fixture');

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || v_fixture_date_text;
        end if;

        if coalesce(r.payload->>'home_away', '') = 'Home' then
          v_body := v_body || chr(10) || 'Home against ' || coalesce(nullif(r.payload->>'opponent_name', ''), 'opponent to be confirmed');
        elsif coalesce(r.payload->>'home_away', '') = 'Away' then
          v_body := v_body || chr(10) || 'Away at ' || coalesce(nullif(r.payload->>'venue_name', ''), 'venue not set');
        end if;

        v_body := v_body || chr(10) || chr(10) || 'This fixture has been cancelled.';

        if coalesce(nullif(r.payload->>'reason', ''), '') <> '' then
          v_body := v_body || chr(10) || chr(10) || 'Reason: ' || (r.payload->>'reason');
        end if;

      elsif r.event_type = 'fixture_message' then
        v_source := coalesce(
          nullif(r.payload->>'title', ''),
          'Fixture Message'
        );

        v_title := v_source || ' : ' || v_created_text;

        v_body := coalesce(nullif(r.payload->>'message', ''), 'You have a new fixture message.');

        if v_fixture_label <> '' then
          v_body := v_body || chr(10) || chr(10) || 'Fixture: ' || v_fixture_label;
        end if;

        if v_fixture_date_text <> '' then
          v_body := v_body || chr(10) || 'When: ' || v_fixture_date_text;
        end if;

        if v_home_away <> '' then
          v_body := v_body || chr(10) || 'Home/Away: ' || v_home_away;
        end if;

        if v_venue_name <> '' then
          v_body := v_body || chr(10) || 'Venue: ' || v_venue_name;
        end if;

        if coalesce(nullif(r.payload->>'opponent_name', ''), '') <> '' then
          v_body := v_body || chr(10) || 'Opponent: ' || (r.payload->>'opponent_name');
        end if;

        if coalesce(nullif(r.payload->>'captain_name', ''), '') <> '' then
          v_body := v_body || chr(10) || 'Captain: ' || (r.payload->>'captain_name');
        end if;

        if coalesce(nullif(r.payload->>'vice_captain_name', ''), '') <> '' then
          v_body := v_body || chr(10) || 'Vice-Captain: ' || (r.payload->>'vice_captain_name');
        end if;

        if coalesce(nullif(r.payload->>'sender_name', ''), '') <> '' then
          v_body := v_body || chr(10) || chr(10) || 'From: ' || (r.payload->>'sender_name');
        end if;
      else
        v_title := 'Update';
        v_body := 'You have a new notification';
      end if;

      insert into app_notifications (
        member_profile_id,
        type,
        title,
        body,
        data,
        fixture_id,
        team_selection_id
      )
      values (
        r.target_member_profile_id,
        r.event_type,
        v_title,
        v_body,
        jsonb_strip_nulls(
          jsonb_build_object(
            'source_member_profile_id', r.member_profile_id,
            'marker_request_id', nullif(r.payload->>'marker_request_id', ''),
            'fixture_rink_id', nullif(r.payload->>'fixture_rink_id', ''),
            'team_no', nullif(r.payload->>'team_no', '')
          )
        ),
        r.fixture_id,
        r.team_selection_id
      );

      -- Optional email queue for important notifications
      if r.event_type in (
        'team_acceptance_changed',
        'reserve_promoted',
        'guest_membership_request',
        'guest_membership_approved',
        'fixture_selected',
        'fixture_moved',
        'fixture_rescheduled_selected',
        'fixture_rescheduled_manager',
        'fixture_rescheduled_availability',        
        'fixture_opponent_changed',
        'fixture_cancelled',
        'marker_request_opened',
        'team_published_player',
        'team_published_reserve',
        'team_published_captain',
        'team_published_vice',
        'team_published_not_selected',
        'team_published_incomplete_request',        
        'acceptance_reminder',
        'fixture_message'
      ) then
        insert into public.email_queue (
          member_profile_id,
          event_type,
          recipient_email,
          subject,
          body,
          payload,
          fixture_id,
          team_selection_id,
          attachments
        )

        select
          r.target_member_profile_id,
          r.event_type,
          mp.email_address,
          v_title,
          v_body,
          jsonb_build_object(
            'fixture_id', r.fixture_id,
            'team_selection_id', r.team_selection_id,
            'team_sheet_required', coalesce(r.payload->'team_sheet_required', 'false'::jsonb)
          ),
          r.fixture_id,
          r.team_selection_id,
          coalesce(r.payload->'attachments', '[]'::jsonb)
        from public.member_profiles mp
        where mp.id = r.target_member_profile_id
          and mp.email_address is not null
          and btrim(mp.email_address) <> '';
      end if;

      update notification_queue
      set status = 'sent',
          processed_at = now(),
          last_error = null
      where id = r.id;

      v_count := v_count + 1;

    exception when others then
      update notification_queue
      set status = 'failed',
          attempts = attempts + 1,
          last_error = sqlerrm
      where id = r.id;
    end;
  end loop;

  return v_count;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."process_notification_queue"(p_limit integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."process_notification_queue"(p_limit integer) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."process_notification_queue"(p_limit integer) TO "service_role";

CREATE OR REPLACE FUNCTION public.process_selected_notification_queue_rows(p_queue_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_requested_count integer;
  v_pending_count integer;
begin
  select count(distinct queue_id)
  into v_requested_count
  from unnest(coalesce(p_queue_ids, array[]::uuid[])) queue_id;

  if v_requested_count = 0 then
    raise exception 'At least one notification queue ID is required.';
  end if;

  select count(*)
  into v_pending_count
  from public.notification_queue nq
  where nq.id = any(p_queue_ids)
    and nq.status = 'pending';

  if v_pending_count <> v_requested_count then
    raise exception 'Every requested notification queue row must exist and be pending.';
  end if;

  perform set_config(
    'app.notification_queue_ids',
    array_to_string(
      array(
        select distinct queue_id::text
        from unnest(p_queue_ids) queue_id
        order by queue_id::text
      ),
      ','
    ),
    true
  );

  return public.process_notification_queue(v_requested_count);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."process_selected_notification_queue_rows"(p_queue_ids uuid[]) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."process_selected_notification_queue_rows"(p_queue_ids uuid[]) TO "service_role";

CREATE OR REPLACE FUNCTION public.publish_team_selection_safe(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_required integer;
  v_assigned integer;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if not public.can_manage_team_selection(p_fixture_id) then
    raise exception 'You do not have permission to publish this team.';
  end if;

  select coalesce(sum(players_per_rink), 0)
  into v_required
  from public.fixture_rinks
  where fixture_id = p_fixture_id;

  select count(*)
  into v_assigned
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id
    and fra.position between 1 and fr.players_per_rink;

  if v_required > 0 and v_assigned < v_required and p_allow_incomplete = false then
    raise exception 'INCOMPLETE_TEAM:%:%', v_required, v_assigned;
  end if;

  update public.team_selections
  set
    status = 'published'::selection_status,
    published_by_member_profile_id = v_current_member
  where id = p_team_selection_id
    and fixture_id = p_fixture_id;

  if not found then
    raise exception 'Team selection not found for this fixture.';
  end if;

  perform public.queue_team_publication_communications(
    p_fixture_id,
    p_team_selection_id,
    p_allow_incomplete
  ); 
end;
$function$;

REVOKE ALL ON FUNCTION "public"."publish_team_selection_safe"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."publish_team_selection_safe"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."publish_team_selection_safe"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."publish_team_selection_safe"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."publish_team_selection_safe"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.queue_fixture_moved_notifications(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int := 0;
begin
  if not public.can_manage_fixture(p_fixture_id) then
    raise exception 'You do not have permission to queue fixture-move notifications.';
  end if;

  -- Serialize retries for this fixture without locking other clubs' fixtures.
  perform 1 from public.fixtures where id = p_fixture_id for update;

  with recipients as (
    -- Includes assigned markers (position 201), as well as playing positions.
    select fra.member_profile_id
    from public.fixture_rink_assignments fra
    where fra.fixture_id = p_fixture_id

    union

    select tsm.member_profile_id
    from public.team_selections ts
    join public.team_selection_members tsm on tsm.team_selection_id = ts.id
    where ts.fixture_id = p_fixture_id
      and ts.status = 'published'
      and tsm.is_selected = true

    union

    select f.captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f where f.id = p_fixture_id
  )
  insert into public.notification_queue (
    target_member_profile_id,
    event_type,
    fixture_id,
    payload,
    status,
    created_at
  )
  select distinct
    recipient.member_profile_id,
    'fixture_moved',
    f.id,
    jsonb_build_object(
      'fixture_id', f.id,
      'fixture_name', coalesce(ct.name, 'Fixture'),
      'old_start_at', p_old_start_at,
      'old_end_at', p_old_end_at,
      'new_start_at', f.start_at,
      'new_end_at', f.end_at,
      'is_home', f.is_home,
      'venue_name', venue.name,
      'opponent_name', opponent.name
    ),
    'pending',
    now()
  from public.fixtures f
  cross join recipients recipient
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues venue
    on venue.id = f.venue_id
  left join public.venues opponent
    on opponent.id = f.opponent_venue_id
  where f.id = p_fixture_id
    and recipient.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = f.id
        and existing.event_type = 'fixture_moved'
        and existing.target_member_profile_id = recipient.member_profile_id
        and (existing.payload ->> 'old_start_at')::timestamptz is not distinct from p_old_start_at
        and nullif(existing.payload ->> 'old_end_at', '')::timestamptz is not distinct from p_old_end_at
        and (existing.payload ->> 'new_start_at')::timestamptz is not distinct from f.start_at
        and nullif(existing.payload ->> 'new_end_at', '')::timestamptz is not distinct from f.end_at
        and existing.status in ('pending', 'processing', 'sent')
    );

  get diagnostics v_count = row_count;

  return v_count;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_fixture_moved_notifications"(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."queue_fixture_moved_notifications"(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."queue_fixture_moved_notifications"(p_fixture_id uuid, p_old_start_at timestamp with time zone, p_old_end_at timestamp with time zone) TO "service_role";

CREATE OR REPLACE FUNCTION public.queue_fixture_opponent_changed_notifications(p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_changed_by_member_profile_id uuid;
  v_team_selection_id uuid;

  v_old_opponent_name text;
  v_new_opponent_name text;

  v_start_at timestamptz;
  v_fixture_name text;
  v_team_name text;
  v_selection_mode text;
  v_is_published boolean := false;

  v_queued_count integer := 0;
begin
  /*
   * Who made the change?
   */
  select public.my_member_profile_id()
  into v_changed_by_member_profile_id;

  /*
   * Current fixture details.
   */
  select
    f.start_at,
    coalesce(nullif(ct.name, ''), 'Fixture'),
    nullif(
      trim(
        coalesce(t.name, f.team_name, '')
      ),
      ''
    ),
    lower(coalesce(ct.selection_mode, ''))
  into
    v_start_at,
    v_fixture_name,
    v_team_name,
    v_selection_mode
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.teams t
    on t.id = f.team_id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture % was not found', p_fixture_id;
  end if;

  if not public.can_manage_fixture(p_fixture_id) then
    raise exception 'You do not have permission to queue opponent-change notifications.';
  end if;

  -- Local venue links must belong to the fixture's club, even when masters are shared.
  if exists (
    select 1
    from unnest(array[p_old_opponent_venue_id, p_new_opponent_venue_id]) as supplied(venue_id)
    where supplied.venue_id is not null
      and not exists (
        select 1 from public.venues v
        join public.fixtures f on f.club_id = v.club_id
        where f.id = p_fixture_id and v.id = supplied.venue_id
      )
  ) then
    raise exception 'Opponent venues must belong to this fixture club.' using errcode = '22023';
  end if;

  /*
   * Venue names before and after the change.
   */
  select name
  into v_old_opponent_name
  from public.venues
  where id = p_old_opponent_venue_id;

  select name
  into v_new_opponent_name
  from public.venues
  where id = p_new_opponent_venue_id;

  v_old_opponent_name :=
    coalesce(nullif(v_old_opponent_name, ''), 'To be confirmed');

  v_new_opponent_name :=
    coalesce(nullif(v_new_opponent_name, ''), 'To be confirmed');

  /*
   * Current team selection, if one exists.
   */
  select
  id,
  status = 'published'
  into
  v_team_selection_id,
  v_is_published
  from public.team_selections
  where fixture_id = p_fixture_id
  order by created_at desc nulls last
  limit 1;

  /*
 * Before publication, opponent changes are still part of fixture preparation.
 * Do not notify selected members until the fixture has been published.
 */
  if coalesce(v_is_published, false) = false then
  return 0;
  end if;

  /*
   * Build one deduplicated recipient set.
   *
   * Recipients:
   *   - fixture captain
   *   - fixture vice-captain
   *   - selected team-selection members
   *   - RSVP Yes / Maybe members
   *
   * The person making the change is excluded.
   */
  with recipients as (

    select f.captain_member_profile_id as member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.captain_member_profile_id is not null

    union

    select f.vice_captain_member_profile_id
    from public.fixtures f
    where f.id = p_fixture_id
      and f.vice_captain_member_profile_id is not null

    union

    select tsm.member_profile_id
    from public.team_selection_members tsm
    join public.team_selections ts
      on ts.id = tsm.team_selection_id
    where ts.fixture_id = p_fixture_id
      and tsm.member_profile_id is not null
      and coalesce(tsm.is_selected, false) = true

    union

    select frsvp.member_profile_id
    from public.fixture_rsvps frsvp
    where frsvp.fixture_id = p_fixture_id
      and frsvp.member_profile_id is not null
      and lower(coalesce(frsvp.status::text, '')) in ('yes', 'maybe')
  ),
  inserted as (
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'fixture_opponent_changed',
      v_changed_by_member_profile_id,
      r.member_profile_id,
      p_fixture_id,
      v_team_selection_id,
      jsonb_build_object(
        'old_opponent_venue_id', p_old_opponent_venue_id,
        'new_opponent_venue_id', p_new_opponent_venue_id,
        'old_opponent_name', v_old_opponent_name,
        'new_opponent_name', v_new_opponent_name,
        'start_at', v_start_at,
        'fixture_name', v_fixture_name,
        'team_name', v_team_name,
        'selection_mode', v_selection_mode
      ),
      'pending'
    from recipients r
    where r.member_profile_id is not null
      and (
        v_changed_by_member_profile_id is null
        or r.member_profile_id <> v_changed_by_member_profile_id
      )
    returning 1
  )
  select count(*)
  into v_queued_count
  from inserted;

  return v_queued_count;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_fixture_opponent_changed_notifications"(p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."queue_fixture_opponent_changed_notifications"(p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."queue_fixture_opponent_changed_notifications"(p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."queue_fixture_opponent_changed_notifications"(p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."queue_fixture_opponent_changed_notifications"(p_fixture_id uuid, p_old_opponent_venue_id uuid, p_new_opponent_venue_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.queue_fixture_selected_notifications(p_fixture_id uuid, p_attachments jsonb DEFAULT NULL::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
    v_count integer := 0;
begin

    insert into notification_queue (
        target_member_profile_id,
        event_type,
        fixture_id,
        payload,
        status,
        created_at
    )
    select
        fra.member_profile_id,
        'fixture_selected',
        f.id,
        jsonb_build_object(
            'fixture_id', f.id,
            'fixture_name',
                coalesce(ct.name, 'Fixture'),
            'start_at',
                f.start_at,
            'team_no',
                fr.fixture_rink_no,
            'position',
                fra.position,
            'players_per_rink',
                fr.players_per_rink,
            'home_rink_label',
                fr.home_rink_label,
            'role',
                case
                    when fra.position = 201 then 'marker'
                    when fra.position >= 100 then 'opponent'
                    else 'player'
                end,
            'captain_member_profile_id',
                f.captain_member_profile_id,
            'venue_id',
                f.venue_id,
            'opponent_venue_id',
                f.opponent_venue_id,
            'attachments', coalesce(p_attachments, '[]'::jsonb)
        ),
        'pending',
        now()
    from fixture_rink_assignments fra
    join fixture_rinks fr
      on fr.id = fra.fixture_rink_id
    join fixtures f
      on f.id = fra.fixture_id
    left join competition_types ct
      on ct.id = f.competition_type_id
    where f.id = p_fixture_id;

    get diagnostics v_count = row_count;

    return v_count;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_fixture_selected_notifications"(p_fixture_id uuid, p_attachments jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."queue_fixture_selected_notifications"(p_fixture_id uuid, p_attachments jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.queue_mailing_list_message(p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean DEFAULT true, p_send_email boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_list_name text;
  v_sender_name text;
  v_message_id uuid;
  v_recipient_count integer := 0;
  v_app_queued_count integer := 0;
  v_email_queued_count integer := 0;
  v_delivery_body text;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  if btrim(coalesce(p_subject, '')) = '' then
    raise exception 'A subject is required.';
  end if;

  if btrim(coalesce(p_message, '')) = '' then
    raise exception 'A message is required.';
  end if;

  if not coalesce(p_send_app, false)
     and not coalesce(p_send_email, false) then
    raise exception 'Select at least one delivery method.';
  end if;

  select ml.club_id, ml.name
  into v_club_id, v_list_name
  from public.mailing_lists ml
  where ml.id = p_mailing_list_id
    and ml.is_active = true;

  if not found then
    raise exception 'The mailing list was not found or is inactive.';
  end if;

  if not (
    public.is_app_superuser()
    or public.is_club_admin(v_club_id)
  ) then
    raise exception 'You do not have permission to send to this mailing list.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select coalesce(
    nullif(btrim(mp.display_name), ''),
    nullif(
      btrim(coalesce(mp.first_name, '') || ' ' || coalesce(mp.last_name, '')),
      ''
    ),
    'Club administrator'
  )
  into v_sender_name
  from public.member_profiles mp
  where mp.id = v_actor_member_profile_id;

  v_sender_name := coalesce(v_sender_name, 'Club administrator');

  insert into public.mailing_list_messages (
    club_id,
    mailing_list_id,
    subject,
    message_body,
    sender_member_profile_id,
    send_app,
    send_email
  )
  values (
    v_club_id,
    p_mailing_list_id,
    btrim(p_subject),
    btrim(p_message),
    v_actor_member_profile_id,
    p_send_app,
    p_send_email
  )
  returning id into v_message_id;

  insert into public.mailing_list_message_recipients (
    mailing_list_message_id,
    member_profile_id,
    email_address,
    app_requested,
    email_requested
  )
  select
    v_message_id,
    mlm.member_profile_id,
    nullif(btrim(mp.email_address), ''),
    p_send_app,
    p_send_email
  from public.mailing_list_members mlm
  join public.member_profiles mp
    on mp.id = mlm.member_profile_id
  join public.club_memberships cm
    on cm.club_id = v_club_id
   and cm.member_profile_id = mlm.member_profile_id
   and cm.is_active = true
  where mlm.mailing_list_id = p_mailing_list_id
    and mlm.is_active = true;

  get diagnostics v_recipient_count = row_count;

  v_delivery_body :=
    btrim(p_message)
    || chr(10) || chr(10)
    || 'List: ' || v_list_name
    || chr(10)
    || 'From: ' || v_sender_name;

  if p_send_app then
    insert into public.app_notifications (
      member_profile_id,
      type,
      title,
      body,
      data,
      fixture_id,
      team_selection_id
    )
    select
      mlmr.member_profile_id,
      'mailing_list_message',
      btrim(p_subject),
      v_delivery_body,
      jsonb_build_object(
        'mailing_list_id', p_mailing_list_id,
        'mailing_list_message_id', v_message_id,
        'sender_member_profile_id', v_actor_member_profile_id
      ),
      null,
      null
    from public.mailing_list_message_recipients mlmr
    where mlmr.mailing_list_message_id = v_message_id
      and mlmr.app_requested = true;

    get diagnostics v_app_queued_count = row_count;
  end if;

  if p_send_email then
    insert into public.email_queue (
      member_profile_id,
      event_type,
      recipient_email,
      subject,
      body,
      payload,
      fixture_id,
      team_selection_id,
      attachments
    )
    select
      mlmr.member_profile_id,
      'mailing_list_message',
      mlmr.email_address,
      btrim(p_subject),
      v_delivery_body,
      jsonb_build_object(
        'mailing_list_id', p_mailing_list_id,
        'mailing_list_message_id', v_message_id,
        'sender_member_profile_id', v_actor_member_profile_id
      ),
      null,
      null,
      '[]'::jsonb
    from public.mailing_list_message_recipients mlmr
    where mlmr.mailing_list_message_id = v_message_id
      and mlmr.email_requested = true
      and mlmr.email_address is not null
      and btrim(mlmr.email_address) <> '';

    get diagnostics v_email_queued_count = row_count;
  end if;

  update public.mailing_list_messages
  set
    recipient_count = v_recipient_count,
    app_queued_count = v_app_queued_count,
    email_queued_count = v_email_queued_count
  where id = v_message_id;

  return jsonb_build_object(
    'mailing_list_message_id', v_message_id,
    'mailing_list_id', p_mailing_list_id,
    'mailing_list_name', v_list_name,
    'recipient_count', v_recipient_count,
    'app_messages_created', v_app_queued_count,
    'emails_queued', v_email_queued_count,
    'members_without_email',
      greatest(v_recipient_count - v_email_queued_count, 0)
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_mailing_list_message"(p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean, p_send_email boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."queue_mailing_list_message"(p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean, p_send_email boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."queue_mailing_list_message"(p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean, p_send_email boolean) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."queue_mailing_list_message"(p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean, p_send_email boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."queue_mailing_list_message"(p_mailing_list_id uuid, p_subject text, p_message text, p_send_app boolean, p_send_email boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.queue_open_marker_request_communications(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_team_selection_id uuid;
  v_marker_mailing_list_id uuid;
  v_marker_mailing_list_name text;

  v_is_superuser boolean := false;
  v_has_permission boolean := false;

  v_queued_count integer := 0;
  v_open_request_count integer := 0;
  v_volunteer_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select f.club_id, ts.id
  into v_club_id, v_team_selection_id
  from public.fixtures f
  left join public.team_selections ts
    on ts.fixture_id = f.id
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission :=
    v_is_superuser
    or exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = v_actor_member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
        and (
          lower(cm.role::text) in ('admin', 'selector')
          or exists (
            select 1
            from public.fixtures f
            where f.id = p_fixture_id
              and v_actor_member_profile_id in (
                f.captain_member_profile_id,
                f.vice_captain_member_profile_id
              )
          )
        )
    );

  if not v_has_permission then
    raise exception
      'You do not have permission to send marker requests for this fixture.';
  end if;

  select vt.mailing_list_id, ml.name
  into v_marker_mailing_list_id, v_marker_mailing_list_name
  from public.volunteer_tasks vt
  join public.mailing_lists ml
    on ml.id = vt.mailing_list_id
   and ml.club_id = vt.club_id
   and ml.is_active = true
  where vt.club_id = v_club_id
    and vt.task_code = 'marker'
    and vt.is_active = true
  limit 1;

  if v_marker_mailing_list_id is null then
    raise exception
      'No active Marker volunteer task with an active mailing list is configured for this club.';
  end if;

  select count(*)
  into v_open_request_count
  from public.fixture_marker_requests mr
  join public.fixture_rinks fr
    on fr.id = mr.fixture_rink_id
  where fr.fixture_id = p_fixture_id
    and mr.status = 'open';

  select count(distinct mlm.member_profile_id)
  into v_volunteer_count
  from public.mailing_list_members mlm
  join public.club_memberships cm
    on cm.club_id = v_club_id
   and cm.member_profile_id = mlm.member_profile_id
   and cm.is_active = true
   and lower(cm.role::text) <> 'guest'
  where mlm.mailing_list_id = v_marker_mailing_list_id
    and mlm.is_active = true
    and not exists (
      select 1
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id = mlm.member_profile_id
        and tsm.is_selected = true
    )
    and not exists (
      select 1
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id = mlm.member_profile_id
    );

  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'marker_request_opened',
    v_actor_member_profile_id,
    mlm.member_profile_id,
    p_fixture_id,
    v_team_selection_id,

    jsonb_build_object(
      'marker_request_id', mr.id,
      'fixture_rink_id', fr.id,
      'team_no', fr.fixture_rink_no,
      'home_rink_label', fr.home_rink_label,
      'players_per_rink', fr.players_per_rink,
      'mailing_list_id', v_marker_mailing_list_id,
      'mailing_list_name', v_marker_mailing_list_name,

      'fixture_label',
        coalesce(
          nullif(btrim(f.team_name), ''),
          nullif(btrim(ct.name), ''),
          'Pre-Select Fixture'
        ),

      'fixture_date', f.start_at,
      'start_at', f.start_at,
      'end_at', f.end_at,

      'home_away',
        case when f.is_home = true then 'Home' else 'Away' end,

      'venue_name',
        case
          when f.is_home = true
            then coalesce(home_venue.name, '')
          else coalesce(opponent_venue.name, home_venue.name, '')
        end,

      'opponent_name', coalesce(opponent_venue.name, ''),

      'message',
        'A marker is required for Team '
        || fr.fixture_rink_no::text
        || '.'
    ),

    'pending'

  from public.fixture_marker_requests mr
  join public.fixture_rinks fr
    on fr.id = mr.fixture_rink_id
  join public.fixtures f
    on f.id = fr.fixture_id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues home_venue
    on home_venue.id = f.venue_id
  left join public.venues opponent_venue
    on opponent_venue.id = f.opponent_venue_id
  join public.mailing_list_members mlm
    on mlm.mailing_list_id = v_marker_mailing_list_id
   and mlm.is_active = true
  join public.club_memberships cm
    on cm.club_id = f.club_id
   and cm.member_profile_id = mlm.member_profile_id
   and cm.is_active = true
   and lower(cm.role::text) <> 'guest'

  where fr.fixture_id = p_fixture_id
    and mr.status = 'open'
    and not exists (
      select 1
      from public.team_selection_members tsm
      where tsm.team_selection_id = v_team_selection_id
        and tsm.member_profile_id = mlm.member_profile_id
        and tsm.is_selected = true
    )
    and not exists (
      select 1
      from public.fixture_rink_assignments fra
      where fra.fixture_id = p_fixture_id
        and fra.member_profile_id = mlm.member_profile_id
    )
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.event_type = 'marker_request_opened'
        and existing.target_member_profile_id = mlm.member_profile_id
        and existing.payload ->> 'marker_request_id' = mr.id::text
    );

  get diagnostics v_queued_count = row_count;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'mailing_list_id', v_marker_mailing_list_id,
    'mailing_list_name', v_marker_mailing_list_name,
    'open_request_count', v_open_request_count,
    'active_marker_volunteer_count', v_volunteer_count,
    'communications_queued', v_queued_count
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_open_marker_request_communications"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."queue_open_marker_request_communications"(p_fixture_id uuid) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."queue_open_marker_request_communications"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."queue_open_marker_request_communications"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.queue_post_publication_player_change(p_team_selection_member_id uuid, p_event_type text, p_actor_member_profile_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_row record;
begin
  if p_event_type not in ('fixture_selected', 'reserve_promoted') then
    raise exception 'Unsupported player-change event type.';
  end if;

  select
    tsm.member_profile_id,
    ts.id as team_selection_id,
    ts.status::text as selection_status,
    f.id as fixture_id,
    f.start_at,
    f.is_home,
    coalesce(nullif(btrim(f.team_name), ''), 'Fixture') as fixture_label,
    coalesce(v.name, ov.name, '') as venue_name,
    coalesce(nullif(btrim(mp.display_name), ''),
      concat_ws(' ', nullif(btrim(mp.first_name), ''), nullif(btrim(mp.last_name), '')),
      'A player') as player_name,
    fr.fixture_rink_no as team_no,
    fr.home_rink_label,
    fr.players_per_rink,
    fra.position
  into v_row
  from public.team_selection_members tsm
  join public.team_selections ts on ts.id = tsm.team_selection_id
  join public.fixtures f on f.id = ts.fixture_id
  join public.member_profiles mp on mp.id = tsm.member_profile_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  join public.fixture_rink_assignments fra
    on fra.fixture_id = f.id and fra.member_profile_id = tsm.member_profile_id
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
   and fr.fixture_id = f.id
  where tsm.id = p_team_selection_member_id
    and tsm.role = 'player'::public.selection_member_role
    and tsm.is_selected = true
    and fra.position between 1 and fr.players_per_rink;

  if not found
     or v_row.selection_status <> 'published'
     or exists (
       select 1 from public.fixtures f
       where f.id = v_row.fixture_id and f.cancelled_at is not null
     ) then
    return false;
  end if;

  if p_event_type = 'reserve_promoted' then
    update public.notification_queue set status = 'cancelled'
    where fixture_id = v_row.fixture_id
      and target_member_profile_id = v_row.member_profile_id
      and event_type = 'team_published_reserve' and status = 'pending';

    update public.email_queue set status = 'cancelled'
    where fixture_id = v_row.fixture_id
      and member_profile_id = v_row.member_profile_id
      and event_type = 'team_published_reserve'
      and status in ('pending', 'failed') and sent_at is null;
  end if;

  insert into public.notification_queue (
    event_type, member_profile_id, target_member_profile_id,
    fixture_id, team_selection_id, payload, status
  ) values (
    p_event_type,
    p_actor_member_profile_id,
    v_row.member_profile_id,
    v_row.fixture_id,
    v_row.team_selection_id,
    jsonb_strip_nulls(jsonb_build_object(
      'player_name', v_row.player_name,
      'fixture_label', v_row.fixture_label,
      'fixture_date', v_row.start_at,
      'start_at', v_row.start_at,
      'home_away', case when v_row.is_home then 'Home' else 'Away' end,
      'venue_name', v_row.venue_name,
      'team_no', v_row.team_no,
      'home_rink_label', v_row.home_rink_label,
      'players_per_rink', v_row.players_per_rink,
      'position', v_row.position,
      'role', 'player',
      'team_sheet_required', true,
      'old_role', case when p_event_type = 'reserve_promoted' then 'reserve' end,
      'new_role', case when p_event_type = 'reserve_promoted' then 'player' end
    )),
    'pending'
  );

  return true;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_post_publication_player_change"(p_team_selection_member_id uuid, p_event_type text, p_actor_member_profile_id uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.queue_team_acceptance_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team_selection record;
  v_fixture record;
  v_player_name text;
  v_fixture_label text;
  v_home_away text;
  v_venue_name text;
  v_opponent_name text;
  v_selection_mode text;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.acceptance is not distinct from new.acceptance then
    return new;
  end if;

  if new.acceptance is null then
    return new;
  end if;

  select ts.*
  into v_team_selection
  from public.team_selections ts
  where ts.id = new.team_selection_id;

  if v_team_selection is null then
    return new;
  end if;

  if v_team_selection.status is distinct from 'published' then
    return new;
  end if;

  select f.*
  into v_fixture
  from public.fixtures f
  where f.id = v_team_selection.fixture_id;

  if v_fixture is null then
    return new;
  end if;

  select lower(btrim(coalesce(ct.selection_mode, '')))
  into v_selection_mode
  from public.competition_types ct
  where ct.id = v_fixture.competition_type_id;

  if new.role = 'player'::public.selection_member_role
     and coalesce(v_selection_mode, '') <> 'preselect'
     and (v_fixture.team_id is not null or coalesce(v_fixture.requires_rsvp, false))
     and not exists (
       select 1
       from public.fixture_rink_assignments fra
       join public.fixture_rinks fr
         on fr.id = fra.fixture_rink_id
        and fr.fixture_id = v_fixture.id
       where fra.fixture_id = v_fixture.id
         and fra.member_profile_id = new.member_profile_id
         and fra.position between 1 and fr.players_per_rink
     ) then
    return new;
  end if;

  if v_fixture.captain_member_profile_id is null then
    return new;
  end if;

  -- Do not notify the captain about their own acceptance change.
  if v_fixture.captain_member_profile_id = new.member_profile_id then
    return new;
  end if;

  select mp.display_name
  into v_player_name
  from public.member_profiles mp
  where mp.id = new.member_profile_id;

  v_home_away := case when v_fixture.is_home then 'Home' else 'Away' end;

  select coalesce(v.name, '')
  into v_venue_name
  from public.venues v
  where v.id = v_fixture.venue_id;

  select coalesce(ov.name, '')
  into v_opponent_name
  from public.venues ov
  where ov.id = v_fixture.opponent_venue_id;

  v_fixture_label := coalesce(
    nullif(v_fixture.team_name, ''),
    case
      when v_opponent_name <> '' then
        v_home_away || ' v ' || v_opponent_name
      else
        'Fixture'
    end
  );

  /*
    Coalesce repeated acceptance changes before the queue is processed.

    Example:
      pending  -> accepted
      accepted -> declined
      declined -> accepted

    If all of that happens before process_notification_queue runs,
    the captain should receive one Team Update, not three.
  */
  delete from public.notification_queue nq
  where nq.event_type = 'team_acceptance_changed'
    and nq.fixture_id = v_fixture.id
    and nq.team_selection_id = new.team_selection_id
    and nq.member_profile_id = new.member_profile_id
    and nq.target_member_profile_id = v_fixture.captain_member_profile_id
    and nq.status = 'pending';

  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  values (
    'team_acceptance_changed',
    new.member_profile_id,
    v_fixture.captain_member_profile_id,
    v_fixture.id,
    new.team_selection_id,
    jsonb_build_object(
      'changed_member_profile_id', new.member_profile_id,
      'old_acceptance', old.acceptance::text,
      'new_acceptance', new.acceptance::text,
      'player_name', coalesce(v_player_name, 'A player'),
      'fixture_label', v_fixture_label,
      'fixture_date', v_fixture.start_at,
      'home_away', v_home_away,
      'venue_name', coalesce(v_venue_name, ''),
      'opponent_name', coalesce(v_opponent_name, '')
    ),
    'pending'
  );

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_team_acceptance_change"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."queue_team_acceptance_change"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."queue_team_acceptance_change"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."queue_team_acceptance_change"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."queue_team_acceptance_change"() TO "service_role";

CREATE OR REPLACE FUNCTION public.queue_team_publication_communications(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_fixture_label text;
  v_start_at timestamptz;
  v_home_away text;
  v_venue_name text;
  v_team_id uuid;
  v_captain uuid;
  v_vice uuid;
  v_required integer;
  v_assigned integer;
  v_missing integer;
  v_count integer := 0;
begin
  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if not public.can_manage_team_selection(p_fixture_id) then
    raise exception 'You do not have permission to queue team communications.';
  end if;

  -- Direct RPC callers must bind the selection to the authorised fixture.
  if not exists (
    select 1 from public.team_selections ts
    where ts.id = p_team_selection_id and ts.fixture_id = p_fixture_id
  ) then
    raise exception 'Team selection does not belong to this fixture.' using errcode = '22023';
  end if;

  select
    coalesce(nullif(f.team_name, ''), 'Fixture'),
    f.start_at,
    case when f.is_home then 'Home' else 'Away' end,
    coalesce(v.name, ov.name, ''),
    f.team_id,
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_fixture_label,
    v_start_at,
    v_home_away,
    v_venue_name,
    v_team_id,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  where f.id = p_fixture_id;

  select coalesce(sum(players_per_rink), 0)
  into v_required
  from public.fixture_rinks
  where fixture_id = p_fixture_id;

  select count(*)
  into v_assigned
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and fra.position between 1 and fr.players_per_rink;

  v_missing := greatest(v_required - v_assigned, 0);

  -- Assigned players
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'team_published_player',
    v_current_member,
    fra.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  where fra.fixture_id = p_fixture_id

    -- Only real club members can receive a player notification.
    and fra.member_profile_id is not null

    -- Only actual player positions, not opponents/markers/request rows.
    and fra.position between 1 and fr.players_per_rink

    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = fra.member_profile_id
        and nq.event_type = 'team_published_player'
    );

  get diagnostics v_count = row_count;

  -- Reserves
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'team_published_reserve',
    v_current_member,
    tsm.member_profile_id,
    p_fixture_id,
    p_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'home_away', v_home_away,
      'venue_name', v_venue_name,
      'missing_players', v_missing,
      'team_sheet_required', true
    ),
    'pending'
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
    and tsm.is_selected = true
    and tsm.role = 'reserve'::selection_member_role
    and not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = tsm.member_profile_id
        and nq.event_type = 'team_published_reserve'
    );

  -- Captain copy
  if v_captain is not null then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'team_published_captain',
      v_current_member,
      v_captain,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_captain
        and nq.event_type = 'team_published_captain'
    );
  end if;

  -- Vice captain copy
  if v_vice is not null and v_vice is distinct from v_captain then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      'team_published_vice',
      v_current_member,
      v_vice,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', true
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = p_fixture_id
        and nq.team_selection_id = p_team_selection_id
        and nq.target_member_profile_id = v_vice
        and nq.event_type = 'team_published_vice'
    );
  end if;

  -- Available but not selected: notification/email, no team sheet.
  -- Assumes team_members has team_id/member_profile_id/is_active.
  if v_team_id is not null then
    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      case
        when p_allow_incomplete = true and v_missing > 0
          then 'team_published_incomplete_request'
        else 'team_published_not_selected'
      end,
      v_current_member,
      tm.member_profile_id,
      p_fixture_id,
      p_team_selection_id,
      jsonb_build_object(
        'fixture_label', v_fixture_label,
        'fixture_date', v_start_at,
        'home_away', v_home_away,
        'venue_name', v_venue_name,
        'missing_players', v_missing,
        'team_sheet_required', false
      ),
      'pending'
    from public.team_members tm
    where tm.team_id = v_team_id
      and tm.member_profile_id is not null
      and coalesce(tm.is_active, true) = true
      and not exists (
        select 1
        from public.team_selection_members tsm
        where tsm.team_selection_id = p_team_selection_id
          and tsm.member_profile_id = tm.member_profile_id
          and tsm.is_selected = true
      )
      and not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = p_team_selection_id
          and nq.target_member_profile_id = tm.member_profile_id
          and nq.event_type in (
            'team_published_not_selected',
            'team_published_incomplete_request'
          )
      );
  end if;

  return v_count;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."queue_team_publication_communications"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."queue_team_publication_communications"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."queue_team_publication_communications"(p_fixture_id uuid, p_team_selection_id uuid, p_allow_incomplete boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.reconcile_preselect_communications(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor_member_profile_id uuid;
  v_club_id uuid;
  v_team_selection_id uuid;
  v_selection_mode text := '';
  v_is_superuser boolean := false;
  v_has_permission boolean := false;
  v_fixture_selected_queued integer := 0;
  v_leadership_queued integer := 0;
  v_fixture_label text;
  v_start_at timestamptz;
  v_is_home boolean;
  v_venue_name text;
  v_captain uuid;
  v_vice uuid;
  v_marker_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select
    f.club_id,
    ts.id,
    lower(coalesce(ct.selection_mode::text, '')),
    coalesce(nullif(btrim(f.team_name), ''), nullif(btrim(ct.name), ''), 'Pre-Select Fixture'),
    f.start_at,
    f.is_home,
    coalesce(v.name, ov.name, ''),
    f.captain_member_profile_id,
    f.vice_captain_member_profile_id
  into
    v_club_id,
    v_team_selection_id,
    v_selection_mode,
    v_fixture_label,
    v_start_at,
    v_is_home,
    v_venue_name,
    v_captain,
    v_vice
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  left join public.venues v on v.id = f.venue_id
  left join public.venues ov on ov.id = f.opponent_venue_id
  left join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_team_selection_id is null then
    raise exception 'No team selection exists for this fixture.';
  end if;

  if v_selection_mode <> 'preselect' then
    raise exception 'This repair routine is only for Pre-Select fixtures.';
  end if;

  select public.my_member_profile_id()
  into v_actor_member_profile_id;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_superuser;

  v_has_permission := public.can_manage_fixture(p_fixture_id);

  if not v_has_permission then
    raise exception
      'You do not have permission to repair this fixture''s communications.';
  end if;

  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    'fixture_selected',
    v_actor_member_profile_id,
    fra.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label',
        coalesce(
          nullif(btrim(f.team_name), ''),
          nullif(btrim(ct.name), ''),
          'Pre-Select Fixture'
        ),
      'start_at', f.start_at,
      'fixture_date', f.start_at,
      'fixture_rink_id', fr.id,
      'team_no', fr.fixture_rink_no,
      'home_rink_label', fr.home_rink_label,
      'players_per_rink', fr.players_per_rink,
      'position', fra.position,
      'role',
        case
          when fra.position = 201 then 'marker'
          when fra.position between 101 and (100 + fr.players_per_rink)
            then 'opponent'
          else 'player'
        end,
      'team_sheet_required', true
    ),
    'pending'
  from public.fixture_rink_assignments fra
  join public.fixture_rinks fr
    on fr.id = fra.fixture_rink_id
  join public.fixtures f
    on f.id = fr.fixture_id
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where fra.fixture_id = p_fixture_id
    and fra.member_profile_id is not null
    and (
      fra.position between 1 and fr.players_per_rink
      or fra.position between 101 and (100 + fr.players_per_rink)
      or fra.position = 201
    )
    and (
      fra.member_profile_id = any(
        coalesce(
          string_to_array(
            nullif(
              current_setting('app.preselect_reselected_member_ids', true),
              ''
            ),
            ','
          )::uuid[],
          array[]::uuid[]
        )
      )
      or not exists (
        select 1
        from public.notification_queue nq
        where nq.fixture_id = p_fixture_id
          and nq.team_selection_id = v_team_selection_id
          and nq.event_type = 'fixture_selected'
          and nq.target_member_profile_id = fra.member_profile_id
          and (
            nullif(nq.payload ->> 'position', '') is null
            or nq.payload ->> 'position' = fra.position::text
          )
          and (
            nullif(nq.payload ->> 'team_no', '') is null
            or nq.payload ->> 'team_no' = fr.fixture_rink_no::text
          )
      )
    );

  get diagnostics v_fixture_selected_queued = row_count;

  -- Leadership who are not already receiving an assignment-specific message
  -- receive one informational publication copy of the same Team Sheet.
  insert into public.notification_queue (
    event_type,
    member_profile_id,
    target_member_profile_id,
    fixture_id,
    team_selection_id,
    payload,
    status
  )
  select
    leadership.event_type,
    v_actor_member_profile_id,
    leadership.member_profile_id,
    p_fixture_id,
    v_team_selection_id,
    jsonb_build_object(
      'fixture_label', v_fixture_label,
      'fixture_date', v_start_at,
      'start_at', v_start_at,
      'home_away', case when v_is_home then 'Home' else 'Away' end,
      'venue_name', v_venue_name,
      'team_sheet_required', true
    ),
    'pending'
  from (
    values
      ('team_published_captain'::text, v_captain),
      ('team_published_vice'::text, v_vice)
  ) as leadership(event_type, member_profile_id)
  where leadership.member_profile_id is not null
    and not exists (
      select 1
      from public.notification_queue existing
      where existing.fixture_id = p_fixture_id
        and existing.team_selection_id = v_team_selection_id
        and existing.target_member_profile_id = leadership.member_profile_id
        and existing.status in ('pending', 'sent')
        and existing.event_type in (
          'fixture_selected',
          'team_published_captain',
          'team_published_vice'
        )
    );

  get diagnostics v_leadership_queued = row_count;

  -- Reuses the existing duplicate-safe marker routine.
  select public.queue_open_marker_request_communications(p_fixture_id)
  into v_marker_result;

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'fixture_selected_queued', v_fixture_selected_queued,
    'leadership_queued', v_leadership_queued,
    'marker_communications',
      coalesce(v_marker_result, '{}'::jsonb),
    'total_communications_queued',
      v_fixture_selected_queued
      + v_leadership_queued
      + coalesce(
          (v_marker_result ->> 'communications_queued')::integer,
          0
        )
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."reconcile_preselect_communications"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."reconcile_preselect_communications"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.record_audit_export(p_row_count integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_label text; begin
 if auth.uid() is null or not exists(select 1 from public.app_superusers where user_id=auth.uid()) then raise exception 'Superuser access required'; end if;
 if p_row_count<0 then raise exception 'Invalid row count'; end if;
 select concat_ws(' ',p.first_name,p.last_name) into actor_label from public.member_profiles p where p.user_id=auth.uid() limit 1;
 insert into public.audit_journal(actor_user_id,actor_name,origin,record_type,record_label,action,after_values)
 values(auth.uid(),coalesce(actor_label,auth.uid()::text),'app','audit_journal','Audit CSV export','export requested',jsonb_build_object('row_count',p_row_count));
end $function$;

REVOKE ALL ON FUNCTION "public"."record_audit_export"(p_row_count integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."record_audit_export"(p_row_count integer) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."record_audit_export"(p_row_count integer) TO "service_role";

CREATE OR REPLACE FUNCTION public.remap_green_rink_labels(p_green_area_id uuid, p_old_labels text[], p_new_labels text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_updated_count integer := 0;
begin
  if not (
    current_setting('role',true) = 'service_role'
    or (session_user='postgres' and coalesce(current_setting('role',true),'none') in ('none','postgres'))
    or (auth.uid() is not null and (
      public.is_app_superuser()
      or exists(select 1 from public.green_areas g where g.id=p_green_area_id and public.is_club_admin(g.club_id))
    ))
  ) then raise exception 'Green administrator access required' using errcode='42501'; end if;
  if array_length(p_old_labels, 1) is distinct from array_length(p_new_labels, 1) then
    raise exception 'Old and new rink label lists must be the same length';
  end if;

  with mapping as (
    select
      old_label,
      new_label
    from unnest(p_old_labels, p_new_labels) as m(old_label, new_label)
    where old_label is not null
      and new_label is not null
      and old_label <> new_label
  )
  update public.fixture_rinks fr
  set home_rink_label = mapping.new_label
  from public.fixtures f,
       mapping
  where f.id = fr.fixture_id
    and f.green_area_id = p_green_area_id
    and fr.home_rink_label = mapping.old_label;

  get diagnostics v_updated_count = row_count;

  return v_updated_count;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."remap_green_rink_labels"(p_green_area_id uuid, p_old_labels text[], p_new_labels text[]) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."remap_green_rink_labels"(p_green_area_id uuid, p_old_labels text[], p_new_labels text[]) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."remap_green_rink_labels"(p_green_area_id uuid, p_old_labels text[], p_new_labels text[]) TO "service_role";

CREATE OR REPLACE FUNCTION public.repair_fixture_publication_communications(p_fixture_id uuid)
 RETURNS TABLE(team_selection_id uuid, deleted_notifications integer, deleted_app_notifications integer, deleted_emails integer, queued_notifications integer, processed_notifications integer, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_team_selection_id uuid;
  v_selection_mode text;
  v_before integer;
  v_after integer;
begin
  perform public.communications_require_superuser();

  select ts.id, lower(coalesce(ct.selection_mode::text, ''))
  into v_team_selection_id, v_selection_mode
  from public.fixtures f
  left join public.competition_types ct on ct.id = f.competition_type_id
  join lateral (
    select x.id
    from public.team_selections x
    where x.fixture_id = f.id and x.status::text = 'published'
    order by x.created_at desc
    limit 1
  ) ts on true
  where f.id = p_fixture_id;

  if v_team_selection_id is null then
    raise exception 'Published team selection not found.';
  end if;

  select count(*) into v_before
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_team_selection_id
    and nq.status <> 'cancelled';

  if v_selection_mode = 'preselect' then
    perform public.reconcile_preselect_communications(p_fixture_id);
  else
    perform public.queue_team_publication_communications(
      p_fixture_id,
      v_team_selection_id,
      true
    );
  end if;

  select count(*) into v_after
  from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_team_selection_id
    and nq.status <> 'cancelled';

  return query select
    v_team_selection_id,
    0,
    0,
    0,
    greatest(v_after - v_before, 0),
    0,
    'communications reconciled; no history deleted and no queue processed'::text;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."repair_fixture_publication_communications"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."repair_fixture_publication_communications"(p_fixture_id uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."repair_fixture_publication_communications"(p_fixture_id uuid) TO "authenticated";

CREATE OR REPLACE FUNCTION public.reschedule_cancelled_fixture_safe(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_source public.fixtures%rowtype;

  v_new_fixture_id uuid;
  v_old_team_selection_id uuid;
  v_new_team_selection_id uuid;

  v_is_admin boolean := false;
  v_is_super boolean := false;

  v_free_rinks integer;

  v_old_selection_status selection_status;

  v_fixture_label text;
  v_recipient record;
begin
  --------------------------------------------------------------------
  -- Basic validation
  --------------------------------------------------------------------

  if v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  if p_new_start_at is null
     or p_new_end_at is null
     or p_new_start_at >= p_new_end_at then
    raise exception 'Invalid new fixture start/end time.';
  end if;

  select *
  into v_source
  from public.fixtures
  where id = p_fixture_id
  for update;

  if not found then
    raise exception 'Fixture not found.';
  end if;

  if v_source.cancelled_at is null then
    raise exception
      'Only a cancelled fixture can be rescheduled by this procedure.';
  end if;

  if v_source.rescheduled_to_fixture_id is not null then
    raise exception
      'This cancelled fixture has already been rescheduled.';
  end if;

  --------------------------------------------------------------------
  -- Fixture label for notifications
  --------------------------------------------------------------------

  select coalesce(
    nullif(btrim(v_source.team_name), ''),
    nullif(btrim(ct.name), ''),
    'Fixture'
  )
  into v_fixture_label
  from public.competition_types ct
  where ct.id = v_source.competition_type_id;

  if v_fixture_label is null then
    v_fixture_label := coalesce(
      nullif(btrim(v_source.team_name), ''),
      'Fixture'
    );
  end if;

  --------------------------------------------------------------------
  -- Permission
  --------------------------------------------------------------------

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_source.club_id
      and cm.member_profile_id = v_current_member
      and cm.is_active = true
      and cm.role = 'admin'
  )
  into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  )
  into v_is_super;

  if not (v_is_admin or v_is_super) then
    raise exception
      'You do not have permission to reschedule this fixture.';
  end if;

  --------------------------------------------------------------------
  -- Defensively suppress legacy undelivered operational communications
  -- for the cancelled fixture. Its lifecycle cancellation is preserved.
  --------------------------------------------------------------------

  update public.email_queue eq
  set status = 'cancelled'
  where eq.fixture_id = p_fixture_id
    and eq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and eq.status in ('pending', 'failed')
    and eq.sent_at is null;

  update public.notification_queue nq
  set status = 'cancelled'
  where nq.fixture_id = p_fixture_id
    and nq.event_type in (
      'acceptance_reminder',
      'fixture_message',
      'fixture_moved',
      'fixture_opponent_changed',
      'fixture_rescheduled_availability',
      'fixture_rescheduled_manager',
      'fixture_rescheduled_selected',
      'fixture_selected',
      'marker_request_opened',
      'reserve_promoted',
      'team_acceptance_changed',
      'team_published_captain',
      'team_published_incomplete_request',
      'team_published_not_selected',
      'team_published_player',
      'team_published_reserve',
      'team_published_vice'
    )
    and nq.status = 'pending';

  --------------------------------------------------------------------
  -- Final capacity check for a HOME fixture using rinks
  --------------------------------------------------------------------

  if v_source.is_home = true
     and v_source.green_area_id is not null
     and v_source.rinks_required > 0 then

    select free_capacity_rinks
    into v_free_rinks
    from public.get_green_rink_availability(
      v_source.green_area_id,
      p_new_start_at,
      p_new_end_at
    )
    limit 1;

    if v_free_rinks is null then
      raise exception
        'No rink availability returned for the selected green.';
    end if;

    if v_free_rinks < v_source.rinks_required then
      raise exception
        'Not enough rinks available on the new date: % free, % required.',
        v_free_rinks,
        v_source.rinks_required;
    end if;

  end if;

  --------------------------------------------------------------------
  -- Create the new LIVE fixture
  --------------------------------------------------------------------

  insert into public.fixtures (
    club_id,
    start_at,
    end_at,
    is_home,
    venue_id,
    green_area_id,
    opponent_name,
    opponent_contact,
    notes,
    fixture_type,
    section,
    dress_code,
    rinks_required,
    players_per_rink,
    orientation,
    time_range,
    captain_member_profile_id,
    opponent_venue_id,
    vice_captain_member_profile_id,
    team_name,
    team_id,
    requires_rsvp,
    competition_type_id,
    rescheduled_from_fixture_id,
    rescheduled_at,
    rescheduled_by_member_profile_id
  )
  values (
    v_source.club_id,
    p_new_start_at,
    p_new_end_at,
    v_source.is_home,
    v_source.venue_id,
    v_source.green_area_id,
    v_source.opponent_name,
    v_source.opponent_contact,
    v_source.notes,
    v_source.fixture_type,
    v_source.section,
    v_source.dress_code,
    v_source.rinks_required,
    v_source.players_per_rink,
    v_source.orientation,
    tstzrange(p_new_start_at, p_new_end_at, '[)'),
    v_source.captain_member_profile_id,
    v_source.opponent_venue_id,
    v_source.vice_captain_member_profile_id,
    v_source.team_name,
    v_source.team_id,
    v_source.requires_rsvp,
    v_source.competition_type_id,
    p_fixture_id,
    now(),
    v_current_member
  )
  returning id into v_new_fixture_id;

  --------------------------------------------------------------------
  -- Link OLD cancelled fixture to NEW fixture
  --------------------------------------------------------------------

  update public.fixtures
  set
    rescheduled_to_fixture_id = v_new_fixture_id,
    rescheduled_at = now(),
    rescheduled_by_member_profile_id = v_current_member
  where id = p_fixture_id;

  --------------------------------------------------------------------
  -- Copy logical rink/team structure
  --
  -- Physical rink labels are deliberately NOT carried forward.
  --------------------------------------------------------------------

  insert into public.fixture_rinks (
    fixture_id,
    fixture_rink_no,
    format,
    players_per_rink,
    home_rink_label,
    marker_required
  )
  select
    v_new_fixture_id,
    fr.fixture_rink_no,
    fr.format,
    fr.players_per_rink,
    null,
    fr.marker_required
  from public.fixture_rinks fr
  where fr.fixture_id = p_fixture_id
  order by fr.fixture_rink_no;

  --------------------------------------------------------------------
  -- Carry picked players into same logical team/rink positions
  --------------------------------------------------------------------

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    position,
    display_name
  )
  select
    v_new_fixture_id,
    new_fr.id,
    fra.member_profile_id,
    fra.position,
    fra.display_name
  from public.fixture_rink_assignments fra
  join public.fixture_rinks old_fr
    on old_fr.id = fra.fixture_rink_id
  join public.fixture_rinks new_fr
    on new_fr.fixture_id = v_new_fixture_id
   and new_fr.fixture_rink_no = old_fr.fixture_rink_no
  where fra.fixture_id = p_fixture_id;

  --------------------------------------------------------------------
  -- Find latest team selection on original fixture
  --------------------------------------------------------------------

  select
    ts.id,
    ts.status
  into
    v_old_team_selection_id,
    v_old_selection_status
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc
  limit 1;

  --------------------------------------------------------------------
  -- Recreate team selection on replacement fixture
  --------------------------------------------------------------------

  if v_old_team_selection_id is not null then

    insert into public.team_selections (
      fixture_id,
      status,
      published_at,
      published_by_member_profile_id,
      captain_member_profile_id,
      vice_captain_member_profile_id
    )
    values (
      v_new_fixture_id,
      v_old_selection_status,

      case
        when v_old_selection_status::text = 'published'
          then now()
        else null
      end,

      case
        when v_old_selection_status::text = 'published'
          then v_current_member
        else null
      end,

      v_source.captain_member_profile_id,
      v_source.vice_captain_member_profile_id
    )
    returning id into v_new_team_selection_id;

    ------------------------------------------------------------------
    -- Carry players/reserves but reset ALL acceptance responses
    ------------------------------------------------------------------

    insert into public.team_selection_members (
      team_selection_id,
      member_profile_id,
      role,
      acceptance,
      responded_at,
      is_selected,
      acceptance_by
    )
    select
      v_new_team_selection_id,
      tsm.member_profile_id,
      tsm.role,
      'pending'::acceptance_status,
      null,
      tsm.is_selected,
      null
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_old_team_selection_id;

  end if;

  --------------------------------------------------------------------
  -- Deliberately DO NOT copy fixture_rsvps.
  --
  -- Availability belongs to the old date.
  --------------------------------------------------------------------

  --------------------------------------------------------------------
  -- Queue reschedule communications
  --
  -- Precedence:
  --   1. Captain / Vice            -> manager
  --   2. Selected player/reserve   -> selected
  --   3. Other eligible member     -> availability
  --------------------------------------------------------------------

  for v_recipient in
  with managers as (
    select v_source.captain_member_profile_id as member_profile_id
    where v_source.captain_member_profile_id is not null

    union

    select v_source.vice_captain_member_profile_id
    where v_source.vice_captain_member_profile_id is not null
  ),

  selected_members as (
    select distinct tsm.member_profile_id
    from public.team_selection_members tsm
    where tsm.team_selection_id = v_new_team_selection_id
      and tsm.member_profile_id is not null
      and coalesce(tsm.is_selected, false) = true
      and not exists (
        select 1
        from managers m
        where m.member_profile_id = tsm.member_profile_id
      )
  ),

  eligible_team_members as (
    select distinct tm.member_profile_id
    from public.team_members tm
    where v_source.team_id is not null
      and tm.team_id = v_source.team_id
      and tm.is_active = true
  ),

  eligible_rsvp_members as (
    select distinct fr.member_profile_id
    from public.fixture_rsvps fr
    join public.club_memberships cm
      on cm.club_id = v_source.club_id
    and cm.member_profile_id = fr.member_profile_id
    and cm.is_active = true
    where v_source.team_id is null
      and fr.fixture_id = p_fixture_id
      and fr.status::text in ('yes', 'maybe')
  ),

  availability_members as (
    select member_profile_id
    from eligible_team_members

    union

    select member_profile_id
    from eligible_rsvp_members
  ),

  recipients as (
    ------------------------------------------------------------------
    -- Managers have highest precedence
    ------------------------------------------------------------------
    select
      m.member_profile_id,
      'fixture_rescheduled_manager'::text as event_type
    from managers m

    union all

    ------------------------------------------------------------------
    -- Selected players/reserves who are not managers
    ------------------------------------------------------------------
    select
      s.member_profile_id,
      'fixture_rescheduled_selected'::text
    from selected_members s

    union all

    ------------------------------------------------------------------
    -- Remaining eligible members can submit fresh availability
    ------------------------------------------------------------------
    select
      a.member_profile_id,
      'fixture_rescheduled_availability'::text
    from availability_members a
    where not exists (
      select 1
      from managers m
      where m.member_profile_id = a.member_profile_id
    )
    and not exists (
      select 1
      from selected_members s
      where s.member_profile_id = a.member_profile_id
    )
  )
  select
    r.member_profile_id,
    r.event_type,
    case
      when r.event_type = 'fixture_rescheduled_selected'
       and exists (
         select 1
         from public.fixture_rink_assignments fra
         join public.team_selection_members tsm
           on tsm.team_selection_id = v_new_team_selection_id
          and tsm.member_profile_id = fra.member_profile_id
          and coalesce(tsm.is_selected, false) = true
          and lower(tsm.role::text) = 'marker'
         where fra.fixture_id = v_new_fixture_id
           and fra.member_profile_id = r.member_profile_id
           and fra.position = 201
       )
        then 'marker'::text
      else null::text
    end as recipient_role
  from recipients r
  where r.member_profile_id is not null
  loop
    -- Replace only this recipient's undelivered cancellation with the
    -- rescheduling event. Sent cancellations remain part of the audit trail.
    delete from public.notification_queue nq
    where nq.fixture_id = p_fixture_id
      and nq.target_member_profile_id = v_recipient.member_profile_id
      and nq.event_type = 'fixture_cancelled'
      and nq.status = 'pending';

    insert into public.notification_queue (
      event_type,
      member_profile_id,
      target_member_profile_id,
      fixture_id,
      team_selection_id,
      payload,
      status
    )
    select
      v_recipient.event_type,
      v_current_member,
      v_recipient.member_profile_id,
      v_new_fixture_id,
      v_new_team_selection_id,
      jsonb_strip_nulls(
        jsonb_build_object(
          'fixture_label', v_fixture_label,
          'old_fixture_id', p_fixture_id,
          'new_fixture_id', v_new_fixture_id,
          'old_start_at', v_source.start_at,
          'old_end_at', v_source.end_at,
          'new_start_at', p_new_start_at,
          'new_end_at', p_new_end_at,
          'recipient_role', v_recipient.recipient_role
        )
      ),
      'pending'
    where not exists (
      select 1
      from public.notification_queue nq
      where nq.fixture_id = v_new_fixture_id
        and nq.target_member_profile_id = v_recipient.member_profile_id
        and nq.event_type = v_recipient.event_type
        and nq.status in ('pending', 'sent')
    );
  end loop;

  --------------------------------------------------------------------
  -- Lifecycle audit
  --------------------------------------------------------------------

  insert into public.fixture_lifecycle_events (
    fixture_id,
    event_type,
    old_start_at,
    old_end_at,
    new_start_at,
    new_end_at,
    reason,
    created_by_member_profile_id
  )
  values (
    p_fixture_id,
    'rescheduled',
    v_source.start_at,
    v_source.end_at,
    p_new_start_at,
    p_new_end_at,
    v_source.cancellation_reason,
    v_current_member
  );

  return v_new_fixture_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."reschedule_cancelled_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."reschedule_cancelled_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."reschedule_cancelled_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."reschedule_cancelled_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."reschedule_cancelled_fixture_safe"(p_fixture_id uuid, p_new_start_at timestamp with time zone, p_new_end_at timestamp with time zone) TO "service_role";

CREATE OR REPLACE FUNCTION public.reset_fixture_publication_test(p_fixture_id uuid)
 RETURNS TABLE(fixture_id uuid, team_selection_id uuid, deleted_notification_queue integer, deleted_app_notifications integer, deleted_email_queue integer, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_team_selection_id uuid;
  v_nq integer;
  v_an integer;
  v_eq integer;
begin
  -- current_user is the function owner here; inspect the invoking SQL role instead.
  if not (
    current_setting('role', true) = 'service_role'
    or (session_user = 'postgres' and coalesce(current_setting('role', true), 'none') in ('none','postgres'))
    or (auth.uid() is not null and public.is_app_superuser())
  ) then
    raise exception 'Superuser or server access required' using errcode = '42501';
  end if;
  select ts.id
  into v_team_selection_id
  from public.team_selections ts
  where ts.fixture_id = p_fixture_id
  order by ts.created_at desc
  limit 1;

  if v_team_selection_id is null then
    raise exception 'No team selection found for fixture %', p_fixture_id;
  end if;

  update public.team_selections
  set status = 'draft',
      published_by_member_profile_id = null
  where id = v_team_selection_id;

  delete from public.notification_queue nq
  where nq.fixture_id = p_fixture_id
    and nq.team_selection_id = v_team_selection_id
    and nq.event_type like 'team_published%';
  get diagnostics v_nq = row_count;

  delete from public.app_notifications an
  where an.fixture_id = p_fixture_id
    and an.team_selection_id = v_team_selection_id
    and an.type like 'team_published%';
  get diagnostics v_an = row_count;

  delete from public.email_queue eq
  where eq.fixture_id = p_fixture_id
    and eq.team_selection_id = v_team_selection_id
    and eq.event_type like 'team_published%';
  get diagnostics v_eq = row_count;

  return query select
    p_fixture_id,
    v_team_selection_id,
    v_nq,
    v_an,
    v_eq,
    'reset to draft'::text;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."reset_fixture_publication_test"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."reset_fixture_publication_test"(p_fixture_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."reset_fixture_publication_test"(p_fixture_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.retry_fixture_failed_emails(p_fixture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_ids uuid[];
begin
  perform public.communications_require_superuser();

  update public.email_queue eq
  set status = 'pending', attempts = 0, last_error = null,
      processing_started_at = null, locked_at = null, locked_by = null
  where eq.fixture_id = p_fixture_id
    and eq.status = 'failed'
    and eq.sent_at is null
    and eq.last_error is distinct from
        'Required Team Sheet attachment is missing or stale.'
  ;

  select coalesce(array_agg(eq.id order by eq.created_at), array[]::uuid[])
  into v_ids
  from public.email_queue eq
  where eq.fixture_id = p_fixture_id and eq.status = 'pending';

  return jsonb_build_object(
    'fixture_id', p_fixture_id,
    'email_queue_ids', to_jsonb(v_ids),
    'pending_count', cardinality(v_ids)
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."retry_fixture_failed_emails"(p_fixture_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."retry_fixture_failed_emails"(p_fixture_id uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."retry_fixture_failed_emails"(p_fixture_id uuid) TO "authenticated";

CREATE OR REPLACE FUNCTION public.run_email_responses_now()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_secret text; v_request_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets
    where name='edge_internal_auth_token';
  if nullif(v_secret,'') is null then raise exception 'Production worker secret is missing'; end if;
  select net.http_post(
    url:='https://xfjelvvfoguzukgvxchh.supabase.co/functions/v1/process-email-responses',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_secret,'apikey',v_secret),
    body:='{}'::jsonb,timeout_milliseconds:=60000
  ) into v_request_id;
  return jsonb_build_object('ok',true,'request_id',v_request_id);
end $function$;

REVOKE ALL ON FUNCTION "public"."run_email_responses_now"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."run_email_responses_now"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."run_email_responses_now"() TO "service_role";

CREATE OR REPLACE FUNCTION public.save_fixture_rink_assignments(p_fixture_id uuid, p_team_selection_id uuid, p_assignments jsonb DEFAULT '[]'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_current_member uuid := public.my_member_profile_id();
  v_fixture_id uuid;
  v_club_id uuid;
  v_selection_status text;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_promoted_ids uuid[] := array[]::uuid[];
  v_promoted_id uuid;
begin
  if auth.uid() is null or v_current_member is null then
    raise exception 'Not signed in.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));

  select ts.fixture_id, f.club_id, ts.status::text,
         lower(btrim(coalesce(ct.selection_mode, ''))),
         f.team_id, coalesce(f.requires_rsvp, false)
  into v_fixture_id, v_club_id, v_selection_status,
       v_selection_mode, v_team_id, v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
  for update of ts;

  if not found then raise exception 'Team selection not found.'; end if;
  if p_fixture_id is distinct from v_fixture_id then
    raise exception 'Team selection does not belong to this fixture.';
  end if;

  if not (
    public.is_app_superuser()
    or (
      exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = v_current_member
          and cm.is_active = true
          and lower(cm.role::text) <> 'guest'
      )
      and (
        public.can_manage_team_selection(v_fixture_id)
        or exists (
          select 1 from public.fixtures f
          where f.id = v_fixture_id
            and v_current_member in (
              f.captain_member_profile_id,
              f.vice_captain_member_profile_id
            )
        )
      )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  if v_selection_status = 'published'
     and v_selection_mode <> 'preselect'
     and (v_team_id is not null or v_requires_rsvp) then
    raise exception 'Published Team/RSVP composition changes must be confirmed together.';
  end if;

  if exists (
    select 1
    from (
      select item->>'member_profile_id' as member_profile_id
      from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
      where nullif(item->>'member_profile_id', '') is not null
      group by item->>'member_profile_id'
      having count(*) > 1
    ) d
  ) then
    raise exception 'A player cannot be assigned more than once.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    left join public.fixture_rinks fr
      on fr.id = (item->>'fixture_rink_id')::uuid
     and fr.fixture_id = v_fixture_id
    where fr.id is null
  ) then
    raise exception 'Invalid team/rink assignment.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    left join public.team_selection_members tsm
      on tsm.team_selection_id = p_team_selection_id
     and tsm.member_profile_id = (item->>'member_profile_id')::uuid
     and tsm.is_selected = true
    where nullif(item->>'member_profile_id', '') is not null
      and tsm.member_profile_id is null
  ) then
    raise exception 'Assigned member is not active in the team selection.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
    join public.team_selection_members tsm
      on tsm.team_selection_id = p_team_selection_id
     and tsm.member_profile_id = (item->>'member_profile_id')::uuid
     and tsm.is_selected = true
     and tsm.role in (
       'player'::public.selection_member_role,
       'reserve'::public.selection_member_role
     )
    where nullif(item->>'member_profile_id', '') is not null
      and not exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = tsm.member_profile_id
          and cm.is_active = true
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception 'Target member is not an active non-Guest member of this club';
  end if;

  perform 1
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
  for update;

  with promoted as (
    update public.team_selection_members tsm
    set role = 'player'::selection_member_role,
        acceptance = 'pending'::acceptance_status,
        responded_at = null,
        acceptance_by = null
    where tsm.team_selection_id = p_team_selection_id
      and tsm.role = 'reserve'::selection_member_role
      and tsm.is_selected = true
      and exists (
        select 1
        from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
        where (item->>'member_profile_id')::uuid = tsm.member_profile_id
      )
    returning tsm.id
  )
  select coalesce(array_agg(id), array[]::uuid[]) into v_promoted_ids
  from promoted;

  delete from public.notification_queue
  where fixture_id = v_fixture_id
    and team_selection_id = p_team_selection_id
    and event_type = 'team_acceptance_changed'
    and status = 'pending'
    and payload->>'new_acceptance' = 'pending'
    and member_profile_id in (
      select tsm.member_profile_id
      from public.team_selection_members tsm
      where tsm.id = any(v_promoted_ids)
    );

  delete from public.fixture_rink_assignments
  where fixture_id = v_fixture_id;

  insert into public.fixture_rink_assignments (
    fixture_id,
    fixture_rink_id,
    member_profile_id,
    position
  )
  select
    v_fixture_id,
    (item->>'fixture_rink_id')::uuid,
    (item->>'member_profile_id')::uuid,
    (item->>'position')::integer
  from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) item
  where nullif(item->>'member_profile_id', '') is not null;

  foreach v_promoted_id in array v_promoted_ids loop
    perform public.queue_post_publication_player_change(
      v_promoted_id, 'reserve_promoted', v_current_member
    );
  end loop;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."save_fixture_rink_assignments"(p_fixture_id uuid, p_team_selection_id uuid, p_assignments jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."save_fixture_rink_assignments"(p_fixture_id uuid, p_team_selection_id uuid, p_assignments jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."save_fixture_rink_assignments"(p_fixture_id uuid, p_team_selection_id uuid, p_assignments jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.save_preselect_fixture_state(p_fixture_id uuid, p_assignments jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        and lower(cm.role::text) <> 'guest'
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
  --   1â€“4       players
  --   101â€“104   opponents
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

  -- External names are valid for player and opponent positions.
  if exists (
    select 1
    from preselect_desired_assignments
    where display_name is not null
      and role not in ('player', 'opponent')
  ) then
    raise exception
      'External names may only be used for player or opponent positions.';
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
          and lower(cm.role::text) <> 'guest'
      )
  ) then
    raise exception
      'One or more selected people are not active non-Guest members of this club.';
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
  -- A confirmed re-addition starts a fresh acceptance cycle.
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

      when existing.is_selected = false
        then 'pending'::acceptance_status

      when existing.role = excluded.role
        then existing.acceptance

      else 'pending'::acceptance_status
    end,

    responded_at = case
      when existing.is_selected = true
       and existing.role = excluded.role
        then existing.responded_at
      else null
    end,

    acceptance_by = case
      when existing.is_selected = true
       and existing.role = excluded.role
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
  perform set_config(
    'app.preselect_reselected_member_ids',
    coalesce(
      (
        select string_agg(d.member_profile_id::text, ',')
        from preselect_desired_members d
        left join preselect_old_selected o
          on o.member_profile_id = d.member_profile_id
        where o.member_profile_id is null
      ),
      ''
    ),
    true
  );

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
$function$;

REVOKE ALL ON FUNCTION "public"."save_preselect_fixture_state"(p_fixture_id uuid, p_assignments jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."save_preselect_fixture_state"(p_fixture_id uuid, p_assignments jsonb) TO "authenticated";

CREATE OR REPLACE FUNCTION public.set_club_created_by()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.created_by := auth.uid();
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_club_created_by"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_club_created_by"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."set_club_created_by"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."set_club_created_by"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_club_created_by"() TO "service_role";

CREATE OR REPLACE FUNCTION public.set_email_queue_cron_enabled(p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
declare v_job_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select jobid into v_job_id from cron.job
    where jobname='bowls-process-email-queue' limit 1;
  if v_job_id is null then raise exception 'Email cron job is missing'; end if;
  perform cron.alter_job(v_job_id,active:=p_enabled);
  return jsonb_build_object('ok',true,'job_id',v_job_id,'active',p_enabled);
end $function$;

REVOKE ALL ON FUNCTION "public"."set_email_queue_cron_enabled"(p_enabled boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_email_queue_cron_enabled"(p_enabled boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_email_queue_cron_enabled"(p_enabled boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.set_email_responses_cron_enabled(p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
declare v_job_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select jobid into v_job_id from cron.job
    where jobname='bowls-process-email-responses' limit 1;
  if v_job_id is null then raise exception 'Email receipt cron job is missing'; end if;
  perform cron.alter_job(v_job_id,active:=p_enabled);
  return jsonb_build_object('ok',true,'job_id',v_job_id,'active',p_enabled);
end $function$;

REVOKE ALL ON FUNCTION "public"."set_email_responses_cron_enabled"(p_enabled boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_email_responses_cron_enabled"(p_enabled boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_email_responses_cron_enabled"(p_enabled boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.set_fixture_time_range()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
  new.time_range :=
    tstzrange(
      new.start_at,
      coalesce(new.end_at, new.start_at + interval '4 hours'),
      '[)'
    );
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_fixture_time_range"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_fixture_time_range"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."set_fixture_time_range"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."set_fixture_time_range"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_fixture_time_range"() TO "service_role";

CREATE OR REPLACE FUNCTION public.set_mailing_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_mailing_updated_at"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_mailing_updated_at"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."set_mailing_updated_at"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."set_mailing_updated_at"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_mailing_updated_at"() TO "service_role";

CREATE OR REPLACE FUNCTION public.set_my_mailing_list_membership(p_mailing_list_id uuid, p_join boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_member_profile_id uuid;
  v_club_id uuid;
  v_list_name text;
  v_is_active boolean;
  v_allow_self_subscription boolean;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in.';
  end if;

  select public.my_member_profile_id()
  into v_member_profile_id;

  if v_member_profile_id is null then
    raise exception 'No member profile was found for the signed-in user.';
  end if;

  select
    ml.club_id,
    ml.name,
    ml.is_active,
    ml.allow_self_subscription
  into
    v_club_id,
    v_list_name,
    v_is_active,
    v_allow_self_subscription
  from public.mailing_lists ml
  where ml.id = p_mailing_list_id;

  if not found then
    raise exception 'Mailing list not found.';
  end if;

  if not v_is_active then
    raise exception 'This mailing list is inactive.';
  end if;

  if not v_allow_self_subscription then
    raise exception 'This mailing list is managed by the club administrator.';
  end if;

  if not exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_member_profile_id
      and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
  ) then
    raise exception 'You are not eligible to join mailing or volunteer lists.';
  end if;

  if coalesce(p_join, false) then
    insert into public.mailing_list_members (
      mailing_list_id,
      member_profile_id,
      is_active,
      added_by_member_profile_id,
      added_at,
      removed_at
    )
    values (
      p_mailing_list_id,
      v_member_profile_id,
      true,
      v_member_profile_id,
      now(),
      null
    )
    on conflict (mailing_list_id, member_profile_id)
    do update set
      is_active = true,
      added_by_member_profile_id = excluded.added_by_member_profile_id,
      added_at = now(),
      removed_at = null;
  else
    delete from public.mailing_list_members mlm
    where mlm.mailing_list_id = p_mailing_list_id
      and mlm.member_profile_id = v_member_profile_id;
  end if;

  return jsonb_build_object(
    'mailing_list_id', p_mailing_list_id,
    'mailing_list_name', v_list_name,
    'member_profile_id', v_member_profile_id,
    'is_joined', coalesce(p_join, false)
  );
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_my_mailing_list_membership"(p_mailing_list_id uuid, p_join boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_my_mailing_list_membership"(p_mailing_list_id uuid, p_join boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."set_my_mailing_list_membership"(p_mailing_list_id uuid, p_join boolean) TO "anon";

GRANT EXECUTE ON FUNCTION "public"."set_my_mailing_list_membership"(p_mailing_list_id uuid, p_join boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_my_mailing_list_membership"(p_mailing_list_id uuid, p_join boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.set_notification_queue_cron_enabled(p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron'
AS $function$
declare v_job_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.app_superusers where user_id=auth.uid()
  ) then raise exception 'Superuser access required'; end if;
  select jobid into v_job_id from cron.job
    where jobname='bowls-process-notification-queue' limit 1;
  if v_job_id is null then raise exception 'Notification cron job is missing'; end if;
  perform cron.alter_job(v_job_id,active:=p_enabled);
  return jsonb_build_object('ok',true,'job_id',v_job_id,'active',p_enabled);
end $function$;

REVOKE ALL ON FUNCTION "public"."set_notification_queue_cron_enabled"(p_enabled boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_notification_queue_cron_enabled"(p_enabled boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_notification_queue_cron_enabled"(p_enabled boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.set_rsvp_member_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
  if new.member_profile_id is null then
    new.member_profile_id := public.my_member_profile_id();
  end if;
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_rsvp_member_profile"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_rsvp_member_profile"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."set_rsvp_member_profile"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."set_rsvp_member_profile"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_rsvp_member_profile"() TO "service_role";

CREATE OR REPLACE FUNCTION public.set_team_selection_member_active(p_team_selection_id uuid, p_member_profile_id uuid, p_is_selected boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_selection_status text;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_member public.team_selection_members%rowtype;
  v_queued boolean := false;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  v_actor := public.my_member_profile_id();
  if v_actor is null then raise exception 'Member profile not found.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));
  select ts.fixture_id, f.club_id, ts.status::text,
         lower(btrim(coalesce(ct.selection_mode, ''))),
         f.team_id, coalesce(f.requires_rsvp, false)
  into v_fixture_id, v_club_id, v_selection_status,
       v_selection_mode, v_team_id, v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
  for update of ts;
  if not found then raise exception 'Team selection not found.'; end if;
  if not (
    public.is_app_superuser()
    or (
      exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = v_actor
          and cm.is_active = true
          and lower(cm.role::text) <> 'guest'
      )
      and (
        public.can_manage_team_selection(v_fixture_id)
        or exists (
          select 1 from public.fixtures f
          where f.id = v_fixture_id
            and v_actor in (
              f.captain_member_profile_id,
              f.vice_captain_member_profile_id
            )
        )
      )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  select * into v_member from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and member_profile_id = p_member_profile_id for update;

  if v_selection_status = 'published'
     and v_selection_mode <> 'preselect'
     and (v_team_id is not null or v_requires_rsvp)
     and (
       (p_is_selected and (not found or not coalesce(v_member.is_selected, false)))
       or (not p_is_selected and found and coalesce(v_member.is_selected, false))
     ) then
    raise exception 'Published Team/RSVP composition changes must be confirmed together.';
  end if;

  if p_is_selected then
    if not exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = v_club_id
        and cm.member_profile_id = p_member_profile_id
        and cm.is_active = true
        and lower(cm.role::text) <> 'guest'
    ) then
      raise exception 'Target member is not an active non-Guest member of this club';
    end if;

    if found and v_member.is_selected then
      return jsonb_build_object('action', 'no_change', 'queued', false);
    end if;

    insert into public.team_selection_members (
      team_selection_id, member_profile_id, role, acceptance,
      responded_at, is_selected, acceptance_by
    ) values (
      p_team_selection_id, p_member_profile_id, 'player', 'pending', null, true, null
    )
    on conflict (team_selection_id, member_profile_id) do update set
      role = 'player', acceptance = 'pending', responded_at = null,
      is_selected = true, acceptance_by = null
    returning * into v_member;

    delete from public.notification_queue
    where fixture_id = v_fixture_id
      and team_selection_id = p_team_selection_id
      and member_profile_id = p_member_profile_id
      and event_type = 'team_acceptance_changed'
      and status = 'pending'
      and payload->>'new_acceptance' = 'pending';

    v_queued := public.queue_post_publication_player_change(v_member.id, 'fixture_selected', v_actor);
    return jsonb_build_object('action', 'selected', 'queued', v_queued);
  end if;

  if not found or not v_member.is_selected then
    return jsonb_build_object('action', 'no_change', 'queued', false);
  end if;

  update public.team_selection_members set is_selected = false where id = v_member.id;
  delete from public.fixture_rink_assignments
  where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id;
  update public.email_action_requests set status = 'cancelled', updated_at = now()
  where target_record_id = v_member.id and status in ('pending', 'responded');
  update public.notification_queue set status = 'cancelled'
  where fixture_id = v_fixture_id and target_member_profile_id = p_member_profile_id
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player', 'team_published_reserve')
    and status = 'pending';
  update public.email_queue set status = 'cancelled'
  where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id
    and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player', 'team_published_reserve')
    and status in ('pending', 'failed') and sent_at is null;

  return jsonb_build_object('action', 'removed', 'queued', false);
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_team_selection_member_active"(p_team_selection_id uuid, p_member_profile_id uuid, p_is_selected boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_team_selection_member_active"(p_team_selection_id uuid, p_member_profile_id uuid, p_is_selected boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_team_selection_member_active"(p_team_selection_id uuid, p_member_profile_id uuid, p_is_selected boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.set_team_selection_member_role(p_team_selection_id uuid, p_member_profile_id uuid, p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_fixture_id uuid;
  v_club_id uuid;
  v_selection_status text;
  v_selection_mode text;
  v_team_id uuid;
  v_requires_rsvp boolean;
  v_member public.team_selection_members%rowtype;
  v_new_role text := lower(btrim(coalesce(p_role, '')));
  v_queued boolean := false;
begin
  if auth.uid() is null then raise exception 'Not signed in.'; end if;
  v_actor := public.my_member_profile_id();
  if v_actor is null then raise exception 'Member profile not found.'; end if;
  if v_new_role not in ('player', 'reserve') then raise exception 'Unsupported role transition.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_team_selection_id::text, 0));
  select ts.fixture_id, f.club_id, ts.status::text,
         lower(btrim(coalesce(ct.selection_mode, ''))),
         f.team_id, coalesce(f.requires_rsvp, false)
  into v_fixture_id, v_club_id, v_selection_status,
       v_selection_mode, v_team_id, v_requires_rsvp
  from public.team_selections ts
  join public.fixtures f on f.id = ts.fixture_id
  left join public.competition_types ct on ct.id = f.competition_type_id
  where ts.id = p_team_selection_id
  for update of ts;
  if not found then raise exception 'Team selection not found.'; end if;
  if not (
    public.is_app_superuser()
    or (
      exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = v_club_id
          and cm.member_profile_id = v_actor
          and cm.is_active = true
          and lower(cm.role::text) <> 'guest'
      )
      and (
        public.can_manage_team_selection(v_fixture_id)
        or exists (
          select 1 from public.fixtures f
          where f.id = v_fixture_id
            and v_actor in (
              f.captain_member_profile_id,
              f.vice_captain_member_profile_id
            )
        )
      )
    )
  ) then
    raise exception 'You do not have permission to manage this fixture.';
  end if;

  select * into strict v_member from public.team_selection_members
  where team_selection_id = p_team_selection_id
    and member_profile_id = p_member_profile_id for update;
  if not v_member.is_selected then raise exception 'Member is not actively selected.'; end if;

  if not exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = p_member_profile_id
      and cm.is_active = true
      and lower(cm.role::text) <> 'guest'
  ) then
    raise exception 'Target member is not an active non-Guest member of this club';
  end if;

  if v_member.role::text = v_new_role then
    return jsonb_build_object('action', 'no_change', 'queued', false);
  end if;

  if v_selection_status = 'published'
     and v_selection_mode <> 'preselect'
     and (v_team_id is not null or v_requires_rsvp) then
    raise exception 'Published Team/RSVP composition changes must be confirmed together.';
  end if;

  if v_member.role = 'reserve' and v_new_role = 'player' then
    update public.team_selection_members set
      role = 'player', acceptance = 'pending', responded_at = null, acceptance_by = null
    where id = v_member.id;
    delete from public.notification_queue
    where fixture_id = v_fixture_id
      and team_selection_id = p_team_selection_id
      and member_profile_id = p_member_profile_id
      and event_type = 'team_acceptance_changed'
      and status = 'pending'
      and payload->>'new_acceptance' = 'pending';
    v_queued := public.queue_post_publication_player_change(v_member.id, 'reserve_promoted', v_actor);
    return jsonb_build_object('action', 'reserve_promoted', 'queued', v_queued);
  end if;

  if v_member.role = 'player' and v_new_role = 'reserve' then
    update public.team_selection_members set role = 'reserve' where id = v_member.id;
    delete from public.fixture_rink_assignments
    where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id;
    update public.email_action_requests set status = 'cancelled', updated_at = now()
    where target_record_id = v_member.id and status in ('pending', 'responded');
    update public.notification_queue set status = 'cancelled'
    where fixture_id = v_fixture_id and target_member_profile_id = p_member_profile_id
      and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
      and status = 'pending';
    update public.email_queue set status = 'cancelled'
    where fixture_id = v_fixture_id and member_profile_id = p_member_profile_id
      and event_type in ('fixture_selected', 'reserve_promoted', 'team_published_player')
      and status in ('pending', 'failed') and sent_at is null;
    return jsonb_build_object('action', 'player_demoted', 'queued', false);
  end if;

  raise exception 'Unsupported role transition.';
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_team_selection_member_role"(p_team_selection_id uuid, p_member_profile_id uuid, p_role text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_team_selection_member_role"(p_team_selection_id uuid, p_member_profile_id uuid, p_role text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_team_selection_member_role"(p_team_selection_id uuid, p_member_profile_id uuid, p_role text) TO "service_role";

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_updated_at"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."set_updated_at"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."set_updated_at"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."set_updated_at"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."set_updated_at"() TO "service_role";

CREATE OR REPLACE FUNCTION public.swap_fixture_rink_labels(p_a_fixture_rink_id uuid, p_b_fixture_rink_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  a_label text;
  b_label text;
  a_fixture_id uuid;
  b_fixture_id uuid;
begin
  select fr.home_rink_label, fr.fixture_id
  into a_label, a_fixture_id
  from public.fixture_rinks fr
  where fr.id = p_a_fixture_rink_id;

  select fr.home_rink_label, fr.fixture_id
  into b_label, b_fixture_id
  from public.fixture_rinks fr
  where fr.id = p_b_fixture_rink_id;

  if a_fixture_id is null or b_fixture_id is null then
    raise exception 'Both fixture rinks must exist.';
  end if;

  if not public.can_manage_fixture(a_fixture_id)
     or not public.can_manage_fixture(b_fixture_id) then
    raise exception 'You do not have permission to move these rink bookings.';
  end if;

  if a_label is null or b_label is null then
    raise exception 'Both fixture rinks must have a home_rink_label before swapping.';
  end if;

  update public.fixture_rinks
  set home_rink_label = null
  where id = p_a_fixture_rink_id;

  update public.fixture_rinks
  set home_rink_label = a_label
  where id = p_b_fixture_rink_id;

  update public.fixture_rinks
  set home_rink_label = b_label
  where id = p_a_fixture_rink_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."swap_fixture_rink_labels"(p_a_fixture_rink_id uuid, p_b_fixture_rink_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."swap_fixture_rink_labels"(p_a_fixture_rink_id uuid, p_b_fixture_rink_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."swap_fixture_rink_labels"(p_a_fixture_rink_id uuid, p_b_fixture_rink_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.team_admin_add_member(p_team_selection_id uuid, p_member_profile_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fixture_id uuid;
  v_club_id uuid;
  v_requester_profile uuid;
  v_is_admin boolean;
  v_is_super boolean;
  v_existing uuid;
  v_new_id uuid;
begin
  -- Resolve fixture_id from team selection
  select ts.fixture_id into v_fixture_id
  from public.team_selections ts
  where ts.id = p_team_selection_id;

  if v_fixture_id is null then
    raise exception 'Team selection not found';
  end if;

  -- Resolve club_id from fixture
  select f.club_id into v_club_id
  from public.fixtures f
  where f.id = v_fixture_id;

  -- Requester member_profile_id from auth user
  select mp.id into v_requester_profile
  from public.member_profiles mp
  where mp.user_id = auth.uid();

  if v_requester_profile is null then
    raise exception 'Member profile not found for current user';
  end if;

  -- Superuser?
  select exists (
    select 1 from public.app_superusers su
    where su.user_id = auth.uid()
  ) into v_is_super;

  -- Club admin?
  select exists (
    select 1 from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_requester_profile
      and cm.role = 'admin'
      and cm.is_active = true
  ) into v_is_admin;

  if not (v_is_admin or v_is_super) then
    raise exception 'Not authorized' using errcode='42501';
  end if;

  if not exists(select 1 from public.club_memberships target
    where target.club_id=v_club_id and target.member_profile_id=p_member_profile_id
      and target.is_active and target.role::text<>'guest') then
    raise exception 'Player must be an active non-guest member of the fixture club' using errcode='42501';
  end if;

  -- Already selected?
  select tsm.id into v_existing
  from public.team_selection_members tsm
  where tsm.team_selection_id = p_team_selection_id
    and tsm.member_profile_id = p_member_profile_id
  limit 1;

  if v_existing is null then
    -- Insert as pending player
    insert into public.team_selection_members(
      team_selection_id,
      member_profile_id,
      role,
      acceptance
    )
    values (
      p_team_selection_id,
      p_member_profile_id,
      'player'::public.selection_member_role,
      'pending'::public.acceptance_status
    )
    returning id into v_new_id;
  else
    v_new_id := v_existing;
  end if;

  -- Ensure they appear in RSVP pool used by ManageTeamScreen
  insert into public.fixture_rsvps (fixture_id, member_profile_id, status)
  values (v_fixture_id, p_member_profile_id, 'yes'::public.rsvp_status)
  on conflict (fixture_id, member_profile_id) do update
    set status = excluded.status;

  return v_new_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."team_admin_add_member"(p_team_selection_id uuid, p_member_profile_id uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."team_admin_add_member"(p_team_selection_id uuid, p_member_profile_id uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."team_admin_add_member"(p_team_selection_id uuid, p_member_profile_id uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.team_admin_set_acceptance(p_team_selection_member_id uuid, p_acceptance text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_club_id uuid;
  v_member_profile_id uuid;
  v_is_admin boolean;
  v_is_super boolean;
begin
  if p_acceptance not in ('pending','accepted','declined') then
    raise exception 'Invalid acceptance value: %', p_acceptance;
  end if;

  select f.club_id
    into v_club_id
  from public.team_selection_members tsm
  join public.team_selections ts on ts.id = tsm.team_selection_id
  join public.fixtures f on f.id = ts.fixture_id
  where tsm.id = p_team_selection_member_id;

  if v_club_id is null then
    raise exception 'Team selection member not found';
  end if;

  select mp.id
    into v_member_profile_id
  from public.member_profiles mp
  where mp.user_id = auth.uid();

  if v_member_profile_id is null then
    raise exception 'Member profile not found for current user';
  end if;

  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = v_member_profile_id
      and cm.role = 'admin'
      and cm.is_active = true
  ) into v_is_admin;

  select exists (
    select 1
    from public.app_superusers su
    where su.user_id = auth.uid()
  ) into v_is_super;

  if not (v_is_admin or v_is_super) then
    raise exception 'Not authorized' using errcode='42501';
  end if;

  update public.team_selection_members
  set acceptance = p_acceptance::acceptance_status
  where id = p_team_selection_member_id;

  return true;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."team_admin_set_acceptance"(p_team_selection_member_id uuid, p_acceptance text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."team_admin_set_acceptance"(p_team_selection_member_id uuid, p_acceptance text) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."team_admin_set_acceptance"(p_team_selection_member_id uuid, p_acceptance text) TO "service_role";

CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
  new.updated_at = now();
  return new;
end $function$;

REVOKE ALL ON FUNCTION "public"."touch_updated_at"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."touch_updated_at"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."touch_updated_at"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."touch_updated_at"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."touch_updated_at"() TO "service_role";

CREATE OR REPLACE FUNCTION public.update_club_venue_full(p_venue_id uuid, p_club_id uuid, p_name text, p_is_home_venue boolean DEFAULT false, p_town_city text DEFAULT NULL::text, p_postcode text DEFAULT NULL::text, p_contact_name text DEFAULT NULL::text, p_contact_phone text DEFAULT NULL::text, p_contact_email text DEFAULT NULL::text, p_address_line1 text DEFAULT NULL::text, p_address_line2 text DEFAULT NULL::text, p_directions_url text DEFAULT NULL::text, p_website_url text DEFAULT NULL::text, p_google_maps_url text DEFAULT NULL::text, p_google_place_id text DEFAULT NULL::text, p_latitude double precision DEFAULT NULL::double precision, p_longitude double precision DEFAULT NULL::double precision, p_club_officers jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_is_superuser boolean := false;
  v_is_club_admin boolean := false;
  v_member_profile_id uuid;
  v_existing_home boolean;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to update a venue.';
  end if;

  if p_venue_id is null or p_club_id is null then
    raise exception 'Venue ID and club ID are required.';
  end if;

  if nullif(btrim(p_name), '') is null then
    raise exception 'Venue name is required.';
  end if;

  if (p_latitude is null) <> (p_longitude is null) then
    raise exception 'Latitude and longitude must be supplied together.';
  end if;

  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then
    raise exception 'Latitude is outside its valid range.';
  end if;

  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then
    raise exception 'Longitude is outside its valid range.';
  end if;

  select v.is_home_venue
    into v_existing_home
  from public.venues v
  where v.id = p_venue_id
    and v.club_id = p_club_id;

  if not found then
    raise exception 'The venue does not exist for this club.';
  end if;

  select exists (
    select 1
    from public.app_superusers s
    where s.user_id = auth.uid()
  )
  into v_is_superuser;

  if not v_is_superuser then
    v_member_profile_id := public.my_member_profile_id();

    select exists (
      select 1
      from public.club_memberships cm
      where cm.club_id = p_club_id
        and cm.member_profile_id = v_member_profile_id
        and cm.role = 'admin'::public.club_role
        and cm.is_active = true
    )
    into v_is_club_admin;
  end if;

  if not (v_is_superuser or v_is_club_admin) then
    raise exception 'You are not authorised to update venues for this club.' using errcode='42501';
  end if;

  -- Keep the existing home-venue authority rule: club admins may maintain an
  -- existing home venue, but only a superuser may change home/non-home status.
  if p_is_home_venue is distinct from v_existing_home and not v_is_superuser then
    raise exception 'Only a superuser may change home venue status.';
  end if;

  if p_is_home_venue and v_is_superuser then
    update public.venues
       set is_home_venue = false
     where club_id = p_club_id
       and id <> p_venue_id
       and is_home_venue = true;
  end if;

  update public.venues
     set name = btrim(p_name),
         is_home_venue = p_is_home_venue,
         town_city = nullif(btrim(p_town_city), ''),
         postcode = nullif(upper(btrim(p_postcode)), ''),
         contact_name = nullif(btrim(p_contact_name), ''),
         contact_phone = nullif(btrim(p_contact_phone), ''),
         contact_email = nullif(btrim(p_contact_email), ''),
         address_line1 = nullif(btrim(p_address_line1), ''),
         address_line2 = nullif(btrim(p_address_line2), ''),
         directions_url = nullif(btrim(p_directions_url), ''),
         website_url = nullif(btrim(p_website_url), ''),
         google_maps_url = nullif(btrim(p_google_maps_url), ''),
         google_place_id = nullif(btrim(p_google_place_id), ''),
         latitude = p_latitude,
         longitude = p_longitude,
         club_officers = case
           when p_is_home_venue then coalesce(p_club_officers, '{}'::jsonb)
           else '{}'::jsonb
         end
   where id = p_venue_id
     and club_id = p_club_id;

  if not found then
    raise exception 'The venue could not be updated.';
  end if;

  return p_venue_id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."update_club_venue_full"(p_venue_id uuid, p_club_id uuid, p_name text, p_is_home_venue boolean, p_town_city text, p_postcode text, p_contact_name text, p_contact_phone text, p_contact_email text, p_address_line1 text, p_address_line2 text, p_directions_url text, p_website_url text, p_google_maps_url text, p_google_place_id text, p_latitude double precision, p_longitude double precision, p_club_officers jsonb) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."update_club_venue_full"(p_venue_id uuid, p_club_id uuid, p_name text, p_is_home_venue boolean, p_town_city text, p_postcode text, p_contact_name text, p_contact_phone text, p_contact_email text, p_address_line1 text, p_address_line2 text, p_directions_url text, p_website_url text, p_google_maps_url text, p_google_place_id text, p_latitude double precision, p_longitude double precision, p_club_officers jsonb) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."update_club_venue_full"(p_venue_id uuid, p_club_id uuid, p_name text, p_is_home_venue boolean, p_town_city text, p_postcode text, p_contact_name text, p_contact_phone text, p_contact_email text, p_address_line1 text, p_address_line2 text, p_directions_url text, p_website_url text, p_google_maps_url text, p_google_place_id text, p_latitude double precision, p_longitude double precision, p_club_officers jsonb) TO "service_role";

CREATE OR REPLACE FUNCTION public.validate_fixture_links()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v record;
  ga record;
  v_uses_rinks boolean := true;
begin
  select coalesce(ct.uses_rinks, true)
    into v_uses_rinks
  from public.competition_types ct
  where ct.id = new.competition_type_id;

  -- Venue must exist and belong to the same club as the fixture record
  select * into v from public.venues where id = new.venue_id;
  if v is null then
    raise exception 'Invalid venue_id';
  end if;

  if v.club_id <> new.club_id then
    raise exception 'Venue does not belong to club';
  end if;

  if new.opponent_venue_id is not null and not exists (
    select 1 from public.venues opponent
    where opponent.id = new.opponent_venue_id
      and opponent.club_id = new.club_id
  ) then
    raise exception 'Opponent venue does not belong to club' using errcode = '23514';
  end if;

  if v_uses_rinks then
    -- HOME rink-using fixture: green_area is required and must match venue/club
    if new.is_home then
      if new.green_area_id is null then
        raise exception 'green_area_id is required for home fixtures that use rinks';
      end if;

      select * into ga from public.green_areas where id = new.green_area_id;
      if ga is null then
        raise exception 'Invalid green_area_id';
      end if;

      if ga.venue_id <> new.venue_id then
        raise exception 'Green area does not belong to venue';
      end if;

      if ga.club_id <> new.club_id then
        raise exception 'Green area does not belong to club';
      end if;

      if ga.discipline = 'outdoor' then
        if ga.orientation_mode = 'required' and new.orientation is null then
          raise exception 'Orientation is required for this outdoor green';
        end if;

        if ga.orientation_mode <> 'not_applicable'
           and array_length(ga.allowed_orientations, 1) > 0
           and new.orientation is not null
           and not (new.orientation = any (ga.allowed_orientations)) then
          raise exception 'Orientation not allowed for this green area';
        end if;
      else
        if new.orientation is not null then
          raise exception 'Orientation must be null for indoor green';
        end if;
      end if;

    else
      -- AWAY rink-using fixture: green_area and orientation should be NULL
      if new.green_area_id is not null then
        raise exception 'green_area_id must be null for away fixtures';
      end if;

      if new.orientation is not null then
        raise exception 'orientation must be null for away fixtures';
      end if;
    end if;

  else
    -- Non-rink event/meeting/party: no green/orientation allowed
    if new.green_area_id is not null then
      raise exception 'green_area_id must be null for fixtures that do not use rinks';
    end if;

    if new.orientation is not null then
      raise exception 'orientation must be null for fixtures that do not use rinks';
    end if;
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."validate_fixture_links"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_links"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_links"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_links"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_links"() TO "service_role";

CREATE OR REPLACE FUNCTION public.validate_fixture_rink()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
  if new.format = 'pairs' and new.players_per_rink <> 2 then
    raise exception 'pairs must have players_per_rink=2';
  end if;
  if new.format = 'triples' and new.players_per_rink <> 3 then
    raise exception 'triples must have players_per_rink=3';
  end if;
  if new.format = 'rinks' and new.players_per_rink <> 4 then
    raise exception 'rinks must have players_per_rink=4';
  end if;
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."validate_fixture_rink"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink"() TO "service_role";

CREATE OR REPLACE FUNCTION public.validate_fixture_rink_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_players_per_rink integer;
  v_selection_mode text;
  v_is_internal boolean;
begin
  -- Get players_per_rink from the linked fixture_rink
  select fr.players_per_rink
    into v_players_per_rink
  from public.fixture_rinks fr
  where fr.id = new.fixture_rink_id;

  if v_players_per_rink is null then
    raise exception 'fixture_rink % not found or has no players_per_rink', new.fixture_rink_id;
  end if;

  -- Get fixture type mode from the fixture
  select
    lower(coalesce(ct.selection_mode, '')),
    coalesce(ct.is_internal, false)
    into v_selection_mode, v_is_internal
  from public.fixtures f
  left join public.competition_types ct
    on ct.id = f.competition_type_id
  where f.id = new.fixture_id;

  -- Internal + Pre-Select:
  -- players:   1..players_per_rink
  -- opponents: 101..100+players_per_rink
  -- marker:    201 (optional)
  if v_is_internal and v_selection_mode = 'preselect' then
    if not (
      (new.position between 1 and v_players_per_rink)
      or
      (new.position between 101 and 100 + v_players_per_rink)
      or
      (new.position = 201)
    ) then
      raise exception
        'position % invalid for players_per_rink %',
        new.position, v_players_per_rink;
    end if;

  else
    -- Standard fixtures: only normal positions
    if not (new.position between 1 and v_players_per_rink) then
      raise exception
        'position % invalid for players_per_rink %',
        new.position, v_players_per_rink;
    end if;
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."validate_fixture_rink_assignment"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink_assignment"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink_assignment"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink_assignment"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."validate_fixture_rink_assignment"() TO "service_role";

CREATE OR REPLACE FUNCTION public.validate_green_rink_maintenance()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_green public.green_areas%rowtype;
begin
  select *
  into v_green
  from public.green_areas
  where id = new.green_area_id;

  if not found then
    raise exception 'Green area was not found.';
  end if;

  new.club_id := v_green.club_id;

  if new.rink_number < 1 or new.rink_number > v_green.rink_count then
    raise exception 'Rink number % is not valid for this green.', new.rink_number;
  end if;

  if new.end_at <= new.start_at then
    raise exception 'Maintenance end time must be after the start time.';
  end if;

  if new.status = 'active' and exists (
    select 1
    from public.green_rink_maintenance m
    where m.green_area_id = new.green_area_id
      and m.rink_number = new.rink_number
      and m.status = 'active'
      and m.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and m.time_range && tstzrange(new.start_at, new.end_at, '[)')
  ) then
    raise exception 'This rink already has maintenance during part of the selected period.';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."validate_green_rink_maintenance"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."validate_green_rink_maintenance"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."validate_green_rink_maintenance"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."validate_green_rink_maintenance"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."validate_green_rink_maintenance"() TO "service_role";

CREATE OR REPLACE FUNCTION public.validate_mailing_list_member_club()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_club_id uuid;
begin
  select ml.club_id
  into v_club_id
  from public.mailing_lists ml
  where ml.id = new.mailing_list_id;

  if v_club_id is null then
    raise exception 'Mailing list not found.';
  end if;

  if not exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = v_club_id
      and cm.member_profile_id = new.member_profile_id
      and cm.is_active = true
  ) then
    raise exception 'The member does not have an active membership of this club.';
  end if;

  if new.is_active then
    new.removed_at := null;
  elsif new.removed_at is null then
    new.removed_at := now();
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."validate_mailing_list_member_club"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."validate_mailing_list_member_club"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."validate_mailing_list_member_club"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."validate_mailing_list_member_club"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."validate_mailing_list_member_club"() TO "service_role";

CREATE OR REPLACE FUNCTION public.validate_required_team_sheet_email_attachment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
  ) AND NOT (NEW.event_type = 'fixture_message' AND
    (coalesce(NEW.payload->>'team_sheet_required', 'false') = 'true' OR jsonb_array_length(coalesce(NEW.attachments, '[]'::jsonb)) > 0)) THEN
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
     OR v_attachment->>'contentType' IS DISTINCT FROM 'application/pdf'
     OR NULLIF(BTRIM(v_attachment->>'contentBytes'), '') IS NULL
     OR NOT (v_attachment ? 'compositionVersion')
     OR (v_attachment->>'compositionVersion')::integer IS DISTINCT FROM v_current_version THEN
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

REVOKE ALL ON FUNCTION "public"."validate_required_team_sheet_email_attachment"() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.validate_team_club_links()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if TG_OP='UPDATE' then
  if new.id is distinct from old.id or new.club_id is distinct from old.club_id then
   raise exception 'A team cannot be moved to a different club or identity' using errcode='23514';
  end if;
  if new.captain_member_profile_id is not distinct from old.captain_member_profile_id
   and new.vice_captain_member_profile_id is not distinct from old.vice_captain_member_profile_id
   and new.manager_member_profile_id is not distinct from old.manager_member_profile_id then
   return new;
  end if;
 end if;
 if exists(select 1 from unnest(array[new.captain_member_profile_id,
   new.vice_captain_member_profile_id,new.manager_member_profile_id]) as leader(id)
   where leader.id is not null and not exists(select 1 from public.club_memberships cm
    where cm.club_id=new.club_id and cm.member_profile_id=leader.id and cm.is_active
    and cm.role::text<>'guest')) then
  raise exception 'Team officials must be active non-guest members of this club' using errcode='23514';
 end if;
 return new;
end $function$;

REVOKE ALL ON FUNCTION "public"."validate_team_club_links"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."validate_team_club_links"() TO "service_role";

CREATE OR REPLACE FUNCTION public.validate_volunteer_task_mailing_list()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_list_club_id uuid;
begin
  select ml.club_id
  into v_list_club_id
  from public.mailing_lists ml
  where ml.id = new.mailing_list_id;

  if v_list_club_id is null then
    raise exception 'Mailing list not found.';
  end if;

  if v_list_club_id <> new.club_id then
    raise exception 'The volunteer task and mailing list must belong to the same club.';
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."validate_volunteer_task_mailing_list"() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION "public"."validate_volunteer_task_mailing_list"() TO PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."validate_volunteer_task_mailing_list"() TO "anon";

GRANT EXECUTE ON FUNCTION "public"."validate_volunteer_task_mailing_list"() TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."validate_volunteer_task_mailing_list"() TO "service_role";

DROP POLICY "club_memberships select self or admin" ON "public"."club_memberships";

CREATE POLICY "club_memberships select self or admin" ON "public"."club_memberships" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)));

DROP POLICY "memberships visible to self" ON "public"."club_memberships";

CREATE POLICY "memberships visible to self" ON "public"."club_memberships" AS PERMISSIVE FOR SELECT TO PUBLIC USING ((member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)));

DROP POLICY "club members can read profiles in their club" ON "public"."member_profiles";

CREATE POLICY "club members can read profiles in their club" ON "public"."member_profiles" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((id IN ( SELECT cm.member_profile_id
   FROM club_memberships cm
  WHERE (cm.is_active AND (cm.club_id IN ( SELECT my_active_club_ids() AS my_active_club_ids))))));

DROP POLICY "member_profiles select (self or same club)" ON "public"."member_profiles";

CREATE POLICY "member_profiles select (self or same club)" ON "public"."member_profiles" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((user_id = ( SELECT auth.uid() AS uid)));

DROP POLICY "member_profiles select self or club admin" ON "public"."member_profiles";

CREATE POLICY "member_profiles select self or club admin" ON "public"."member_profiles" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((id = ( SELECT my_member_profile_id() AS my_member_profile_id)) OR (id IN ( SELECT cm.member_profile_id
   FROM club_memberships cm
  WHERE (cm.club_id IN ( SELECT mine.club_id
           FROM club_memberships mine
          WHERE ((mine.member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)) AND mine.is_active AND (mine.role = 'admin'::club_role))))))));

DROP POLICY "read own profile" ON "public"."member_profiles";

CREATE POLICY "read own profile" ON "public"."member_profiles" AS PERMISSIVE FOR SELECT TO PUBLIC USING ((user_id = ( SELECT auth.uid() AS uid)));

DROP POLICY "team_members_insert_managers" ON "public"."team_members";

CREATE POLICY "team_members_insert_managers" ON "public"."team_members" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (((EXISTS ( SELECT 1
   FROM ((teams t
     JOIN club_memberships cm ON ((cm.club_id = t.club_id)))
     JOIN member_profiles mp ON ((mp.id = cm.member_profile_id)))
  WHERE ((t.id = team_members.team_id) AND (mp.user_id = auth.uid()) AND (cm.is_active = true) AND ((cm.role)::text = ANY (ARRAY['admin'::text, 'selector'::text]))))) OR (EXISTS ( SELECT 1
   FROM (teams t
     JOIN member_profiles mp ON (((mp.id = t.captain_member_profile_id) OR (mp.id = t.vice_captain_member_profile_id) OR (mp.id = t.manager_member_profile_id))))
  WHERE ((t.id = team_members.team_id) AND (mp.user_id = auth.uid()))))));

DROP POLICY "team_members_update_managers" ON "public"."team_members";

CREATE POLICY "team_members_update_managers" ON "public"."team_members" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM ((teams t
     JOIN club_memberships cm ON ((cm.club_id = t.club_id)))
     JOIN member_profiles mp ON ((mp.id = cm.member_profile_id)))
  WHERE ((t.id = team_members.team_id) AND (mp.user_id = auth.uid()) AND (cm.is_active = true) AND ((cm.role)::text = ANY (ARRAY['admin'::text, 'selector'::text]))))) OR (EXISTS ( SELECT 1
   FROM (teams t
     JOIN member_profiles mp ON (((mp.id = t.captain_member_profile_id) OR (mp.id = t.vice_captain_member_profile_id) OR (mp.id = t.manager_member_profile_id))))
  WHERE ((t.id = team_members.team_id) AND (mp.user_id = auth.uid())))))) WITH CHECK (((EXISTS ( SELECT 1
   FROM ((teams t
     JOIN club_memberships cm ON ((cm.club_id = t.club_id)))
     JOIN member_profiles mp ON ((mp.id = cm.member_profile_id)))
  WHERE ((t.id = team_members.team_id) AND (mp.user_id = auth.uid()) AND (cm.is_active = true) AND ((cm.role)::text = ANY (ARRAY['admin'::text, 'selector'::text]))))) OR (EXISTS ( SELECT 1
   FROM (teams t
     JOIN member_profiles mp ON (((mp.id = t.captain_member_profile_id) OR (mp.id = t.vice_captain_member_profile_id) OR (mp.id = t.manager_member_profile_id))))
  WHERE ((t.id = team_members.team_id) AND (mp.user_id = auth.uid()))))));

CREATE POLICY "notifications_recipient_read" ON "public"."app_notifications" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)));

CREATE POLICY "notifications_recipient_read_state" ON "public"."app_notifications" AS PERMISSIVE FOR UPDATE TO "authenticated" USING ((member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id))) WITH CHECK ((member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)));

CREATE POLICY "superuser_read" ON "public"."audit_journal" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM app_superusers s
  WHERE (s.user_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "schedule_read_active_club" ON "public"."club_schedule_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((club_id IN ( SELECT my_active_club_ids() AS my_active_club_ids)));

CREATE POLICY "email_queue_superuser_read" ON "public"."email_queue" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT is_app_superuser() AS is_app_superuser));

CREATE POLICY "notification_queue_authorized_insert" ON "public"."notification_queue" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (notification_security.can_enqueue(notification_queue.*));

CREATE POLICY "teams_create_club" ON "public"."teams" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM club_memberships cm
  WHERE ((cm.club_id = teams.club_id) AND (cm.member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)) AND cm.is_active AND ((cm.role)::text = ANY (ARRAY['admin'::text, 'selector'::text]))))));

CREATE POLICY "teams_edit_club" ON "public"."teams" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (((club_id IN ( SELECT my_active_club_ids() AS my_active_club_ids)) AND ((((( SELECT my_member_profile_id() AS my_member_profile_id) = captain_member_profile_id) OR (( SELECT my_member_profile_id() AS my_member_profile_id) = vice_captain_member_profile_id)) OR (( SELECT my_member_profile_id() AS my_member_profile_id) = manager_member_profile_id)) OR (EXISTS ( SELECT 1
   FROM club_memberships cm
  WHERE ((cm.club_id = teams.club_id) AND (cm.member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)) AND cm.is_active AND ((cm.role)::text = ANY (ARRAY['admin'::text, 'selector'::text])))))))) WITH CHECK ((club_id IN ( SELECT my_active_club_ids() AS my_active_club_ids)));

CREATE POLICY "teams_read_club" ON "public"."teams" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((club_id IN ( SELECT my_active_club_ids() AS my_active_club_ids)));

CREATE POLICY "dashboard_filters_owner" ON "public"."user_club_dashboard_filters" AS PERMISSIVE FOR ALL TO "authenticated" USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "push_tokens_owner" ON "public"."user_push_tokens" AS PERMISSIVE FOR ALL TO "authenticated" USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ((member_profile_id IS NULL) OR (member_profile_id = ( SELECT my_member_profile_id() AS my_member_profile_id)))));

CREATE POLICY "venue_master_shared_read" ON "public"."venue_master" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((( SELECT auth.uid() AS uid) IS NOT NULL));

CREATE POLICY "venue_master_superuser_delete" ON "public"."venue_master" AS PERMISSIVE FOR DELETE TO "authenticated" USING (( SELECT is_app_superuser() AS is_app_superuser));

CREATE POLICY "venue_master_superuser_insert" ON "public"."venue_master" AS PERMISSIVE FOR INSERT TO "authenticated" WITH CHECK (( SELECT is_app_superuser() AS is_app_superuser));

CREATE POLICY "venue_master_superuser_update" ON "public"."venue_master" AS PERMISSIVE FOR UPDATE TO "authenticated" USING (( SELECT is_app_superuser() AS is_app_superuser)) WITH CHECK (( SELECT is_app_superuser() AS is_app_superuser));

CREATE POLICY "venues_superuser_read" ON "public"."venues" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT is_app_superuser() AS is_app_superuser));

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON app_superusers FOR EACH ROW EXECUTE FUNCTION audit_private.capture('user_id');

CREATE TRIGGER immutable_audit BEFORE DELETE OR UPDATE OR TRUNCATE ON audit_journal FOR EACH STATEMENT EXECUTE FUNCTION audit_private.immutable();

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON club_memberships FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,club_id,member_profile_id,role,is_active,is_coach');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON club_schedule_items FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,club_id,title,item_type,start_at,end_at,status,linked_fixture_id');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON clubs FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,name,primary_color_hex,secondary_color_hex');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON email_queue FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,fixture_id,member_profile_id,event_type,status,sent_at');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON feature_revision_policy FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,enabled_revision');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON fixture_rink_assignments FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,fixture_id,fixture_rink_id,member_profile_id,position,display_name');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON fixture_rsvps FOR EACH ROW EXECUTE FUNCTION audit_private.capture_fixture_rsvp();

CREATE TRIGGER a_set_fixture_creator BEFORE INSERT OR UPDATE ON fixtures FOR EACH ROW EXECUTE FUNCTION audit_private.set_fixture_creator();

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON fixtures FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,club_id,team_id,team_name,start_at,end_at,venue_id,opponent_venue_id,opponent_name,is_home,section,rinks_required,players_per_rink,competition_type_id,captain_member_profile_id,vice_captain_member_profile_id,cancelled_at,cancellation_reason,rescheduled_at,rescheduled_to_fixture_id,rescheduled_from_fixture_id,archived_at,archive_reason');

CREATE TRIGGER prevent_app_fixture_delete BEFORE DELETE ON fixtures FOR EACH ROW EXECUTE FUNCTION audit_private.guard_fixture_delete();

CREATE TRIGGER validate_archived_fixture BEFORE INSERT OR UPDATE ON fixtures FOR EACH ROW EXECUTE FUNCTION audit_private.guard_archived_fixture();

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON member_invitation_attempts FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,club_id,membership_id,user_id,status,template_version');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON member_profiles FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,user_id,first_name,last_name,title,email_address,phone,gender,sex_at_birth,outdoor_club');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON team_members FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,team_id,member_profile_id,is_active');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON team_selection_members FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,team_selection_id,member_profile_id,is_selected,role,acceptance');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON team_selections FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,fixture_id,status,published_at,captain_member_profile_id,vice_captain_member_profile_id');

CREATE TRIGGER durable_audit BEFORE INSERT OR DELETE OR UPDATE ON teams FOR EACH ROW EXECUTE FUNCTION audit_private.capture('id,club_id,name,description,is_active,captain_member_profile_id,vice_captain_member_profile_id,manager_member_profile_id,section');

CREATE TRIGGER validate_team_club_links BEFORE INSERT OR UPDATE ON teams FOR EACH ROW EXECUTE FUNCTION validate_team_club_links();

ALTER TABLE "audit_private"."import_runs" DISABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "audit_private"."import_runs" FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE "public"."audit_journal" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."audit_journal" FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE "public"."audit_journal" TO "authenticated";

ALTER TABLE "public"."email_written_replies" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."email_written_replies" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."email_written_replies" TO "service_role";

GRANT SELECT ON TABLE "public"."email_written_replies" TO "service_role";

GRANT UPDATE ON TABLE "public"."email_written_replies" TO "service_role";

GRANT DELETE ON TABLE "public"."email_written_replies" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."email_written_replies" TO "service_role";

GRANT REFERENCES ON TABLE "public"."email_written_replies" TO "service_role";

GRANT TRIGGER ON TABLE "public"."email_written_replies" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."email_written_replies" TO "service_role";

ALTER TABLE "public"."email_written_reply_reminders" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."email_written_reply_reminders" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."email_written_reply_reminders" TO "service_role";

GRANT SELECT ON TABLE "public"."email_written_reply_reminders" TO "service_role";

GRANT UPDATE ON TABLE "public"."email_written_reply_reminders" TO "service_role";

GRANT DELETE ON TABLE "public"."email_written_reply_reminders" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."email_written_reply_reminders" TO "service_role";

GRANT REFERENCES ON TABLE "public"."email_written_reply_reminders" TO "service_role";

GRANT TRIGGER ON TABLE "public"."email_written_reply_reminders" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."email_written_reply_reminders" TO "service_role";

ALTER TABLE "public"."email_written_reply_settings" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."email_written_reply_settings" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."email_written_reply_settings" TO "service_role";

GRANT SELECT ON TABLE "public"."email_written_reply_settings" TO "service_role";

GRANT UPDATE ON TABLE "public"."email_written_reply_settings" TO "service_role";

GRANT DELETE ON TABLE "public"."email_written_reply_settings" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."email_written_reply_settings" TO "service_role";

GRANT REFERENCES ON TABLE "public"."email_written_reply_settings" TO "service_role";

GRANT TRIGGER ON TABLE "public"."email_written_reply_settings" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."email_written_reply_settings" TO "service_role";

ALTER TABLE "public"."app_notifications" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."app_notifications" TO "service_role";

GRANT SELECT ON TABLE "public"."app_notifications" TO "service_role";

GRANT UPDATE ON TABLE "public"."app_notifications" TO "service_role";

GRANT DELETE ON TABLE "public"."app_notifications" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."app_notifications" TO "service_role";

GRANT REFERENCES ON TABLE "public"."app_notifications" TO "service_role";

GRANT TRIGGER ON TABLE "public"."app_notifications" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."app_notifications" TO "service_role";

GRANT SELECT ON TABLE "public"."app_notifications" TO "authenticated";

ALTER TABLE "public"."club_invites" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."club_invites" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."club_invites" TO "service_role";

GRANT SELECT ON TABLE "public"."club_invites" TO "service_role";

GRANT UPDATE ON TABLE "public"."club_invites" TO "service_role";

GRANT DELETE ON TABLE "public"."club_invites" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."club_invites" TO "service_role";

GRANT REFERENCES ON TABLE "public"."club_invites" TO "service_role";

GRANT TRIGGER ON TABLE "public"."club_invites" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."club_invites" TO "service_role";

ALTER TABLE "public"."club_schedule_items" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."club_schedule_items" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT SELECT ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT UPDATE ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT DELETE ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT REFERENCES ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT TRIGGER ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."club_schedule_items" TO "service_role";

GRANT SELECT ON TABLE "public"."club_schedule_items" TO "authenticated";

REVOKE ALL ON TABLE "public"."debug_login_users" FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE "public"."debug_login_users" TO "anon";

GRANT MAINTAIN ON TABLE "public"."debug_login_users" TO "anon";

GRANT SELECT ON TABLE "public"."debug_login_users" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."debug_login_users" TO "authenticated";

GRANT INSERT ON TABLE "public"."debug_login_users" TO "service_role";

GRANT SELECT ON TABLE "public"."debug_login_users" TO "service_role";

GRANT UPDATE ON TABLE "public"."debug_login_users" TO "service_role";

GRANT DELETE ON TABLE "public"."debug_login_users" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."debug_login_users" TO "service_role";

GRANT REFERENCES ON TABLE "public"."debug_login_users" TO "service_role";

GRANT TRIGGER ON TABLE "public"."debug_login_users" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."debug_login_users" TO "service_role";

ALTER TABLE "public"."email_queue" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."email_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."email_queue" TO "service_role";

GRANT SELECT ON TABLE "public"."email_queue" TO "service_role";

GRANT UPDATE ON TABLE "public"."email_queue" TO "service_role";

GRANT DELETE ON TABLE "public"."email_queue" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."email_queue" TO "service_role";

GRANT REFERENCES ON TABLE "public"."email_queue" TO "service_role";

GRANT TRIGGER ON TABLE "public"."email_queue" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."email_queue" TO "service_role";

GRANT SELECT ON TABLE "public"."email_queue" TO "authenticated";

ALTER TABLE "public"."fixture_email_log" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."fixture_email_log" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."fixture_email_log" TO "service_role";

GRANT SELECT ON TABLE "public"."fixture_email_log" TO "service_role";

GRANT UPDATE ON TABLE "public"."fixture_email_log" TO "service_role";

GRANT DELETE ON TABLE "public"."fixture_email_log" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."fixture_email_log" TO "service_role";

GRANT REFERENCES ON TABLE "public"."fixture_email_log" TO "service_role";

GRANT TRIGGER ON TABLE "public"."fixture_email_log" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."fixture_email_log" TO "service_role";

ALTER TABLE "public"."fixtures" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."fixtures" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."fixtures" TO "anon";

GRANT SELECT ON TABLE "public"."fixtures" TO "anon";

GRANT UPDATE ON TABLE "public"."fixtures" TO "anon";

GRANT TRUNCATE ON TABLE "public"."fixtures" TO "anon";

GRANT REFERENCES ON TABLE "public"."fixtures" TO "anon";

GRANT TRIGGER ON TABLE "public"."fixtures" TO "anon";

GRANT MAINTAIN ON TABLE "public"."fixtures" TO "anon";

GRANT INSERT ON TABLE "public"."fixtures" TO "authenticated";

GRANT SELECT ON TABLE "public"."fixtures" TO "authenticated";

GRANT UPDATE ON TABLE "public"."fixtures" TO "authenticated";

GRANT TRUNCATE ON TABLE "public"."fixtures" TO "authenticated";

GRANT REFERENCES ON TABLE "public"."fixtures" TO "authenticated";

GRANT TRIGGER ON TABLE "public"."fixtures" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."fixtures" TO "authenticated";

GRANT INSERT ON TABLE "public"."fixtures" TO "service_role";

GRANT SELECT ON TABLE "public"."fixtures" TO "service_role";

GRANT UPDATE ON TABLE "public"."fixtures" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."fixtures" TO "service_role";

GRANT REFERENCES ON TABLE "public"."fixtures" TO "service_role";

GRANT TRIGGER ON TABLE "public"."fixtures" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."fixtures" TO "service_role";

REVOKE ALL ON TABLE "public"."marker_volunteer_directory" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."marker_volunteer_directory" TO "service_role";

GRANT SELECT ON TABLE "public"."marker_volunteer_directory" TO "service_role";

GRANT UPDATE ON TABLE "public"."marker_volunteer_directory" TO "service_role";

GRANT DELETE ON TABLE "public"."marker_volunteer_directory" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."marker_volunteer_directory" TO "service_role";

GRANT REFERENCES ON TABLE "public"."marker_volunteer_directory" TO "service_role";

GRANT TRIGGER ON TABLE "public"."marker_volunteer_directory" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."marker_volunteer_directory" TO "service_role";

ALTER TABLE "public"."notification_queue" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."notification_queue" TO "service_role";

GRANT SELECT ON TABLE "public"."notification_queue" TO "service_role";

GRANT UPDATE ON TABLE "public"."notification_queue" TO "service_role";

GRANT DELETE ON TABLE "public"."notification_queue" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."notification_queue" TO "service_role";

GRANT REFERENCES ON TABLE "public"."notification_queue" TO "service_role";

GRANT TRIGGER ON TABLE "public"."notification_queue" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."notification_queue" TO "service_role";

ALTER TABLE "public"."teams" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."teams" TO "anon";

GRANT SELECT ON TABLE "public"."teams" TO "anon";

GRANT UPDATE ON TABLE "public"."teams" TO "anon";

GRANT DELETE ON TABLE "public"."teams" TO "anon";

GRANT MAINTAIN ON TABLE "public"."teams" TO "anon";

GRANT INSERT ON TABLE "public"."teams" TO "authenticated";

GRANT SELECT ON TABLE "public"."teams" TO "authenticated";

GRANT DELETE ON TABLE "public"."teams" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."teams" TO "authenticated";

GRANT INSERT ON TABLE "public"."teams" TO "service_role";

GRANT SELECT ON TABLE "public"."teams" TO "service_role";

GRANT UPDATE ON TABLE "public"."teams" TO "service_role";

GRANT DELETE ON TABLE "public"."teams" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."teams" TO "service_role";

GRANT REFERENCES ON TABLE "public"."teams" TO "service_role";

GRANT TRIGGER ON TABLE "public"."teams" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."teams" TO "service_role";

ALTER TABLE "public"."user_club_dashboard_filters" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."user_club_dashboard_filters" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT SELECT ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT UPDATE ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT DELETE ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT TRUNCATE ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT REFERENCES ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT TRIGGER ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT MAINTAIN ON TABLE "public"."user_club_dashboard_filters" TO "anon";

GRANT INSERT ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT SELECT ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT UPDATE ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT DELETE ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT TRUNCATE ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT REFERENCES ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT TRIGGER ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT MAINTAIN ON TABLE "public"."user_club_dashboard_filters" TO "authenticated";

GRANT INSERT ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

GRANT SELECT ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

GRANT UPDATE ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

GRANT DELETE ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

GRANT REFERENCES ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

GRANT TRIGGER ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."user_club_dashboard_filters" TO "service_role";

ALTER TABLE "public"."user_push_tokens" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."user_push_tokens" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT SELECT ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT UPDATE ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT DELETE ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT REFERENCES ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT TRIGGER ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."user_push_tokens" TO "service_role";

GRANT INSERT ON TABLE "public"."user_push_tokens" TO "authenticated";

GRANT SELECT ON TABLE "public"."user_push_tokens" TO "authenticated";

GRANT UPDATE ON TABLE "public"."user_push_tokens" TO "authenticated";

GRANT DELETE ON TABLE "public"."user_push_tokens" TO "authenticated";

ALTER TABLE "public"."venue_master" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."venue_master" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ON TABLE "public"."venue_master" TO "service_role";

GRANT SELECT ON TABLE "public"."venue_master" TO "service_role";

GRANT UPDATE ON TABLE "public"."venue_master" TO "service_role";

GRANT DELETE ON TABLE "public"."venue_master" TO "service_role";

GRANT TRUNCATE ON TABLE "public"."venue_master" TO "service_role";

GRANT REFERENCES ON TABLE "public"."venue_master" TO "service_role";

GRANT TRIGGER ON TABLE "public"."venue_master" TO "service_role";

GRANT MAINTAIN ON TABLE "public"."venue_master" TO "service_role";

GRANT INSERT ON TABLE "public"."venue_master" TO "authenticated";

GRANT SELECT ON TABLE "public"."venue_master" TO "authenticated";

GRANT UPDATE ON TABLE "public"."venue_master" TO "authenticated";

GRANT DELETE ON TABLE "public"."venue_master" TO "authenticated";

REVOKE ALL ON SEQUENCE public.audit_journal_id_seq FROM PUBLIC, anon, authenticated, service_role;

REVOKE INSERT ("is_read") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("is_read") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("is_read") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("is_read") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("is_read") ON "public"."app_notifications" TO "authenticated";

REVOKE INSERT ("read_at") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("read_at") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("read_at") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("read_at") ON "public"."app_notifications" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("read_at") ON "public"."app_notifications" TO "authenticated";

REVOKE INSERT ("event_type") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("event_type") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("event_type") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("event_type") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ("event_type") ON "public"."notification_queue" TO "authenticated";

REVOKE INSERT ("member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ("member_profile_id") ON "public"."notification_queue" TO "authenticated";

REVOKE INSERT ("target_member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("target_member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("target_member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("target_member_profile_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ("target_member_profile_id") ON "public"."notification_queue" TO "authenticated";

REVOKE INSERT ("fixture_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("fixture_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("fixture_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("fixture_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ("fixture_id") ON "public"."notification_queue" TO "authenticated";

REVOKE INSERT ("team_selection_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("team_selection_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("team_selection_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("team_selection_id") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ("team_selection_id") ON "public"."notification_queue" TO "authenticated";

REVOKE INSERT ("payload") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("payload") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("payload") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("payload") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ("payload") ON "public"."notification_queue" TO "authenticated";

REVOKE INSERT ("status") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("status") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("status") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("status") ON "public"."notification_queue" FROM PUBLIC, anon, authenticated, service_role;

GRANT INSERT ("status") ON "public"."notification_queue" TO "authenticated";

REVOKE INSERT ("name") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("name") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("name") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("name") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("name") ON "public"."teams" TO "authenticated";

REVOKE INSERT ("description") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("description") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("description") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("description") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("description") ON "public"."teams" TO "authenticated";

REVOKE INSERT ("is_active") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("is_active") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("is_active") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("is_active") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("is_active") ON "public"."teams" TO "authenticated";

REVOKE INSERT ("captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("captain_member_profile_id") ON "public"."teams" TO "authenticated";

REVOKE INSERT ("vice_captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("vice_captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("vice_captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("vice_captain_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("vice_captain_member_profile_id") ON "public"."teams" TO "authenticated";

REVOKE INSERT ("manager_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("manager_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("manager_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("manager_member_profile_id") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("manager_member_profile_id") ON "public"."teams" TO "authenticated";

REVOKE INSERT ("section") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE UPDATE ("section") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE SELECT ("section") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

REVOKE REFERENCES ("section") ON "public"."teams" FROM PUBLIC, anon, authenticated, service_role;

GRANT UPDATE ("section") ON "public"."teams" TO "authenticated";

ALTER VIEW "public"."club_diary_view" SET (security_invoker=true);

ALTER VIEW "public"."marker_volunteer_directory" SET (security_invoker=true);

ALTER VIEW "public"."rink_usage_view" SET (security_invoker=true);

ALTER VIEW "public"."venues_with_details" SET (security_invoker=true);

NOTIFY pgrst, 'reload schema';

COMMIT;
