do $test$
declare c public.club_competitions; before_entries jsonb; before_matches jsonb; options jsonb;
begin
select * into strict c from public.club_competitions where id='f6d357b6-7d72-4639-9064-b9df52ea7738';
perform set_config('request.jwt.claim.sub',c.created_by::text,true);
select jsonb_agg(e order by entry_order) into before_entries from public.competition_entries e where competition_id=c.id;
select jsonb_agg(m order by id) into before_matches from public.competition_draw_matches m where competition_id=c.id;
options:=c.settings||'{"rules":"Updated rules","scoring":"21 shots","woods_per_player":4,"dress":"Whites"}'::jsonb;
perform public.update_club_competition(c.id,c.name,c.season,options);
assert (select settings=options from public.club_competitions where id=c.id),'Rules not saved';
begin perform public.update_club_competition(c.id,c.name,c.season,options||'{"players_per_entry":3,"playing_format":"triples"}');raise exception 'Structural change allowed';exception when raise_exception then if sqlerrm='Structural change allowed' then raise;end if;end;
assert before_entries=(select jsonb_agg(e order by entry_order) from public.competition_entries e where competition_id=c.id),'Entries changed';
assert before_matches is not distinct from (select jsonb_agg(m order by id) from public.competition_draw_matches m where competition_id=c.id),'Draw changed';
update public.club_competitions set status='published' where id=c.id;
perform public.update_club_competition(c.id,c.name,c.season,options);
perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
begin perform public.update_club_competition(c.id,c.name,c.season,options);raise exception 'Outsider allowed';exception when insufficient_privilege then null;end;
end $test$;
select 'PASS: original rules editable, format protected, entries and draw unchanged, published edits and permissions checked' result;
