create schema if not exists notification_security;
revoke all on schema notification_security from public;
grant usage on schema notification_security to authenticated;
-- A narrow policy predicate needs protected membership/selection records.
create or replace function notification_security.can_enqueue(q public.notification_queue)
returns boolean language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare actor uuid; club uuid; f public.fixtures; manager boolean; super boolean;
begin
 if auth.uid() is null then return false; end if;
 actor:=public.my_member_profile_id();
 if actor is null or q.member_profile_id is distinct from actor
    or q.target_member_profile_id is null or q.status is distinct from 'pending'
    or q.attempts<>0 or q.last_error is not null or q.processed_at is not null
    or q.recipient_email is not null then return false; end if;
 super:=public.is_app_superuser();
 if q.event_type='guest_membership_approved' then
  if q.fixture_id is not null or q.team_selection_id is not null then return false; end if;
  begin club:=(q.payload->>'club_id')::uuid; exception when invalid_text_representation then return false; end;
  return coalesce((super or public.is_club_admin(club)) and exists(
   select 1 from public.club_memberships where club_id=club and member_profile_id=q.target_member_profile_id
    and is_active and role::text='member'),false);
 end if;
 if q.event_type not in ('fixture_message','acceptance_reminder','fixture_selected') then return false; end if;
 select * into f from public.fixtures where id=q.fixture_id;
 if not found then return false; end if;
 if not super and not exists(select 1 from public.club_memberships
  where club_id=f.club_id and member_profile_id=actor and is_active and role::text<>'guest') then return false; end if;
 if not exists(select 1 from public.club_memberships where club_id=f.club_id
  and member_profile_id=q.target_member_profile_id and is_active) then return false; end if;
 if q.team_selection_id is not null and not exists(select 1 from public.team_selections
  where id=q.team_selection_id and fixture_id=f.id) then return false; end if;
 manager:=super or actor in (f.captain_member_profile_id,f.vice_captain_member_profile_id)
  or exists(select 1 from public.club_memberships where club_id=f.club_id and member_profile_id=actor
   and is_active and role::text in ('admin','selector'));
 if q.event_type='fixture_selected' then
  return coalesce((manager or actor=q.target_member_profile_id) and exists(
   select 1 from public.fixture_rink_assignments where fixture_id=f.id and member_profile_id=q.target_member_profile_id),false);
 end if;
 if not coalesce(manager,false) then return false; end if;
 if q.event_type='acceptance_reminder' then
  return exists(select 1 from public.team_selection_members where team_selection_id=q.team_selection_id
   and member_profile_id=q.target_member_profile_id and acceptance::text='pending');
 end if;
 return coalesce(q.target_member_profile_id in (f.captain_member_profile_id,f.vice_captain_member_profile_id)
  or exists(select 1 from public.team_selection_members where team_selection_id=q.team_selection_id
   and member_profile_id=q.target_member_profile_id),false);
end;
$$;
revoke all on function notification_security.can_enqueue(public.notification_queue) from public,anon;
grant execute on function notification_security.can_enqueue(public.notification_queue) to authenticated;
alter table public.notification_queue enable row level security;
revoke all on public.notification_queue from public,anon,authenticated;
grant insert(event_type,member_profile_id,target_member_profile_id,fixture_id,team_selection_id,payload,status)
 on public.notification_queue to authenticated;
create policy notification_queue_authorized_insert on public.notification_queue
 for insert to authenticated with check(notification_security.can_enqueue(notification_queue));
