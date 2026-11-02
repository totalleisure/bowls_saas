-- Save reviewed consecutive team groups atomically, preserving their order.
create function public.add_competition_teams(p_competition_id uuid,p_members uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; size int; pos int:=1; added int:=0; base_order int;
 team uuid[]; existing_entry uuid; new_entry uuid; base_label text; label text; suffix int;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501';end if;
 if exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'Entries are locked after creating the draw';end if;
 size:=(c.settings->>'players_per_entry')::int;
 if size is null or size not between 2 and 12 then raise exception 'This competition requires individual entries';end if;
 if cardinality(p_members) is null or cardinality(p_members)<size or cardinality(p_members)>size*256
 or cardinality(p_members)%size<>0 or array_lower(p_members,1)<>1
 or (select count(distinct x) from unnest(p_members) x)<>cardinality(p_members)
 or exists(select 1 from unnest(p_members) x where x is null or not exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=x and cm.is_active and cm.role::text<>'guest')) then
 raise exception 'Select different active Club members in complete groups of %',size;end if;
 select coalesce(max(entry_order),0) into base_order from public.competition_entries where competition_id=c.id;
 while pos<=cardinality(p_members) loop
 team:=p_members[pos:pos+size-1];pos:=pos+size;
 select em.entry_id into existing_entry from public.competition_entry_members em where em.competition_id=c.id and em.member_profile_id=any(team) limit 1;
 if existing_entry is not null then
 if (select count(*) from public.competition_entry_members where entry_id=existing_entry)=size
 and (select count(*) from public.competition_entry_members where entry_id=existing_entry and member_profile_id=any(team))=size then continue;end if;
 raise exception 'A selected player is already entered with a different partner';
 end if;
 select string_agg(btrim(concat_ws(' ',nullif(btrim(mp.first_name),''),nullif(btrim(mp.last_name),''))),' / ' order by p.ordinality)
 into base_label from unnest(team) with ordinality p(id,ordinality) join public.member_profiles mp on mp.id=p.id;
 base_label:=left(coalesce(nullif(base_label,''),'Unnamed team'),180);label:=base_label;suffix:=1;
 while exists(select 1 from public.competition_entries where competition_id=c.id and name=label) loop
 suffix:=suffix+1;label:=base_label||' ('||suffix||')';end loop;
 insert into public.competition_entries(competition_id,name,entry_order) values(c.id,label,base_order+added+1) returning id into new_entry;
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) select c.id,new_entry,x from unnest(team) x;
 added:=added+1;
 end loop;
 if (select count(*) from public.competition_entries where competition_id=c.id)>256 then raise exception 'A competition supports up to 256 team entries';end if;
 return added;
end $$;
revoke all on function public.add_competition_teams(uuid,uuid[]) from public,anon,authenticated;
grant execute on function public.add_competition_teams(uuid,uuid[]) to authenticated;
