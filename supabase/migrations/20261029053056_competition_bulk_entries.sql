-- Bulk singles are atomic and safe to retry. Team membership remains explicit.
create function public.add_competition_singles(p_competition_id uuid,p_members uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare c public.club_competitions; member_id uuid; entry_id uuid; label text; base_label text; suffix int; added int:=0;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'Entries are locked after creating the draw'; end if;
 if (c.settings->>'players_per_entry')::int<>1 then raise exception 'Select the players for one team together'; end if;
 if cardinality(p_members) is null or cardinality(p_members) not between 1 and 256
 or exists(select 1 from unnest(p_members) x where x is null or not exists(select 1 from public.club_memberships cm where cm.club_id=c.club_id and cm.member_profile_id=x and cm.is_active and cm.role::text<>'guest')) then
 raise exception 'Select active Club members (up to 256 at once)'; end if;
 foreach member_id in array p_members loop
 if exists(select 1 from public.competition_entry_members where competition_id=c.id and member_profile_id=member_id) then continue; end if;
 select btrim(concat_ws(' ',nullif(btrim(mp.first_name),''),nullif(btrim(mp.last_name),''))) into base_label from public.member_profiles mp where mp.id=member_id;
 if coalesce(base_label,'')='' then base_label:='Unnamed member'; end if;
 base_label:=left(base_label,180); label:=base_label; suffix:=1;
 while exists(select 1 from public.competition_entries where competition_id=c.id and name=label) loop
 suffix:=suffix+1; label:=base_label||' ('||suffix||')'; end loop;
 insert into public.competition_entries(competition_id,name) values(c.id,label) returning id into entry_id;
 insert into public.competition_entry_members(competition_id,entry_id,member_profile_id) values(c.id,entry_id,member_id);
 added:=added+1;
 end loop;
 return added;
end $$;

-- Null paid means unchanged. Explicit set_handicap permits clearing to null.
create function public.update_competition_entry_options(p_entry_id uuid,p_paid boolean default null,p_handicap numeric default null,p_set_handicap boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; club uuid;
begin
 select e.competition_id,c.club_id into cid,club from public.competition_entries e join public.club_competitions c on c.id=e.competition_id where e.id=p_entry_id;
 if cid is null or not competition_private.can_manage(club) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 if p_set_handicap then
 if exists(select 1 from public.competition_rounds where competition_id=cid) then raise exception 'Handicaps are locked after creating the draw'; end if;
 if p_handicap is not null and (p_handicap::text in ('NaN','Infinity','-Infinity') or p_handicap not between -100000 and 100000) then raise exception 'Enter a finite handicap between -100000 and 100000'; end if;
 update public.competition_entries set handicap=p_handicap where id=p_entry_id;
 end if;
 if p_paid is not null then
 update public.competition_entries set payment_status=case when p_paid then 'paid' else 'unpaid' end where id=p_entry_id;
 end if;
end $$;
revoke all on function public.add_competition_singles(uuid,uuid[]),public.update_competition_entry_options(uuid,boolean,numeric,boolean) from public,anon,authenticated;
grant execute on function public.add_competition_singles(uuid,uuid[]),public.update_competition_entry_options(uuid,boolean,numeric,boolean) to authenticated;
