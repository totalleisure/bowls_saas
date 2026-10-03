-- Teams are visible only to active club members. Existing pool editing roles retained.
alter table public.teams enable row level security;
-- RLS does not govern TRUNCATE or schema-level capabilities.
revoke truncate,references,trigger on public.teams from anon,authenticated;
create policy teams_read_club on public.teams for select to authenticated
using (club_id in (select public.my_active_club_ids()));
create policy teams_create_club on public.teams for insert to authenticated
with check (exists (select 1 from public.club_memberships cm
 where cm.club_id=teams.club_id and cm.member_profile_id=(select public.my_member_profile_id())
 and cm.is_active and cm.role::text in ('admin','selector')));
create policy teams_edit_club on public.teams for update to authenticated
using (club_id in (select public.my_active_club_ids()) and (
 (select public.my_member_profile_id()) in (captain_member_profile_id,vice_captain_member_profile_id,manager_member_profile_id)
 or exists(select 1 from public.club_memberships cm where cm.club_id=teams.club_id
 and cm.member_profile_id=(select public.my_member_profile_id()) and cm.is_active
 and cm.role::text in ('admin','selector'))))
with check (club_id in (select public.my_active_club_ids()));
-- No client delete policy: the current application deactivates teams/members.
-- Restrict structural columns as well as rows; WITH CHECK alone cannot compare OLD/NEW.
revoke update on public.teams from authenticated;
grant update(name,description,is_active,section,captain_member_profile_id,
 vice_captain_member_profile_id,manager_member_profile_id) on public.teams to authenticated;

create or replace function public.validate_team_club_links() returns trigger
language plpgsql security invoker set search_path='' as $function$
begin
 if TG_OP='UPDATE' then
  if new.id is distinct from old.id or new.club_id is distinct from old.club_id then
   raise exception 'A team cannot be moved to a different club or identity' using errcode='23514';
  end if;
  if new.captain_member_profile_id is not distinct from old.captain_member_profile_id
   and new.vice_captain_member_profile_id is not distinct from old.vice_captain_member_profile_id
   and new.manager_member_profile_id is not distinct from old.manager_member_profile_id then
   return new;
  end if;
 end if;
 if exists(select 1 from unnest(array[new.captain_member_profile_id,
   new.vice_captain_member_profile_id,new.manager_member_profile_id]) as leader(id)
   where leader.id is not null and not exists(select 1 from public.club_memberships cm
    where cm.club_id=new.club_id and cm.member_profile_id=leader.id and cm.is_active
    and cm.role::text<>'guest')) then
  raise exception 'Team officials must be active non-guest members of this club' using errcode='23514';
 end if;
 return new;
end $function$;
revoke all on function public.validate_team_club_links() from public,anon,authenticated;
create trigger validate_team_club_links before insert or update on public.teams
for each row execute function public.validate_team_club_links();
