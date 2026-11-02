CREATE OR REPLACE FUNCTION public.build_positioned_competition_draw(p_competition_id uuid, p_positions uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions; n int; capacity int:=2; levels int:=1; r int; j int;
 rid uuid; mid uuid; previous uuid[]; current_ids uuid[]; a uuid; b uuid; sa uuid; sb uuid; round_size int;
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501'; end if;
 if exists(select 1 from public.competition_rounds where competition_id=c.id) then raise exception 'A draw already exists; published rounds are never silently redrawn'; end if;
 select count(*) into n from public.competition_entries where competition_id=c.id;
 if n not between 2 and 256 then raise exception 'A draw requires 2-256 entries'; end if;
 while capacity<n loop capacity:=capacity*2;levels:=levels+1;end loop;
 if cardinality(p_positions) is distinct from capacity or array_lower(p_positions,1)<>1
 or (select count(distinct x) from unnest(p_positions) x where x is not null)<>n
 or (select count(*) from unnest(p_positions) x where x is not null)<>n
 or exists(select 1 from unnest(p_positions) x where x is not null and not exists(select 1 from public.competition_entries e where e.id=x and e.competition_id=c.id)) then
 raise exception 'Supply every entry exactly once in the opening bracket positions, with nulls for byes';end if;
 for j in 1..capacity/2 loop
 if p_positions[j*2-1] is null and p_positions[j*2] is null then raise exception 'An opening match cannot have two byes';end if;
 end loop;
 set constraints public.competition_entry_order_unique deferred;
 with positions as(select x,row_number() over(order by ordinality) n from unnest(p_positions) with ordinality p(x,ordinality) where x is not null)
 update public.competition_entries e set entry_order=p.n from positions p where e.id=p.x;
 for r in 1..levels loop
 round_size:=capacity/(2^(r-1))::int;
 insert into public.competition_rounds(competition_id,round_number,name) values(c.id,r,
 case when r=levels then 'Final' when r=levels-1 then 'Semi-final' when r=levels-2 then 'Quarter-final'
 when r=1 and capacity>n then 'Preliminary' else 'Last '||round_size end) returning id into rid;
 current_ids:='{}'::uuid[];
 for j in 1..(capacity/(2^r)::int) loop
 a:=null;b:=null;sa:=null;sb:=null;
 if r=1 then a:=p_positions[j*2-1];b:=p_positions[j*2];
 else
 sa:=previous[j*2-1];sb:=previous[j*2];
 select winner_entry_id into a from public.competition_draw_matches where id=sa;
 select winner_entry_id into b from public.competition_draw_matches where id=sb;
 end if;
 insert into public.competition_draw_matches(competition_id,round_id,match_number,side_a_kind,side_b_kind,side_a_entry_id,side_b_entry_id,side_a_source_id,side_b_source_id,status,winner_entry_id)
 values(c.id,rid,j,case when r>1 then 'winner' when a is null then 'bye' else 'entry' end,
 case when r>1 then 'winner' when b is null then 'bye' else 'entry' end,
 a,b,sa,sb,case when r=1 and (a is null or b is null) then 'bye' else 'to_be_arranged' end,
 case when r=1 and (a is null or b is null) then coalesce(a,b) else null end) returning id into mid;
 current_ids:=array_append(current_ids,mid);
 end loop;
 previous:=current_ids;
 end loop;
end $function$
;
CREATE OR REPLACE FUNCTION public.build_competition_draw(p_competition_id uuid, p_entry_order uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.club_competitions; n int; capacity int:=2; games int; i int; positions uuid[]:='{}';
begin
 select * into c from public.club_competitions where id=p_competition_id for update;
 if not found or not competition_private.can_manage(c.club_id) then raise exception 'Club administrator access required' using errcode='42501';end if;
 n:=cardinality(p_entry_order);
 if n is null or n not between 2 and 256 then raise exception 'Supply 2-256 entries';end if;
 while capacity<n loop capacity:=capacity*2;end loop;
 games:=n-capacity/2;
 for i in 1..n loop
 positions:=array_append(positions,p_entry_order[i]);
 if i>games*2 then positions:=array_append(positions,null::uuid);end if;
 end loop;
 perform public.build_positioned_competition_draw(c.id,positions);
end $function$
;