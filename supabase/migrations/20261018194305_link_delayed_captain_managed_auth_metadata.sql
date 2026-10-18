-- GoTrue can write app_metadata after the initial Auth insert. Link at that
-- point as well; never use user-editable user_metadata as authority.
create function public.link_captain_managed_auth_metadata()
returns trigger language plpgsql security definer set search_path='' as $body$
declare target_id uuid; actor_id uuid; club uuid; placeholder uuid;
 dependency record; referenced boolean;
begin
 if not (new.raw_app_meta_data ? 'captain_managed_profile_id') then return new; end if;
 target_id:=(new.raw_app_meta_data->>'captain_managed_profile_id')::uuid;
 actor_id:=(new.raw_app_meta_data->>'enabled_by_admin')::uuid;
 club:=(new.raw_app_meta_data->>'enabled_for_club')::uuid;
 perform 1 from public.member_profiles where id=target_id for update;
 if exists(select 1 from public.member_profiles where id=target_id and user_id=new.id and not is_captain_managed) then return new; end if;
 if actor_id is null or club is null or target_id is null or not (
   exists(select 1 from public.app_superusers where user_id=actor_id) or
   exists(select 1 from public.club_memberships cm join public.member_profiles p on p.id=cm.member_profile_id
     where p.user_id=actor_id and cm.club_id=club and cm.is_active and cm.role='admin')) then
   raise exception 'An active administrator must enable app access.' using errcode='42501';
 end if;
 if not exists(select 1 from public.member_profiles p join public.club_memberships cm on cm.member_profile_id=p.id
   where p.id=target_id and p.is_captain_managed and p.user_id is null and cm.club_id=club and cm.is_active) then
   raise exception 'The target must be an active captain-managed member.';
 end if;
 if nullif(btrim(new.email),'') is null or exists(select 1 from public.member_profiles where id<>target_id
   and user_id is distinct from new.id and lower(email_address)=lower(new.email)) then
   raise exception 'Use a unique email address.' using errcode='23505';
 end if;
 select id into placeholder from public.member_profiles where user_id=new.id and id<>target_id for update;
 if placeholder is not null then
   -- Only discard the empty Auth-generated placeholder. Guard every declared
   -- reference, including CASCADE/SET NULL foreign keys, before deleting it.
   if exists(select 1 from public.member_profiles where id=placeholder and
     (nullif(btrim(first_name),'') is not null or nullif(btrim(last_name),'') is not null or nullif(btrim(phone),'') is not null)) then
     raise exception 'The new profile contains member details; manual reconciliation is required.';
   end if;
   for dependency in select n.nspname schema_name,c.relname table_name,a.attname column_name,cardinality(k.conkey) key_count
     from pg_catalog.pg_constraint k join pg_catalog.pg_class c on c.oid=k.conrelid
     join pg_catalog.pg_namespace n on n.oid=c.relnamespace
     join pg_catalog.pg_attribute a on a.attrelid=k.conrelid and a.attnum=k.conkey[1]
     where k.confrelid='public.member_profiles'::regclass and k.contype='f'
   loop
     if dependency.key_count<>1 then raise exception 'Profile reference needs manual reconciliation.'; end if;
     execute format('select exists(select 1 from %I.%I where %I=$1)',dependency.schema_name,dependency.table_name,dependency.column_name)
       into referenced using placeholder;
     if referenced then raise exception 'The new profile has history; manual reconciliation is required.'; end if;
   end loop;
   delete from public.member_profiles where id=placeholder;
 end if;
 update public.member_profiles set user_id=new.id,email_address=lower(new.email),is_captain_managed=false
   where id=target_id and is_captain_managed and user_id is null;
 if not found then raise exception 'Member linking changed. Please refresh.'; end if;
 return new;
end;
$body$;
revoke all on function public.link_captain_managed_auth_metadata() from public,anon,authenticated;
create trigger link_captain_managed_after_metadata
 after update of raw_app_meta_data on auth.users
 for each row when (new.raw_app_meta_data ? 'captain_managed_profile_id')
 execute function public.link_captain_managed_auth_metadata();
-- Repair only conversions with trusted metadata and the original unlinked
-- captain-managed target. The trigger refuses to discard any profile history.
do $repair$
declare candidate record;
begin
 for candidate in select u.id from auth.users u join public.member_profiles p
   on p.id=(u.raw_app_meta_data->>'captain_managed_profile_id')::uuid
   where u.raw_app_meta_data ? 'captain_managed_profile_id' and p.is_captain_managed and p.user_id is null
 loop
   update auth.users set raw_app_meta_data=raw_app_meta_data where id=candidate.id;
 end loop;
end;
$repair$;
