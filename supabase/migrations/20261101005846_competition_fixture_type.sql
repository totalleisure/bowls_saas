begin;
-- Explicit Fixture Type association; existing draw positions and rules are preserved.
alter table public.club_competitions add column fixture_type_id uuid
  references public.competition_types(id) on delete restrict;
create index club_competitions_fixture_type_idx on public.club_competitions(fixture_type_id);
comment on column public.club_competitions.fixture_type_id is 'Fixture Type used when arranging competition matches; references competition_types.';

-- Only backfill where the Club has one unambiguous Club Competition type.
update public.club_competitions c set fixture_type_id=t.id
from public.competition_types t
where t.club_id=c.club_id and lower(btrim(t.name))='club competition'
and (select count(*) from public.competition_types x where x.club_id=c.club_id and lower(btrim(x.name))='club competition')=1;

create function competition_private.check_fixture_type() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.fixture_type_id is not null and not exists (
   select 1 from public.competition_types t where t.id=new.fixture_type_id and t.club_id=new.club_id
 ) then raise exception 'Fixture Type must belong to the competition Club' using errcode='23514'; end if;
 return new;
end $$;
revoke all on function competition_private.check_fixture_type() from public,anon,authenticated;
create trigger check_competition_fixture_type before insert or update of fixture_type_id,club_id
on public.club_competitions for each row execute function competition_private.check_fixture_type();
CREATE OR REPLACE FUNCTION public.create_club_competition(p_club_id uuid, p_name text, p_season text, p_settings jsonb, p_fixture_type_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
 if not competition_private.can_manage(p_club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if p_fixture_type_id is null then raise exception 'Select a Fixture Type'; end if;
 perform competition_private.validate_settings(p_settings);
 insert into public.club_competitions(club_id,name,season,settings,created_by,fixture_type_id)
 values(p_club_id,btrim(p_name),btrim(p_season),p_settings,auth.uid(),p_fixture_type_id) returning id into v_id;
 return v_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.update_club_competition(p_competition_id uuid, p_name text, p_season text, p_settings jsonb, p_fixture_type_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;

 if p_fixture_type_id is null then raise exception 'Select a Fixture Type'; end if;
 perform competition_private.validate_settings(p_settings);
 if (exists(select 1 from public.competition_entries where competition_id=c.id)
     or exists(select 1 from public.competition_rounds where competition_id=c.id))
 and (p_settings->>'players_per_entry' is distinct from c.settings->>'players_per_entry'
      or p_settings->>'playing_format' is distinct from c.settings->>'playing_format') then
 raise exception 'Playing format and team size cannot change while entries or a draw exist';end if;
 if nullif(btrim(p_name),'') is null or nullif(btrim(p_season),'') is null then raise exception 'Competition name and season are required';end if;
 update public.club_competitions set name=btrim(p_name),season=btrim(p_season),settings=p_settings,fixture_type_id=p_fixture_type_id where id=c.id;
end $function$
;
revoke all on function public.create_club_competition(uuid,text,text,jsonb,uuid),public.update_club_competition(uuid,text,text,jsonb,uuid) from public,anon;
grant execute on function public.create_club_competition(uuid,text,text,jsonb,uuid),public.update_club_competition(uuid,text,text,jsonb,uuid) to authenticated;
create or replace function public.create_club_competition(p_club_id uuid,p_name text,p_season text,p_settings jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 if not competition_private.can_manage(p_club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 raise exception 'Select a Fixture Type using the updated competition setup screen';
end $$;

commit;
