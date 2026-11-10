-- Store each confirmed selection position explicitly.
CREATE OR REPLACE FUNCTION public.add_competition_singles(p_competition_id uuid, p_members uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions; member_id uuid; entry_id uuid; label text; base_label text; suffix int; added int:=0; base_order int;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'Entries are locked after creating the draw'; end if;
 if (c.settings->>'players_per_entry')::int<>1 then raise exception 'Select the players for one team together'; end if;
 if cardinality(p_members) is null or cardinality(p_members) not between 1 and 256
 or exists(select 1 from unnest(p_members) x where x is null or not exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=x and cm.is_active and cm.role::text<>'guest')) then
 raise exception 'Select active Club members (up to 256 at once)'; end if;
 select coalesce(max(entry_order),0) into base_order from public.competition_entries where competition_id=c.id;
 foreach member_id in array p_members loop
 if exists(select 1 from public.competition_entry_members where competition_id=c.id and member_profile_id=member_id) then continue; end if;
 select btrim(concat_ws(' ',nullif(btrim(mp.first_name),''),nullif(btrim(mp.last_name),''))) into base_label from public.member_profiles mp where mp.id=member_id;
 if coalesce(base_label,'')='' then base_label:='Unnamed member'; end if;
 base_label:=left(base_label,180); label:=base_label; suffix:=1;
 while exists(select 1 from public.competition_entries where competition_id=c.id and name=label) loop
 suffix:=suffix+1; label:=base_label||' ('||suffix||')'; end loop;
 insert into public.competition_entries(competition_id,name,entry_order) values(c.id,label,base_order+added+1) returning id into entry_id;
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c.id,entry_id,member_id);
 added:=added+1;
 end loop;
 return added;
end $function$;

revoke all on function public.add_competition_singles(uuid,uuid[]) from public,anon;
grant execute on function public.add_competition_singles(uuid,uuid[]) to authenticated;
