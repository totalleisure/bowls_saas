-- Require active administrators; retain app-superuser authority.
CREATE OR REPLACE FUNCTION public.team_admin_add_member(p_team_selection_id uuid, p_member_profile_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
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
revoke all on function public.team_admin_add_member(uuid,uuid) from public,anon;
grant execute on function public.team_admin_add_member(uuid,uuid) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.team_admin_set_acceptance(p_team_selection_member_id uuid, p_acceptance text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
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
revoke all on function public.team_admin_set_acceptance(uuid,text) from public,anon;
grant execute on function public.team_admin_set_acceptance(uuid,text) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.update_club_venue_full(p_venue_id uuid, p_club_id uuid, p_name text, p_is_home_venue boolean DEFAULT false, p_town_city text DEFAULT NULL::text, p_postcode text DEFAULT NULL::text, p_contact_name text DEFAULT NULL::text, p_contact_phone text DEFAULT NULL::text, p_contact_email text DEFAULT NULL::text, p_address_line1 text DEFAULT NULL::text, p_address_line2 text DEFAULT NULL::text, p_directions_url text DEFAULT NULL::text, p_website_url text DEFAULT NULL::text, p_google_maps_url text DEFAULT NULL::text, p_google_place_id text DEFAULT NULL::text, p_latitude double precision DEFAULT NULL::double precision, p_longitude double precision DEFAULT NULL::double precision, p_club_officers jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
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
revoke all on function public.update_club_venue_full(uuid,uuid,text,boolean,text,text,text,text,text,text,text,text,text,text,text,double precision,double precision,jsonb) from public,anon;
grant execute on function public.update_club_venue_full(uuid,uuid,text,boolean,text,text,text,text,text,text,text,text,text,text,text,double precision,double precision,jsonb) to authenticated,service_role;
