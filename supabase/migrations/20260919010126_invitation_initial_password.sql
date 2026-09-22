create schema if not exists invitation_private;
revoke all on schema invitation_private from public, anon, authenticated;
grant usage on schema invitation_private to service_role;

-- Records creation provenance, never a plaintext password or a usable password hash.
create table invitation_private.imported_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  password_fingerprint text not null,
  created_at timestamptz not null default now()
);
alter table invitation_private.imported_accounts enable row level security;
revoke all on invitation_private.imported_accounts from public, anon, authenticated;

-- These narrow, service-only helpers must inspect Auth's private password state.
-- Interactive callers are authorized by the Edge Functions; no user JWT may call them.
create function invitation_private.record_imported_account(p_user uuid, p_club uuid)
returns void language sql security definer set search_path = '' as $$
  insert into invitation_private.imported_accounts(user_id,club_id,password_fingerprint)
    select id,p_club,md5(encrypted_password) from auth.users
    where id=p_user and created_at > now()-interval '2 minutes'
      and last_sign_in_at is null and encrypted_password <> ''
    on conflict(user_id) do nothing;
$$;
create function invitation_private.check_initial_password(p_user uuid,p_club uuid,p_password text)
returns boolean language sql security definer set search_path = '' as $$
  select exists (
    select 1 from invitation_private.imported_accounts i join auth.users u on u.id=i.user_id
    where i.user_id=p_user and i.club_id=p_club and u.last_sign_in_at is null
      and i.password_fingerprint=md5(u.encrypted_password)
      and length(p_password)>0
      and extensions.crypt(p_password,u.encrypted_password)=u.encrypted_password
  );
$$;
revoke all on function invitation_private.record_imported_account(uuid,uuid) from public,anon,authenticated;
revoke all on function invitation_private.check_initial_password(uuid,uuid,text) from public,anon,authenticated;
grant execute on function invitation_private.record_imported_account(uuid,uuid) to service_role;
grant execute on function invitation_private.check_initial_password(uuid,uuid,text) to service_role;

create function public.record_member_import_account(p_user uuid,p_club uuid)
returns void language sql security invoker set search_path = '' as $$
  select invitation_private.record_imported_account(p_user,p_club);
$$;
create function public.check_member_initial_password(p_user uuid,p_club uuid,p_password text)
returns boolean language sql security invoker set search_path = '' as $$
  select invitation_private.check_initial_password(p_user,p_club,p_password);
$$;
revoke all on function public.record_member_import_account(uuid,uuid) from public,anon,authenticated;
revoke all on function public.check_member_initial_password(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.record_member_import_account(uuid,uuid) to service_role;
grant execute on function public.check_member_initial_password(uuid,uuid,text) to service_role;

alter table public.member_invitation_attempts
  add column initial_password_source text,
  add column template_version text not null default 'legacy-v1';
