-- Link the trusted admin-created Auth account to the existing profile atomically.
-- User-editable user_metadata is never used to authorise or choose a target.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $body$
declare target_id uuid; actor_id uuid; club uuid;
begin
  if new.raw_app_meta_data ? 'captain_managed_profile_id' then
    target_id := (new.raw_app_meta_data->>'captain_managed_profile_id')::uuid;
    actor_id := (new.raw_app_meta_data->>'enabled_by_admin')::uuid;
    club := (new.raw_app_meta_data->>'enabled_for_club')::uuid;
    if actor_id is null or club is null or target_id is null or
      not (exists(select 1 from public.app_superusers where user_id=actor_id)
        or exists(select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
          where mp.user_id=actor_id and cm.club_id=club and cm.role='admin' and cm.is_active)) then
      raise exception 'An active club administrator must enable app access.' using errcode='42501';
    end if;
    perform 1 from public.member_profiles where id=target_id for update;
    if not exists(select 1 from public.club_memberships where club_id=club and member_profile_id=target_id and is_active) then
      raise exception 'Select an active member of this club.' using errcode='42501';
    end if;
    if nullif(btrim(new.email),'') is null or exists(select 1 from public.member_profiles
      where id<>target_id and lower(email_address)=lower(new.email)) then
      raise exception 'Use a unique email address.' using errcode='23505';
    end if;
    update public.member_profiles set user_id=new.id,email_address=lower(new.email),is_captain_managed=false
      where id=target_id and is_captain_managed and user_id is null;
    if not found then raise exception 'This member already has a login or is no longer captain-managed.'; end if;
    return new;
  end if;
  -- Existing registration behaviour is unchanged.
  insert into public.member_profiles(user_id,display_name)
    values(new.id,coalesce(new.raw_user_meta_data->>'display_name',new.email,'New member'));
  return new;
end;
$body$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
