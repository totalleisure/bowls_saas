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
