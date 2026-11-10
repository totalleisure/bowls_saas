-- LOCAL PGLITE TEST BASELINE ONLY. Never apply to a hosted project.
-- Structural source: staging-recovery/source-schema.json (no customer rows).
-- Historical lifecycle functions: release 1.5.5 bundle and 22 September guard.
-- Deliberately scoped: no outbound workers, credentials, schedules or storage.
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth; CREATE SCHEMA audit_private; CREATE SCHEMA extensions;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,encrypted_password text,last_sign_in_at timestamptz,raw_user_meta_data jsonb);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$ SELECT nullif(current_setting('test.role',true),'') $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('sub',auth.uid(),'role',auth.role()) $$;
GRANT USAGE ON SCHEMA auth TO authenticated,anon,service_role;
SET check_function_bodies=off;
CREATE TYPE public."acceptance_status" AS ENUM ('pending','accepted','declined');
CREATE TYPE public."club_role" AS ENUM ('member','captain','selector','admin','guest');
CREATE TYPE public."discipline" AS ENUM ('indoor','outdoor');
CREATE TYPE public."dress_code" AS ENUM ('whites','greys','blacks','jackets');
CREATE TYPE public."fixture_type" AS ENUM ('friendly','league','cup','competition');
CREATE TYPE public."orientation" AS ENUM ('north_south','east_west');
CREATE TYPE public."orientation_mode" AS ENUM ('not_applicable','required','optional');
CREATE TYPE public."rsvp_status" AS ENUM ('yes','no','maybe');
CREATE TYPE public."section" AS ENUM ('mixed','mens','ladies','open');
CREATE TYPE public."selection_member_role" AS ENUM ('player','reserve','opponent','marker');
CREATE TYPE public."selection_status" AS ENUM ('draft','published');
CREATE TABLE public."app_notifications" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"member_profile_id" uuid NOT NULL,
"type" text NOT NULL,
"title" text NOT NULL,
"body" text NOT NULL,
"data" jsonb DEFAULT '{}'::jsonb NOT NULL,
"is_read" boolean DEFAULT false NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"read_at" timestamp with time zone,
"fixture_id" uuid,
"team_selection_id" uuid);
CREATE TABLE public."app_superusers" ("user_id" uuid NOT NULL);
CREATE TABLE public."app_version_policy" ("platform" text NOT NULL,
"minimum_build" integer NOT NULL,
"latest_build" integer,
"force_update_message" text,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"update_url" text,
"update_message" text);
CREATE TABLE public."club_diary_view" ("source_id" uuid,
"source_kind" text,
"club_id" uuid,
"title" text,
"description" text,
"start_at" timestamp with time zone,
"end_at" timestamp with time zone,
"all_day" boolean,
"is_home" boolean,
"venue_id" uuid,
"green_area_id" uuid,
"item_type" text,
"activity_type" text,
"linked_fixture_id" uuid,
"rinks_required" integer,
"players_per_rink" integer,
"fixture_type" text,
"section" text);
CREATE TABLE public."club_invites" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"email" text NOT NULL,
"first_name" text,
"last_name" text,
"role" text DEFAULT 'member'::text NOT NULL,
"token" uuid DEFAULT gen_random_uuid() NOT NULL,
"created_by" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"used_at" timestamp with time zone,
"used_by" uuid,
"status" text DEFAULT 'pending'::text NOT NULL);
CREATE TABLE public."club_member_volunteer_roles" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"volunteer_role" text NOT NULL,
"is_active" boolean DEFAULT true NOT NULL,
"notes" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."club_memberships" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"role" club_role DEFAULT 'member'::club_role NOT NULL,
"is_active" boolean DEFAULT true NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"is_coach" boolean DEFAULT false NOT NULL,
"coaching_award" text);
CREATE TABLE public."club_schedule_items" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"title" text NOT NULL,
"description" text,
"item_type" text NOT NULL,
"activity_type" text NOT NULL,
"start_at" timestamp with time zone NOT NULL,
"end_at" timestamp with time zone NOT NULL,
"all_day" boolean DEFAULT false NOT NULL,
"is_home" boolean DEFAULT true NOT NULL,
"needs_rinks" boolean DEFAULT false NOT NULL,
"rinks_required" integer,
"needs_selection" boolean DEFAULT false NOT NULL,
"needs_rsvp" boolean DEFAULT false NOT NULL,
"opponent_name" text,
"venue_id" uuid,
"green_area_id" uuid,
"linked_fixture_id" uuid,
"status" text DEFAULT 'draft'::text,
"created_by" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."clubs" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"name" text NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"created_by" uuid,
"primary_color_hex" text,
"secondary_color_hex" text,
"branding_set_no" integer DEFAULT 0 NOT NULL,
"primary_colour" text,
"secondary_colour" text);
CREATE TABLE public."competition_types" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"name" text NOT NULL,
"is_internal" boolean DEFAULT false NOT NULL,
"section" text NOT NULL,
"default_rinks_required" integer,
"default_players_per_rink" integer,
"default_duration_minutes" integer,
"dress_code" text,
"team_selection_enabled" boolean DEFAULT false NOT NULL,
"selection_mode" text,
"colour_scheme_id" uuid,
"is_active" boolean DEFAULT true NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"team_id" uuid,
"tags" text[] DEFAULT '{}'::text[] NOT NULL,
"uses_rinks" boolean DEFAULT true NOT NULL,
"bookable_by_members" boolean DEFAULT false NOT NULL,
"default_format" text);
CREATE TABLE public."debug_login_users" ("member_profile_id" uuid,
"display_name" text,
"email" text,
"sort_order" integer,
"is_enabled" boolean);
CREATE TABLE public."email_action_requests" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"recipient_email" text NOT NULL,
"action_type" text NOT NULL,
"target_record_id" uuid NOT NULL,
"fixture_id" uuid,
"team_selection_id" uuid,
"source_email_queue_id" uuid,
"allowed_actions" text[] NOT NULL,
"response_code_hash" text NOT NULL,
"expires_at" timestamp with time zone,
"status" text DEFAULT 'pending'::text NOT NULL,
"last_action" text,
"last_responded_at" timestamp with time zone,
"last_sender_email" text,
"last_graph_message_id" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"response_token_hash" text,
"response_protocol_version" smallint DEFAULT 1 NOT NULL);
CREATE TABLE public."email_action_response_log" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"request_id" uuid,
"graph_message_id" text NOT NULL,
"sender_email" text,
"command" text,
"result_status" text NOT NULL,
"result_detail" text,
"received_at" timestamp with time zone,
"processed_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."email_inbox_sync_state" ("mailbox" text NOT NULL,
"delta_link" text,
"initialized_at" timestamp with time zone,
"last_checked_at" timestamp with time zone,
"last_success_at" timestamp with time zone,
"last_error" text,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."email_queue" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"member_profile_id" uuid NOT NULL,
"app_notification_id" uuid,
"event_type" text NOT NULL,
"recipient_email" text NOT NULL,
"subject" text NOT NULL,
"body" text NOT NULL,
"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
"status" text DEFAULT 'pending'::text NOT NULL,
"attempts" integer DEFAULT 0 NOT NULL,
"last_error" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"processing_started_at" timestamp with time zone,
"last_attempt_at" timestamp with time zone,
"sent_at" timestamp with time zone,
"locked_at" timestamp with time zone,
"locked_by" text,
"attachments" jsonb,
"fixture_id" uuid,
"team_selection_id" uuid);
CREATE TABLE public."fixture_colour_schemes" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"name" text NOT NULL,
"background_hex" text NOT NULL,
"foreground_hex" text NOT NULL,
"sort_order" integer,
"is_active" boolean DEFAULT true NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."fixture_communication_audit" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_id" uuid NOT NULL,
"club_id" uuid NOT NULL,
"action" text NOT NULL,
"workflow" text,
"changed_by_member_profile_id" uuid,
"result" jsonb DEFAULT '{}'::jsonb NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."fixture_email_log" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_id" uuid,
"member_profile_id" uuid,
"email_address" text,
"email_type" text,
"send_status" text,
"sent_at" timestamp without time zone DEFAULT now(),
"error_message" text,
"provider_response" jsonb,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."fixture_lifecycle_events" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_id" uuid NOT NULL,
"event_type" text NOT NULL,
"old_start_at" timestamp with time zone,
"old_end_at" timestamp with time zone,
"new_start_at" timestamp with time zone,
"new_end_at" timestamp with time zone,
"reason" text,
"created_by_member_profile_id" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."fixture_marker_requests" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_rink_id" uuid NOT NULL,
"status" text DEFAULT 'open'::text NOT NULL,
"requested_by_member_profile_id" uuid,
"requested_at" timestamp with time zone DEFAULT now() NOT NULL,
"fulfilled_by_member_profile_id" uuid,
"fulfilled_at" timestamp with time zone,
"cancelled_by_member_profile_id" uuid,
"cancelled_at" timestamp with time zone,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."fixture_rink_assignments" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_id" uuid NOT NULL,
"fixture_rink_id" uuid NOT NULL,
"member_profile_id" uuid,
"position" integer NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"display_name" text);
CREATE TABLE public."fixture_rinks" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_id" uuid NOT NULL,
"fixture_rink_no" integer NOT NULL,
"format" text NOT NULL,
"players_per_rink" integer NOT NULL,
"home_rink_label" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"marker_required" boolean DEFAULT false NOT NULL);
CREATE TABLE public."fixture_rsvps" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"status" rsvp_status NOT NULL,
"responded_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."fixtures" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"start_at" timestamp with time zone NOT NULL,
"end_at" timestamp with time zone,
"is_home" boolean NOT NULL,
"venue_id" uuid NOT NULL,
"green_area_id" uuid,
"opponent_name" text,
"opponent_contact" text,
"notes" text,
"fixture_type" fixture_type DEFAULT 'friendly'::fixture_type NOT NULL,
"section" section DEFAULT 'mixed'::section NOT NULL,
"dress_code" dress_code[] DEFAULT '{}'::dress_code[] NOT NULL,
"rinks_required" integer NOT NULL,
"players_per_rink" integer NOT NULL,
"orientation" orientation,
"time_range" tstzrange NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"captain_member_profile_id" uuid,
"opponent_venue_id" uuid,
"vice_captain_member_profile_id" uuid,
"team_name" text,
"team_id" uuid,
"requires_rsvp" boolean DEFAULT true NOT NULL,
"last_team_sheet_emailed_at" timestamp with time zone,
"last_team_sheet_email_count" integer,
"last_team_sheet_emailed_by" uuid,
"competition_type_id" uuid,
"cancelled_at" timestamp with time zone,
"cancelled_by_member_profile_id" uuid,
"cancellation_reason" text,
"rescheduled_to_fixture_id" uuid,
"rescheduled_from_fixture_id" uuid,
"rescheduled_at" timestamp with time zone,
"rescheduled_by_member_profile_id" uuid);
CREATE TABLE public."green_areas" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"venue_id" uuid NOT NULL,
"name" text NOT NULL,
"discipline" discipline NOT NULL,
"rink_count" integer NOT NULL,
"scheme_type" text NOT NULL,
"scheme_prefix" text DEFAULT ''::text NOT NULL,
"scheme_padding" integer DEFAULT 0 NOT NULL,
"custom_labels" text[],
"orientation_mode" orientation_mode DEFAULT 'not_applicable'::orientation_mode NOT NULL,
"allowed_orientations" orientation[] DEFAULT '{}'::orientation[] NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"is_outdoor" boolean DEFAULT false NOT NULL,
"uses_sunset_cutoff" boolean DEFAULT false NOT NULL,
"sunset_booking_offset_minutes" integer DEFAULT 30 NOT NULL);
CREATE TABLE public."green_rink_maintenance" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"maintenance_group_id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"green_area_id" uuid NOT NULL,
"rink_number" integer NOT NULL,
"start_at" timestamp with time zone NOT NULL,
"end_at" timestamp with time zone NOT NULL,
"time_range" tstzrange GENERATED ALWAYS AS (tstzrange(start_at, end_at, '[)'::text)) STORED,
"reason" text DEFAULT 'Maintenance'::text NOT NULL,
"notes" text,
"status" text DEFAULT 'active'::text NOT NULL,
"created_by_member_profile_id" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."mailing_list_members" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"mailing_list_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"is_active" boolean DEFAULT true NOT NULL,
"notes" text,
"added_by_member_profile_id" uuid,
"added_at" timestamp with time zone DEFAULT now() NOT NULL,
"removed_at" timestamp with time zone);
CREATE TABLE public."mailing_list_message_recipients" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"mailing_list_message_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"email_address" text,
"app_requested" boolean DEFAULT true NOT NULL,
"email_requested" boolean DEFAULT true NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."mailing_list_messages" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"mailing_list_id" uuid NOT NULL,
"subject" text NOT NULL,
"message_body" text NOT NULL,
"sender_member_profile_id" uuid,
"send_app" boolean DEFAULT true NOT NULL,
"send_email" boolean DEFAULT true NOT NULL,
"recipient_count" integer DEFAULT 0 NOT NULL,
"app_queued_count" integer DEFAULT 0 NOT NULL,
"email_queued_count" integer DEFAULT 0 NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."mailing_lists" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"name" text NOT NULL,
"description" text,
"system_key" text,
"is_active" boolean DEFAULT true NOT NULL,
"created_by_member_profile_id" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"allow_self_subscription" boolean DEFAULT false NOT NULL);
CREATE TABLE public."marker_volunteer_directory" ("volunteer_role_id" uuid,
"club_id" uuid,
"club_name" text,
"member_profile_id" uuid,
"member_name" text,
"first_name" text,
"last_name" text,
"email_address" text,
"is_active" boolean,
"notes" text);
CREATE TABLE public."member_invitation_attempts" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"membership_id" uuid NOT NULL,
"created_by" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"email" text NOT NULL,
"user_id" uuid,
"first_name" text NOT NULL,
"subject" text NOT NULL,
"html" text NOT NULL,
"preview" jsonb NOT NULL,
"guides" jsonb NOT NULL,
"previous_sent_id" uuid,
"status" text DEFAULT 'pending'::text NOT NULL);
CREATE TABLE public."member_invitation_guides" ("club_id" uuid NOT NULL,
"kind" text NOT NULL,
"name" text NOT NULL,
"path" text NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."member_profiles" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"user_id" uuid NOT NULL,
"display_name" text NOT NULL,
"phone" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"first_name" text,
"last_name" text,
"email_address" text,
"address_line1" text,
"address_line2" text,
"town_city" text,
"county" text,
"postcode" text,
"gender" text,
"gender_self_described" text,
"sex_at_birth" text,
"preferred_position" text,
"home_phone" text,
"office_phone" text,
"show_mobile_in_directory" boolean DEFAULT true NOT NULL,
"show_home_phone_in_directory" boolean DEFAULT false NOT NULL,
"show_office_phone_in_directory" boolean DEFAULT false NOT NULL,
"show_email_in_directory" boolean DEFAULT true NOT NULL,
"show_address_in_directory" boolean DEFAULT false NOT NULL,
"title" text,
"outdoor_club" text);
CREATE TABLE public."member_season_admin" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"season_year" integer NOT NULL,
"subscription_fee_due" numeric(10,2),
"subscription_fee_received" numeric(10,2),
"locker_fee_due" numeric(10,2),
"locker_fee_received" numeric(10,2),
"club_induction_completed" boolean DEFAULT false NOT NULL,
"coaching_attended" boolean DEFAULT false NOT NULL,
"signed_off" boolean DEFAULT false NOT NULL,
"signed_off_by_member_profile_id" uuid,
"signed_off_at" timestamp with time zone,
"notes" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."notification_queue" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"event_type" text NOT NULL,
"member_profile_id" uuid,
"target_member_profile_id" uuid,
"fixture_id" uuid,
"team_selection_id" uuid,
"payload" jsonb DEFAULT '{}'::jsonb NOT NULL,
"status" text DEFAULT 'pending'::text NOT NULL,
"attempts" integer DEFAULT 0 NOT NULL,
"last_error" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"processed_at" timestamp with time zone,
"recipient_email" text);
CREATE TABLE public."rink_usage_view" ("source_kind" text,
"club_id" uuid,
"source_id" uuid,
"source_row_id" text,
"start_at" timestamp with time zone,
"end_at" timestamp with time zone,
"green_area_id" uuid,
"rink_label" text,
"is_provisional" boolean,
"title" text,
"fixture_type" text,
"section" text,
"fixture_rink_no" integer,
"players_per_rink" integer);
CREATE TABLE public."team_members" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"team_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"is_active" boolean DEFAULT true NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"created_by" uuid);
CREATE TABLE public."team_selection_acceptance_reminder_log" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"team_selection_member_id" uuid NOT NULL,
"reminder_type" text NOT NULL,
"source" text DEFAULT 'manual'::text NOT NULL,
"sent_by_member_profile_id" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."team_selection_members" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"team_selection_id" uuid NOT NULL,
"member_profile_id" uuid NOT NULL,
"role" selection_member_role DEFAULT 'player'::selection_member_role NOT NULL,
"acceptance" acceptance_status DEFAULT 'pending'::acceptance_status NOT NULL,
"responded_at" timestamp with time zone,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"is_selected" boolean DEFAULT true NOT NULL,
"acceptance_by" uuid);
CREATE TABLE public."team_selections" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"fixture_id" uuid NOT NULL,
"status" selection_status DEFAULT 'draft'::selection_status NOT NULL,
"published_at" timestamp with time zone,
"published_by_member_profile_id" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"captain_member_profile_id" uuid,
"vice_captain_member_profile_id" uuid,
"composition_version" bigint DEFAULT 0 NOT NULL);
CREATE TABLE public."teams" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"name" text NOT NULL,
"description" text,
"is_active" boolean DEFAULT true NOT NULL,
"created_by" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
"captain_member_profile_id" uuid,
"vice_captain_member_profile_id" uuid,
"manager_member_profile_id" uuid,
"section" text);
CREATE TABLE public."user_club_dashboard_filters" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"user_id" uuid NOT NULL,
"club_id" uuid NOT NULL,
"filter_json" jsonb DEFAULT '{}'::jsonb NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."user_push_tokens" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"user_id" uuid NOT NULL,
"member_profile_id" uuid,
"device_token" text NOT NULL,
"platform" text,
"app_build" text,
"is_active" boolean DEFAULT true NOT NULL,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."venue_master" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"name" text NOT NULL,
"contact_name" text,
"contact_phone" text,
"contact_email" text,
"address_line1" text,
"address_line2" text,
"town_city" text,
"postcode" text,
"directions_url" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."venue_places_settings" ("id" boolean DEFAULT true NOT NULL,
"is_enabled" boolean DEFAULT true NOT NULL,
"daily_project_limit" integer DEFAULT 500 NOT NULL,
"daily_club_limit" integer DEFAULT 100 NOT NULL,
"daily_user_limit" integer DEFAULT 50 NOT NULL,
"max_nearby_radius_metres" integer DEFAULT 50000 NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE public."venue_places_usage" ("id" bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
"requested_at" timestamp with time zone DEFAULT now() NOT NULL,
"usage_date" date DEFAULT ((now() AT TIME ZONE 'UTC'::text))::date NOT NULL,
"user_id" uuid NOT NULL,
"club_id" uuid NOT NULL,
"action" text NOT NULL,
"units" integer DEFAULT 1 NOT NULL);
CREATE TABLE public."venues" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"name" text NOT NULL,
"is_home_venue" boolean DEFAULT true NOT NULL,
"contact_name" text,
"contact_phone" text,
"contact_email" text,
"address_line1" text,
"address_line2" text,
"town_city" text,
"postcode" text,
"directions_url" text,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"venue_master_id" uuid,
"club_officers" jsonb DEFAULT '{}'::jsonb NOT NULL,
"latitude" double precision,
"longitude" double precision,
"google_place_id" text,
"website_url" text,
"google_maps_url" text);
CREATE TABLE public."venues_with_details" ("id" uuid,
"club_id" uuid,
"name" text,
"is_home_venue" boolean,
"contact_name" text,
"contact_phone" text,
"contact_email" text,
"address_line1" text,
"address_line2" text,
"town_city" text,
"postcode" text,
"directions_url" text,
"created_at" timestamp with time zone,
"venue_master_id" uuid,
"club_officers" jsonb);
CREATE TABLE public."volunteer_tasks" ("id" uuid DEFAULT gen_random_uuid() NOT NULL,
"club_id" uuid NOT NULL,
"task_code" text NOT NULL,
"name" text NOT NULL,
"description" text,
"mailing_list_id" uuid NOT NULL,
"is_active" boolean DEFAULT true NOT NULL,
"created_by_member_profile_id" uuid,
"created_at" timestamp with time zone DEFAULT now() NOT NULL,
"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.fixtures ADD COLUMN created_by_user_id uuid;
ALTER TABLE public.fixtures ADD COLUMN archived_at timestamptz;
ALTER TABLE public."app_notifications" ADD CONSTRAINT "app_notifications_pkey" PRIMARY KEY (id);
ALTER TABLE public."app_superusers" ADD CONSTRAINT "app_superusers_pkey" PRIMARY KEY (user_id);
ALTER TABLE public."app_version_policy" ADD CONSTRAINT "app_version_policy_latest_build_check" CHECK (latest_build IS NULL OR latest_build >= minimum_build);
ALTER TABLE public."app_version_policy" ADD CONSTRAINT "app_version_policy_minimum_build_check" CHECK (minimum_build >= 0);
ALTER TABLE public."app_version_policy" ADD CONSTRAINT "app_version_policy_pkey" PRIMARY KEY (platform);
ALTER TABLE public."app_version_policy" ADD CONSTRAINT "app_version_policy_platform_check" CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text, 'windows'::text]));
ALTER TABLE public."app_version_policy" ADD CONSTRAINT "app_version_policy_update_url_scheme_check" CHECK (update_url IS NULL OR btrim(update_url) = ''::text OR update_url ~* '^(https|itms-apps)://'::text);
ALTER TABLE public."club_invites" ADD CONSTRAINT "club_invites_pkey" PRIMARY KEY (id);
ALTER TABLE public."club_invites" ADD CONSTRAINT "club_invites_token_key" UNIQUE (token);
ALTER TABLE public."club_member_volunteer_roles" ADD CONSTRAINT "club_member_volunteer_roles_pkey" PRIMARY KEY (id);
ALTER TABLE public."club_member_volunteer_roles" ADD CONSTRAINT "club_member_volunteer_roles_role_check" CHECK (btrim(volunteer_role) <> ''::text);
ALTER TABLE public."club_member_volunteer_roles" ADD CONSTRAINT "club_member_volunteer_roles_unique" UNIQUE (club_id, member_profile_id, volunteer_role);
ALTER TABLE public."club_memberships" ADD CONSTRAINT "club_memberships_club_id_member_profile_id_key" UNIQUE (club_id, member_profile_id);
ALTER TABLE public."club_memberships" ADD CONSTRAINT "club_memberships_pkey" PRIMARY KEY (id);
ALTER TABLE public."club_schedule_items" ADD CONSTRAINT "club_schedule_items_check" CHECK (end_at > start_at);
ALTER TABLE public."club_schedule_items" ADD CONSTRAINT "club_schedule_items_item_type_check" CHECK (item_type = ANY (ARRAY['fixture'::text, 'session'::text, 'event'::text, 'booking'::text, 'block'::text]));
ALTER TABLE public."club_schedule_items" ADD CONSTRAINT "club_schedule_items_pkey" PRIMARY KEY (id);
ALTER TABLE public."clubs" ADD CONSTRAINT "clubs_pkey" PRIMARY KEY (id);
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_default_format_check" CHECK (default_format IS NULL OR (default_format = ANY (ARRAY['singles'::text, 'pairs'::text, 'aussie_pairs'::text, 'triples'::text, 'rinks'::text])));
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_default_players_per_rink_check" CHECK (default_players_per_rink IS NULL OR (default_players_per_rink = ANY (ARRAY[1, 2, 3, 4])));
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_dress_code_chk" CHECK (dress_code IS NULL OR (dress_code = ANY (ARRAY['whites'::text, 'greys'::text, 'club_colours'::text, 'blacks'::text, 'open'::text])));
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_duration_chk" CHECK (default_duration_minutes IS NULL OR default_duration_minutes > 0);
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_pkey" PRIMARY KEY (id);
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_players_chk" CHECK (default_players_per_rink IS NULL OR default_players_per_rink > 0);
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_rinks_chk" CHECK (default_rinks_required IS NULL OR default_rinks_required > 0);
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_section_chk" CHECK (section IS NULL OR (section = ANY (ARRAY['mens'::text, 'ladies'::text, 'mixed'::text, 'open'::text])));
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_selection_consistency_chk" CHECK (team_selection_enabled = false AND selection_mode IS NULL OR team_selection_enabled = true AND selection_mode IS NOT NULL);
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_selection_mode_chk" CHECK (selection_mode IS NULL OR (selection_mode = ANY (ARRAY['rsvp'::text, 'team'::text, 'preselect'::text, 'open'::text])));
ALTER TABLE public."competition_types" ADD CONSTRAINT "competition_types_tags_allowed" CHECK (tags <@ ARRAY['match'::text, 'league'::text, 'competition'::text, 'drive'::text, 'rollup'::text, 'event'::text, 'friendly'::text, 'cup'::text, 'social'::text, 'training'::text, 'meeting'::text]);
ALTER TABLE public."email_action_requests" ADD CONSTRAINT "email_action_requests_action_type_check" CHECK (action_type = ANY (ARRAY['team_selection'::text, 'marker_assignment'::text]));
ALTER TABLE public."email_action_requests" ADD CONSTRAINT "email_action_requests_allowed_actions_check" CHECK (cardinality(allowed_actions) > 0);
ALTER TABLE public."email_action_requests" ADD CONSTRAINT "email_action_requests_pkey" PRIMARY KEY (id);
ALTER TABLE public."email_action_requests" ADD CONSTRAINT "email_action_requests_response_code_hash_key" UNIQUE (response_code_hash);
ALTER TABLE public."email_action_requests" ADD CONSTRAINT "email_action_requests_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'responded'::text, 'expired'::text, 'cancelled'::text]));
ALTER TABLE public."email_action_response_log" ADD CONSTRAINT "email_action_response_log_graph_message_id_key" UNIQUE (graph_message_id);
ALTER TABLE public."email_action_response_log" ADD CONSTRAINT "email_action_response_log_pkey" PRIMARY KEY (id);
ALTER TABLE public."email_inbox_sync_state" ADD CONSTRAINT "email_inbox_sync_state_pkey" PRIMARY KEY (mailbox);
ALTER TABLE public."email_queue" ADD CONSTRAINT "email_queue_pkey" PRIMARY KEY (id);
ALTER TABLE public."email_queue" ADD CONSTRAINT "email_queue_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'cancelled'::text]));
ALTER TABLE public."fixture_colour_schemes" ADD CONSTRAINT "fixture_colour_schemes_bg_hex_chk" CHECK (background_hex ~ '^#[0-9A-Fa-f]{6}$'::text);
ALTER TABLE public."fixture_colour_schemes" ADD CONSTRAINT "fixture_colour_schemes_fg_hex_chk" CHECK (foreground_hex ~ '^#[0-9A-Fa-f]{6}$'::text);
ALTER TABLE public."fixture_colour_schemes" ADD CONSTRAINT "fixture_colour_schemes_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixture_communication_audit" ADD CONSTRAINT "fixture_communication_audit_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixture_email_log" ADD CONSTRAINT "fixture_email_log_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixture_lifecycle_events" ADD CONSTRAINT "fixture_lifecycle_events_event_type_chk" CHECK (event_type = ANY (ARRAY['cancelled'::text, 'rescheduled'::text, 'reinstated'::text]));
ALTER TABLE public."fixture_lifecycle_events" ADD CONSTRAINT "fixture_lifecycle_events_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixture_marker_requests" ADD CONSTRAINT "fixture_marker_requests_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixture_marker_requests" ADD CONSTRAINT "fixture_marker_requests_status_check" CHECK (status = ANY (ARRAY['open'::text, 'fulfilled'::text, 'cancelled'::text]));
ALTER TABLE public."fixture_marker_requests" ADD CONSTRAINT "fixture_marker_requests_status_dates_check" CHECK (status = 'open'::text AND fulfilled_at IS NULL AND cancelled_at IS NULL OR status = 'fulfilled'::text AND fulfilled_by_member_profile_id IS NOT NULL AND fulfilled_at IS NOT NULL AND cancelled_at IS NULL OR status = 'cancelled'::text AND cancelled_at IS NOT NULL AND fulfilled_at IS NULL);
ALTER TABLE public."fixture_rink_assignments" ADD CONSTRAINT "fixture_rink_assignments_fixture_id_member_profile_id_key" UNIQUE (fixture_id, member_profile_id);
ALTER TABLE public."fixture_rink_assignments" ADD CONSTRAINT "fixture_rink_assignments_fixture_rink_id_member_profile_id_key" UNIQUE (fixture_rink_id, member_profile_id);
ALTER TABLE public."fixture_rink_assignments" ADD CONSTRAINT "fixture_rink_assignments_fixture_rink_id_position_key" UNIQUE (fixture_rink_id, "position");
ALTER TABLE public."fixture_rink_assignments" ADD CONSTRAINT "fixture_rink_assignments_identity_check" CHECK (member_profile_id IS NOT NULL AND display_name IS NULL OR member_profile_id IS NULL AND display_name IS NOT NULL AND btrim(display_name) <> ''::text);
ALTER TABLE public."fixture_rink_assignments" ADD CONSTRAINT "fixture_rink_assignments_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixture_rink_assignments" ADD CONSTRAINT "fixture_rink_assignments_rink_position_key" UNIQUE (fixture_rink_id, "position");
ALTER TABLE public."fixture_rinks" ADD CONSTRAINT "fixture_rinks_fixture_id_rink_order_key" UNIQUE (fixture_id, fixture_rink_no);
ALTER TABLE public."fixture_rinks" ADD CONSTRAINT "fixture_rinks_format_check" CHECK (format = ANY (ARRAY['singles'::text, 'pairs'::text, 'aussie_pairs'::text, 'triples'::text, 'fours'::text, 'rinks'::text]));
ALTER TABLE public."fixture_rinks" ADD CONSTRAINT "fixture_rinks_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixture_rinks" ADD CONSTRAINT "fixture_rinks_players_per_rink_check" CHECK (players_per_rink = ANY (ARRAY[1, 2, 3, 4]));
ALTER TABLE public."fixture_rinks" ADD CONSTRAINT "fixture_rinks_rink_order_check" CHECK (fixture_rink_no >= 1);
ALTER TABLE public."fixture_rsvps" ADD CONSTRAINT "fixture_rsvps_fixture_id_member_profile_id_key" UNIQUE (fixture_id, member_profile_id);
ALTER TABLE public."fixture_rsvps" ADD CONSTRAINT "fixture_rsvps_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixtures" ADD CONSTRAINT "fixtures_pkey" PRIMARY KEY (id);
ALTER TABLE public."fixtures" ADD CONSTRAINT "fixtures_players_per_rink_check" CHECK (players_per_rink = ANY (ARRAY[1, 2, 3, 4]));
ALTER TABLE public."fixtures" ADD CONSTRAINT "fixtures_rinks_required_check" CHECK (rinks_required >= 0);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_check" CHECK (scheme_type <> 'alpha'::text OR rink_count <= 26);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_check1" CHECK (scheme_type <> 'custom_list'::text OR custom_labels IS NOT NULL AND array_length(custom_labels, 1) >= rink_count);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_check2" CHECK (discipline <> 'indoor'::discipline OR orientation_mode = 'not_applicable'::orientation_mode);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_check3" CHECK (NOT (discipline = 'outdoor'::discipline AND orientation_mode = 'required'::orientation_mode) OR array_length(allowed_orientations, 1) >= 1);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_pkey" PRIMARY KEY (id);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_rink_count_check" CHECK (rink_count > 0);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_scheme_padding_check" CHECK (scheme_padding >= 0 AND scheme_padding <= 6);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_scheme_type_check" CHECK (scheme_type = ANY (ARRAY['numeric'::text, 'alpha'::text, 'custom_list'::text]));
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_sunset_offset_check" CHECK (sunset_booking_offset_minutes >= 0 AND sunset_booking_offset_minutes <= 180);
ALTER TABLE public."green_areas" ADD CONSTRAINT "green_areas_venue_id_name_key" UNIQUE (venue_id, name);
ALTER TABLE public."green_rink_maintenance" ADD CONSTRAINT "green_rink_maintenance_pkey" PRIMARY KEY (id);
ALTER TABLE public."green_rink_maintenance" ADD CONSTRAINT "green_rink_maintenance_rink_number_check" CHECK (rink_number > 0);
ALTER TABLE public."green_rink_maintenance" ADD CONSTRAINT "green_rink_maintenance_status_check" CHECK (status = ANY (ARRAY['active'::text, 'cancelled'::text]));
ALTER TABLE public."green_rink_maintenance" ADD CONSTRAINT "green_rink_maintenance_valid_time" CHECK (end_at > start_at);
ALTER TABLE public."mailing_list_members" ADD CONSTRAINT "mailing_list_members_pkey" PRIMARY KEY (id);
ALTER TABLE public."mailing_list_members" ADD CONSTRAINT "mailing_list_members_unique" UNIQUE (mailing_list_id, member_profile_id);
ALTER TABLE public."mailing_list_message_recipients" ADD CONSTRAINT "mailing_list_message_recipients_pkey" PRIMARY KEY (id);
ALTER TABLE public."mailing_list_message_recipients" ADD CONSTRAINT "mailing_list_message_recipients_unique" UNIQUE (mailing_list_message_id, member_profile_id);
ALTER TABLE public."mailing_list_messages" ADD CONSTRAINT "mailing_list_messages_body_not_blank" CHECK (btrim(message_body) <> ''::text);
ALTER TABLE public."mailing_list_messages" ADD CONSTRAINT "mailing_list_messages_channel_required" CHECK (send_app OR send_email);
ALTER TABLE public."mailing_list_messages" ADD CONSTRAINT "mailing_list_messages_pkey" PRIMARY KEY (id);
ALTER TABLE public."mailing_list_messages" ADD CONSTRAINT "mailing_list_messages_subject_not_blank" CHECK (btrim(subject) <> ''::text);
ALTER TABLE public."mailing_lists" ADD CONSTRAINT "mailing_lists_club_system_key_unique" UNIQUE (club_id, system_key);
ALTER TABLE public."mailing_lists" ADD CONSTRAINT "mailing_lists_name_not_blank" CHECK (btrim(name) <> ''::text);
ALTER TABLE public."mailing_lists" ADD CONSTRAINT "mailing_lists_pkey" PRIMARY KEY (id);
ALTER TABLE public."mailing_lists" ADD CONSTRAINT "mailing_lists_system_key_format" CHECK (system_key IS NULL OR btrim(system_key) <> ''::text AND system_key = lower(btrim(system_key)));
ALTER TABLE public."member_invitation_attempts" ADD CONSTRAINT "member_invitation_attempts_pkey" PRIMARY KEY (id);
ALTER TABLE public."member_invitation_attempts" ADD CONSTRAINT "member_invitation_attempts_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'sending'::text, 'sent'::text, 'failed'::text, 'unknown'::text, 'superseded'::text]));
ALTER TABLE public."member_invitation_guides" ADD CONSTRAINT "member_invitation_guides_kind_check" CHECK (kind = ANY (ARRAY['introduction'::text, 'android'::text]));
ALTER TABLE public."member_invitation_guides" ADD CONSTRAINT "member_invitation_guides_pkey" PRIMARY KEY (club_id, kind);
ALTER TABLE public."member_profiles" ADD CONSTRAINT "member_profiles_gender_check" CHECK ((gender = ANY (ARRAY['male'::text, 'female'::text, 'non_binary'::text, 'prefer_to_self_describe'::text, 'prefer_not_to_say'::text])) OR gender IS NULL);
ALTER TABLE public."member_profiles" ADD CONSTRAINT "member_profiles_pkey" PRIMARY KEY (id);
ALTER TABLE public."member_profiles" ADD CONSTRAINT "member_profiles_preferred_position_check" CHECK (preferred_position IS NULL OR (preferred_position = ANY (ARRAY['lead'::text, 'third'::text, 'skip'::text])));
ALTER TABLE public."member_profiles" ADD CONSTRAINT "member_profiles_sex_at_birth_check" CHECK ((sex_at_birth = ANY (ARRAY['male'::text, 'female'::text, 'intersex'::text, 'prefer_not_to_say'::text])) OR sex_at_birth IS NULL);
ALTER TABLE public."member_profiles" ADD CONSTRAINT "member_profiles_user_id_key" UNIQUE (user_id);
ALTER TABLE public."member_season_admin" ADD CONSTRAINT "member_season_admin_club_id_member_profile_id_season_year_key" UNIQUE (club_id, member_profile_id, season_year);
ALTER TABLE public."member_season_admin" ADD CONSTRAINT "member_season_admin_pkey" PRIMARY KEY (id);
ALTER TABLE public."notification_queue" ADD CONSTRAINT "notification_queue_pkey" PRIMARY KEY (id);
ALTER TABLE public."team_members" ADD CONSTRAINT "team_members_pkey" PRIMARY KEY (id);
ALTER TABLE public."team_members" ADD CONSTRAINT "team_members_unique_member_per_team" UNIQUE (team_id, member_profile_id);
ALTER TABLE public."team_selection_acceptance_reminder_log" ADD CONSTRAINT "team_selection_acceptance_reminder_log_pkey" PRIMARY KEY (id);
ALTER TABLE public."team_selection_acceptance_reminder_log" ADD CONSTRAINT "team_selection_acceptance_reminder_log_reminder_type_check" CHECK (reminder_type = ANY (ARRAY['manual'::text, '3_day'::text, '1_day'::text]));
ALTER TABLE public."team_selection_acceptance_reminder_log" ADD CONSTRAINT "team_selection_acceptance_reminder_log_source_check" CHECK (source = ANY (ARRAY['manual'::text, 'scheduled'::text]));
ALTER TABLE public."team_selection_members" ADD CONSTRAINT "team_selection_members_pkey" PRIMARY KEY (id);
ALTER TABLE public."team_selection_members" ADD CONSTRAINT "team_selection_members_team_selection_id_member_profile_id_key" UNIQUE (team_selection_id, member_profile_id);
ALTER TABLE public."team_selections" ADD CONSTRAINT "team_selections_fixture_id_key" UNIQUE (fixture_id);
ALTER TABLE public."team_selections" ADD CONSTRAINT "team_selections_pkey" PRIMARY KEY (id);
ALTER TABLE public."teams" ADD CONSTRAINT "teams_pkey" PRIMARY KEY (id);
ALTER TABLE public."teams" ADD CONSTRAINT "teams_section_check" CHECK (section IS NULL OR (section = ANY (ARRAY['mens'::text, 'ladies'::text, 'mixed'::text, 'open'::text])));
ALTER TABLE public."user_club_dashboard_filters" ADD CONSTRAINT "user_club_dashboard_filters_pkey" PRIMARY KEY (id);
ALTER TABLE public."user_club_dashboard_filters" ADD CONSTRAINT "user_club_dashboard_filters_user_id_club_id_key" UNIQUE (user_id, club_id);
ALTER TABLE public."user_push_tokens" ADD CONSTRAINT "user_push_tokens_pkey" PRIMARY KEY (id);
ALTER TABLE public."venue_master" ADD CONSTRAINT "venue_master_pkey" PRIMARY KEY (id);
ALTER TABLE public."venue_places_settings" ADD CONSTRAINT "venue_places_settings_daily_club_limit_check" CHECK (daily_club_limit > 0);
ALTER TABLE public."venue_places_settings" ADD CONSTRAINT "venue_places_settings_daily_project_limit_check" CHECK (daily_project_limit > 0);
ALTER TABLE public."venue_places_settings" ADD CONSTRAINT "venue_places_settings_daily_user_limit_check" CHECK (daily_user_limit > 0);
ALTER TABLE public."venue_places_settings" ADD CONSTRAINT "venue_places_settings_id_check" CHECK (id);
ALTER TABLE public."venue_places_settings" ADD CONSTRAINT "venue_places_settings_max_nearby_radius_metres_check" CHECK (max_nearby_radius_metres >= 1000 AND max_nearby_radius_metres <= 50000);
ALTER TABLE public."venue_places_settings" ADD CONSTRAINT "venue_places_settings_pkey" PRIMARY KEY (id);
ALTER TABLE public."venue_places_usage" ADD CONSTRAINT "venue_places_usage_action_check" CHECK (action = ANY (ARRAY['search'::text, 'details'::text, 'nearby_bowls'::text]));
ALTER TABLE public."venue_places_usage" ADD CONSTRAINT "venue_places_usage_pkey" PRIMARY KEY (id);
ALTER TABLE public."venue_places_usage" ADD CONSTRAINT "venue_places_usage_units_check" CHECK (units >= 1 AND units <= 5);
ALTER TABLE public."venues" ADD CONSTRAINT "venues_club_id_name_key" UNIQUE (club_id, name);
ALTER TABLE public."venues" ADD CONSTRAINT "venues_pkey" PRIMARY KEY (id);
ALTER TABLE public."volunteer_tasks" ADD CONSTRAINT "volunteer_tasks_club_code_unique" UNIQUE (club_id, task_code);
ALTER TABLE public."volunteer_tasks" ADD CONSTRAINT "volunteer_tasks_code_format" CHECK (task_code = lower(btrim(task_code)));
ALTER TABLE public."volunteer_tasks" ADD CONSTRAINT "volunteer_tasks_code_not_blank" CHECK (btrim(task_code) <> ''::text);
ALTER TABLE public."volunteer_tasks" ADD CONSTRAINT "volunteer_tasks_name_not_blank" CHECK (btrim(name) <> ''::text);
ALTER TABLE public."volunteer_tasks" ADD CONSTRAINT "volunteer_tasks_pkey" PRIMARY KEY (id);
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
$function$
;
CREATE OR REPLACE FUNCTION public.my_member_profile_id()
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id
  from public.member_profiles
  where user_id = auth.uid()
  limit 1
$function$
;
CREATE OR REPLACE FUNCTION public.set_fixture_time_range()
 RETURNS trigger
 LANGUAGE plpgsql
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
$function$
;
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
create or replace function audit_private.guard_archived_fixture() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE'
    and old.cancelled_at is null
    and new.cancelled_at is not null
    and length(trim(coalesce(new.cancellation_reason,''))) < 5
  then
    raise exception 'A cancellation reason of at least five characters is required';
  end if;
  return new;
end $$;


CREATE TRIGGER fixtures_set_time_range BEFORE INSERT OR UPDATE ON public.fixtures FOR EACH ROW EXECUTE FUNCTION public.set_fixture_time_range();
CREATE TRIGGER fixtures_creator BEFORE INSERT OR UPDATE ON public.fixtures FOR EACH ROW EXECUTE FUNCTION audit_private.set_fixture_creator();
CREATE TRIGGER fixtures_cancellation_guard BEFORE UPDATE ON public.fixtures FOR EACH ROW EXECUTE FUNCTION audit_private.guard_archived_fixture();
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
SET check_function_bodies=on;
