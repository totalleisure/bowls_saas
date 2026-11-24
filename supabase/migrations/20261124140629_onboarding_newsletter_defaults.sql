-- Only future onboarding imports opt in. Do not resubscribe existing contacts.
alter table public.club_onboarding_pending_members
  add column newsletter_requested boolean not null default false,
  add column newsletter_enrolled_at timestamptz;
alter table public.club_onboarding_pending_members
  alter column newsletter_requested set default true;

-- Preserve active/non-Guest mailing eligibility, and defer unlinked contacts
-- without creating an Auth account. Once enrolled, honour later opt-outs.
create function club_setup_private.enrol_onboarding_newsletter(p_club uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in
    select c.id, c.member_profile_id, ml.id as list_id
    from public.club_onboarding_pending_members c
    join public.club_memberships cm
      on cm.club_id=c.club_id and cm.member_profile_id=c.member_profile_id
      and cm.is_active and cm.role::text <> 'guest'
    join public.mailing_lists ml on ml.club_id=c.club_id
      and ml.system_key='newsletter_recipients' and ml.is_active
    where c.club_id=p_club and c.newsletter_requested
      and c.newsletter_enrolled_at is null
    for update of c
  loop
    insert into public.mailing_list_members(mailing_list_id,member_profile_id,is_active)
      values(r.list_id,r.member_profile_id,true)
      on conflict(mailing_list_id,member_profile_id) do nothing;
    update public.club_onboarding_pending_members
      set newsletter_enrolled_at=now() where id=r.id;
  end loop;
end $$;
revoke all on function club_setup_private.enrol_onboarding_newsletter(uuid)
  from public,anon,authenticated,service_role;

create function club_setup_private.onboarding_newsletter_changed()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform club_setup_private.enrol_onboarding_newsletter(new.club_id);
  return new;
end $$;
revoke all on function club_setup_private.onboarding_newsletter_changed()
  from public,anon,authenticated,service_role;

create trigger onboarding_contact_newsletter
after insert or update of member_profile_id,newsletter_requested
on public.club_onboarding_pending_members for each row
execute function club_setup_private.onboarding_newsletter_changed();

create trigger onboarding_membership_newsletter
after insert or update of is_active,role
on public.club_memberships for each row
execute function club_setup_private.onboarding_newsletter_changed();

create trigger onboarding_list_newsletter
after insert or update of system_key,is_active
on public.mailing_lists for each row
when (new.system_key='newsletter_recipients')
execute function club_setup_private.onboarding_newsletter_changed();
