-- Members contacted by telephone have a profile, not an Auth identity.
alter table public.member_profiles add column is_captain_managed boolean not null default false;
alter table public.member_profiles alter column user_id drop not null;
alter table public.member_profiles add constraint member_profile_account_mode check (
  (not is_captain_managed and user_id is not null)
  or (is_captain_managed and user_id is null and email_address is null
      and nullif(btrim(first_name), '') is not null
      and nullif(btrim(last_name), '') is not null
      and length(regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g')) between 7 and 15)
);

create schema if not exists managed_members_private;
revoke all on schema managed_members_private from public, anon, authenticated;
grant usage on schema managed_members_private to authenticated;

create function managed_members_private.create_member(
  p_club_id uuid, p_first_name text, p_last_name text, p_phone text,
  p_sex_at_birth text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_phone text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
begin
  if auth.uid() is null or not (
    public.is_app_superuser() or exists (
      select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
      where cm.club_id=p_club_id and cm.is_active and cm.role='admin' and mp.user_id=auth.uid()
    )
  ) then raise exception 'Only club administrators can add captain-managed members.' using errcode='42501'; end if;
  if nullif(btrim(p_first_name),'') is null or nullif(btrim(p_last_name),'') is null
     or length(v_phone) not between 7 and 15
     or length(p_first_name)>100 or length(p_last_name)>100 or length(p_phone)>40 then
    raise exception 'Enter first name, last name and a valid telephone number.' using errcode='22023';
  end if;
  -- Serialize retries for the same club/person without treating a shared phone as one person.
  perform pg_advisory_xact_lock(hashtextextended(p_club_id::text || lower(btrim(p_first_name)) || ':' || lower(btrim(p_last_name)) || ':' || v_phone,0));
  if exists(select 1 from public.member_profiles mp join public.club_memberships cm on cm.member_profile_id=mp.id
    where cm.club_id=p_club_id and lower(btrim(mp.first_name))=lower(btrim(p_first_name))
      and lower(btrim(mp.last_name))=lower(btrim(p_last_name))
      and regexp_replace(coalesce(mp.phone,''),'[^0-9]','','g')=v_phone) then
    raise exception 'A member with this name and telephone number already exists in this club.' using errcode='23505';
  end if;
  insert into public.member_profiles(user_id,first_name,last_name,display_name,phone,email_address,
    is_captain_managed,sex_at_birth,show_email_in_directory,show_mobile_in_directory)
  values(null,btrim(p_first_name),btrim(p_last_name),btrim(p_first_name)||' '||btrim(p_last_name),
    btrim(p_phone),null,true,p_sex_at_birth,false,true) returning id into v_id;
  insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(p_club_id,v_id,'member',true);
  return v_id;
end $$;
revoke all on function managed_members_private.create_member(uuid,text,text,text,text) from public,anon;
grant execute on function managed_members_private.create_member(uuid,text,text,text,text) to authenticated;

create function public.create_captain_managed_member(p_club_id uuid,p_first_name text,p_last_name text,p_phone text,p_sex_at_birth text default null)
returns uuid language sql security invoker set search_path = '' as $$
  select managed_members_private.create_member(p_club_id,p_first_name,p_last_name,p_phone,p_sex_at_birth);
$$;
revoke all on function public.create_captain_managed_member(uuid,text,text,text,text) from public,anon;
grant execute on function public.create_captain_managed_member(uuid,text,text,text,text) to authenticated;

-- Narrow recipient guards: existing publication and email workers are unchanged.
create function managed_members_private.skip_accountless_recipient()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_recipient uuid;
begin
  if TG_TABLE_NAME='notification_queue' then v_recipient:=new.target_member_profile_id;
  else v_recipient:=new.member_profile_id; end if;
  if exists(select 1 from public.member_profiles where id=v_recipient and is_captain_managed) then
    return null;
  end if;
  return new;
end $$;
revoke all on function managed_members_private.skip_accountless_recipient() from public,anon,authenticated;
create trigger aaa_skip_captain_managed_recipient before insert on public.notification_queue
for each row execute function managed_members_private.skip_accountless_recipient();
create trigger aaa_skip_captain_managed_recipient before insert on public.email_queue
for each row execute function managed_members_private.skip_accountless_recipient();

comment on column public.member_profiles.is_captain_managed is 'Contact by telephone; no Auth account, email, invitations or personal notifications. Captains manage selection and acceptance.';
