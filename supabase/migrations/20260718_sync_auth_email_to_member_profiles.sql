-- Make the Supabase Auth email the master login/contact email.
-- Run this once in the Supabase SQL Editor after reviewing it.

create or replace function public.sync_member_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.email is distinct from old.email then
    update public.member_profiles
       set email_address = new.email
     where user_id = new.id;
  end if;

  return new;
end;
$$;

revoke all on function public.sync_member_profile_email_from_auth()
from public, anon, authenticated;

drop trigger if exists sync_member_profile_email_after_auth_change
on auth.users;

create trigger sync_member_profile_email_after_auth_change
after update of email on auth.users
for each row
when (old.email is distinct from new.email)
execute function public.sync_member_profile_email_from_auth();

-- One-time alignment of existing profile emails with their Auth accounts.
update public.member_profiles as mp
   set email_address = au.email
  from auth.users as au
 where mp.user_id = au.id
   and mp.email_address is distinct from au.email;
