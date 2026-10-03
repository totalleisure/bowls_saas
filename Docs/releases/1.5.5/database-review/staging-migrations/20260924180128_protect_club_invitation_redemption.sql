-- Legacy token invitations are server-managed; clients redeem through accept_invite.
alter table public.club_invites enable row level security;
revoke all on public.club_invites from public,anon,authenticated;
revoke all on function public.accept_invite(uuid) from public,anon;
grant execute on function public.accept_invite(uuid) to authenticated;
-- Service role retains its existing privileges. No client table policies are needed.

-- Retain the existing email-bound redemption API; fix enum conversion and serialize redemption.
create or replace function public.accept_invite(p_token uuid)
returns boolean language plpgsql security definer set search_path='' as $function$
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
