-- Include older imported accounts only when the supplied CSV credential is still
-- correct and the member has never signed in. Never reset or return an Auth hash.
create or replace function invitation_private.check_initial_password(p_user uuid,p_club uuid,p_password text)
returns boolean language sql security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u
    join public.member_profiles p on p.user_id=u.id
    join public.club_memberships m on m.member_profile_id=p.id and m.club_id=p_club
    left join invitation_private.imported_accounts i on i.user_id=u.id
    where u.id=p_user and u.last_sign_in_at is null and m.is_active
      and (i.user_id is null or (i.club_id=p_club and i.password_fingerprint=md5(u.encrypted_password)))
      and length(p_password)>0 and u.encrypted_password <> ''
      and extensions.crypt(p_password,u.encrypted_password)=u.encrypted_password
  );
$$;
revoke all on function invitation_private.check_initial_password(uuid,uuid,text) from public,anon,authenticated;
grant execute on function invitation_private.check_initial_password(uuid,uuid,text) to service_role;
