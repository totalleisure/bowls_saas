-- Auth remains the authority. Only the verified Edge Function's service client
-- may prepare/finalize these operations; browser sessions cannot call them.
create table audit_private.member_email_changes (
 id uuid primary key default gen_random_uuid(),
 club_id uuid not null, member_profile_id uuid not null, user_id uuid not null,
 actor_user_id uuid not null, old_email text not null, new_email text not null,
 status text not null default 'prepared' check(status in ('prepared','succeeded','failed')),
 created_at timestamptz not null default clock_timestamp(), completed_at timestamptz
);
alter table audit_private.member_email_changes enable row level security;
revoke all on audit_private.member_email_changes from public,anon,authenticated;
create unique index member_email_change_pending on audit_private.member_email_changes(member_profile_id) where status='prepared';

create function public.begin_admin_member_email_change(p_actor_user_id uuid,p_club_id uuid,
 p_member_profile_id uuid,p_expected_email text,p_new_email text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare target public.member_profiles; old_email text; new_email text:=lower(btrim(p_new_email));
 super_actor boolean; change_id uuid;
begin
 super_actor:=exists(select 1 from public.app_superusers where user_id=p_actor_user_id);
 if p_actor_user_id is null or not(super_actor or exists(
  select 1 from public.club_memberships cm join public.member_profiles mp on mp.id=cm.member_profile_id
  where mp.user_id=p_actor_user_id and cm.club_id=p_club_id and cm.is_active and cm.role::text='admin'))
 then raise exception 'Active club administrator access required' using errcode='42501';end if;
 select * into target from public.member_profiles where id=p_member_profile_id for update;
 if not found or target.user_id is null then raise exception 'This member has no linked login account' using errcode='22023';end if;
 if not exists(select 1 from public.club_memberships where club_id=p_club_id and member_profile_id=target.id and is_active)
 then raise exception 'Select an active member of this club' using errcode='42501';end if;
 if not super_actor and target.user_id<>p_actor_user_id and (
  exists(select 1 from public.app_superusers where user_id=target.user_id) or
  exists(select 1 from public.club_memberships where member_profile_id=target.id and is_active and role::text='admin' and club_id<>p_club_id))
 then raise exception 'A platform administrator must change this administrator account' using errcode='42501';end if;
 if new_email is null or length(new_email)>254 or new_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 then raise exception 'Enter a valid email address' using errcode='22023';end if;
 select lower(email) into old_email from auth.users where id=target.user_id;
 if old_email is null or old_email is distinct from lower(btrim(p_expected_email))
   or old_email is distinct from lower(target.email_address)
 then raise exception 'The member email has changed. Refresh the record before trying again' using errcode='40001';end if;
 if new_email=old_email then raise exception 'Enter a different email address' using errcode='22023';end if;
 if exists(select 1 from auth.users where lower(email)=new_email and id<>target.user_id)
 or exists(select 1 from public.member_profiles where lower(email_address)=new_email and user_id is distinct from target.user_id)
 then raise exception 'That email address is already used by another account or member' using errcode='23505';end if;
 update audit_private.member_email_changes set status='failed',completed_at=clock_timestamp()
  where member_profile_id=target.id and status='prepared' and created_at<clock_timestamp()-interval '5 minutes';
 if exists(select 1 from audit_private.member_email_changes where member_profile_id=target.id and status='prepared')
 then raise exception 'Another email change is in progress. Refresh before trying again' using errcode='55000';end if;
 insert into audit_private.member_email_changes(club_id,member_profile_id,user_id,actor_user_id,old_email,new_email)
 values(p_club_id,target.id,target.user_id,p_actor_user_id,old_email,new_email) returning id into change_id;
 return jsonb_build_object('change_id',change_id,'user_id',target.user_id,'old_email',old_email,'new_email',new_email);
end $$;

create function public.finish_admin_member_email_change(p_change_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare change audit_private.member_email_changes; verified boolean; actor_name text; member_name text;
begin
 select * into strict change from audit_private.member_email_changes where id=p_change_id for update;
 if change.status<>'prepared' then return jsonb_build_object('changed',change.status='succeeded','email',change.new_email);end if;
 verified:=exists(select 1 from auth.users u join public.member_profiles mp on mp.user_id=u.id
  where u.id=change.user_id and mp.id=change.member_profile_id and lower(u.email)=change.new_email
   and lower(mp.email_address)=change.new_email and u.email_confirmed_at is not null);
 update audit_private.member_email_changes set status=case when verified then 'succeeded' else 'failed' end,
  completed_at=clock_timestamp() where id=change.id;
 select coalesce(nullif(btrim(first_name||' '||last_name),''),display_name,'Club administrator') into actor_name
  from public.member_profiles where user_id=change.actor_user_id limit 1;
 select coalesce(nullif(btrim(first_name||' '||last_name),''),display_name,'Club member') into member_name
  from public.member_profiles where id=change.member_profile_id;
 insert into public.audit_journal(actor_user_id,actor_name,origin,club_id,club_name,record_type,record_id,record_label,
   action,reason,before_values,after_values,outcome)
 values(change.actor_user_id,coalesce(actor_name,'Club administrator'),'admin_email_change',change.club_id,
   (select name from public.clubs where id=change.club_id),'member_profiles',change.member_profile_id::text,
   coalesce(member_name,'Club member'),'update','Administrator requested login email change',
   jsonb_build_object('email_address',change.old_email),jsonb_build_object('email_address',change.new_email),
   case when verified then 'completed' else 'failed' end);
 return jsonb_build_object('changed',verified,'email',change.new_email);
end $$;
revoke all on function public.begin_admin_member_email_change(uuid,uuid,uuid,text,text),
 public.finish_admin_member_email_change(uuid) from public,anon,authenticated;
grant execute on function public.begin_admin_member_email_change(uuid,uuid,uuid,text,text),
 public.finish_admin_member_email_change(uuid) to service_role;
notify pgrst,'reload schema';
