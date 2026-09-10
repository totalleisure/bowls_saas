create or replace function public.enforce_operational_mailing_list_member_eligibility()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
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

revoke all on function public.enforce_operational_mailing_list_member_eligibility()
from public, anon, authenticated;

drop trigger if exists enforce_operational_mailing_list_member_eligibility
on public.mailing_list_members;

create trigger enforce_operational_mailing_list_member_eligibility
before insert or update of mailing_list_id, member_profile_id, is_active
on public.mailing_list_members
for each row
execute function public.enforce_operational_mailing_list_member_eligibility();
