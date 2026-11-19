begin;
create unique index email_competition_booking_removed_recipient on public.email_queue
 ((payload->>'competition_booking_removed_key'),lower(btrim(recipient_email)))
 where event_type='competition_booking_removed';

create function competition_private.queue_booking_removal(p_match_id uuid,p_fixture_id uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare m public.competition_draw_matches; c public.club_competitions; r public.competition_rounds; f public.fixtures;
 msg text; n integer; rink_text text;
begin
 select * into strict m from public.competition_draw_matches where id=p_match_id and fixture_id=p_fixture_id;
 select * into strict c from public.club_competitions where id=m.competition_id;
 select * into strict r from public.competition_rounds where id=m.round_id;
 select * into strict f from public.fixtures where id=p_fixture_id;
 select string_agg(coalesce(nullif(home_rink_label,''),fixture_rink_no::text),', ' order by fixture_rink_no)
 into rink_text from public.fixture_rinks where fixture_id=f.id;
 msg:=concat_ws(chr(10),
 'The booking for your competition match has been removed. The competition match has NOT been cancelled.',
 'Please contact the other players and arrange a new date, time and rink. The match is now shown as "To be arranged" in the App.',
 '', 'Competition: '||c.name,'Round: '||r.name||' '||m.match_number,
 (select name from public.competition_entries where id=m.side_a_entry_id)||' versus '||(select name from public.competition_entries where id=m.side_b_entry_id),
 'Removed booking: '||to_char(f.start_at at time zone 'Europe/London','FMDay DD Mon YYYY HH24:MI')||' to '||to_char(f.end_at at time zone 'Europe/London','HH24:MI'),
 'Venue: '||(select name from public.venues where id=f.venue_id),
 'Green: '||(select name from public.green_areas where id=f.green_area_id), 'Rink: '||coalesce(rink_text,'Not allocated'),
 'Play by: '||coalesce(to_char(r.play_by,'DD Mon YYYY'),'Not set'),
 case when nullif(btrim(current_setting('app.audit_reason',true)),'') is not null then 'Reason: '||current_setting('app.audit_reason',true) end,
 '', 'Your competition entry and draw position are unchanged. Open your competitions in the App to rearrange this match.');
 -- Self-contained rows survive fixture deletion and use the ordinary throttled mail queue.
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,payload,status)
 select distinct on(lower(btrim(mp.email_address))) mp.id,'competition_booking_removed',lower(btrim(mp.email_address)),
 'Booking removed - please rearrange: '||c.name||' - '||r.name||' '||m.match_number,msg,
 jsonb_build_object('competition_booking_removed_key',f.id::text||':'||m.id::text,
 'deleted_fixture_id',f.id,'competition_id',c.id,'competition_match_id',m.id,'club_id',c.club_id,
 'fixture_deleted',true,'team_sheet_required',false),'pending'
 from public.competition_entry_members em join public.member_profiles mp on mp.id=em.member_profile_id
 where em.competition_id=c.id and em.entry_id in(m.side_a_entry_id,m.side_b_entry_id)
 and competition_private.email_recipient_allowed(mp.email_address)
 order by lower(btrim(mp.email_address)),mp.id
 on conflict do nothing;
 get diagnostics n=row_count;
 return n;
end $$;
revoke all on function competition_private.queue_booking_removal(uuid,uuid) from public,anon,authenticated;

create or replace function competition_private.detach_deleted_fixture() returns trigger
language plpgsql security definer set search_path='' as $$
declare m public.competition_draw_matches;
begin
 if not exists(select 1 from public.competition_draw_matches where fixture_id=old.id) then return old;end if;
 -- The existing fixture deletion RPC/guard still authorises this operation.
 -- Lock the draw before detaching, so result confirmation cannot race deletion.
 for m in select * from public.competition_draw_matches where fixture_id=old.id order by id for update loop
  if m.status<>'to_be_arranged' or m.score_a is not null or m.score_b is not null
     or m.winner_entry_id is not null or m.proposed_winner_entry_id is not null then
   raise exception 'This competition match has a recorded result. Keep its booking and review the result with the Competition Secretary.';
  end if;
 end loop;
 if exists(select 1 from scorecard_private.shared_cards where fixture_id=old.id)
    or exists(select 1 from scorecard_private.fixture_rink_setups s
      join scorecard_private.fixture_matches fm on fm.id=s.match_id where fm.fixture_id=old.id) then
  raise exception 'A scorecard has already been prepared for this competition fixture. Review it before removing the booking.';
 end if;
 for m in select * from public.competition_draw_matches where fixture_id=old.id order by id loop
  perform competition_private.queue_booking_removal(m.id,old.id);
 end loop;
 insert into public.audit_journal(actor_user_id,actor_name,origin,club_id,record_type,record_id,record_label,fixture_id,action,reason,before_values,after_values)
 select auth.uid(),coalesce((select nullif(trim(concat_ws(' ',first_name,last_name)),'') from public.member_profiles where user_id=auth.uid() limit 1),auth.uid()::text,'Database maintenance'),'app',old.club_id,'competition_draw_matches',d.id::text,'Competition booking removed',old.id,'booking removed',
 nullif(current_setting('app.audit_reason',true),''),to_jsonb(d),jsonb_build_object('fixture_id',null,'status','to_be_arranged')
 from public.competition_draw_matches d where d.fixture_id=old.id;
 update public.competition_fixture_management_events
 set fixture_id=null,details=details || jsonb_build_object('deleted_fixture_id',old.id,'booking_removed_at',now())
 where fixture_id=old.id;
 update public.competition_draw_matches set fixture_id=null where fixture_id=old.id;
 return old;
end $$;
revoke all on function competition_private.detach_deleted_fixture() from public,anon,authenticated;

commit;
