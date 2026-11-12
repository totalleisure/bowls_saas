begin;
CREATE OR REPLACE FUNCTION public.change_competition_fixture_booking(p_fixture_id uuid, p_green_area_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_rink_labels text[], p_orientation text, p_expected_start_at timestamp with time zone, p_expected_end_at timestamp with time zone, p_expected_green_area_id uuid, p_expected_rink_labels text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.fixtures; m public.competition_draw_matches; cid uuid; venue uuid; current_labels text[]; comm_revision uuid;
begin
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage this competition fixture, or it is locked' using errcode='42501'; end if;
 select competition_id into cid from public.competition_draw_matches where fixture_id=p_fixture_id;
 if cid is null then raise exception 'This fixture is not linked to a competition match' using errcode='42501'; end if;
 perform 1 from public.club_competitions where id=cid for update;
 select * into strict m from public.competition_draw_matches where fixture_id=p_fixture_id for update;
 -- Same serialization as initial competition booking, including ordinary fixture writes.
 lock table public.fixtures in share row exclusive mode;
 lock table public.fixture_rinks in share row exclusive mode;
 select * into strict f from public.fixtures where id=p_fixture_id for update;
 if not competition_private.can_arrange_linked_fixture(p_fixture_id) then raise exception 'You cannot manage this competition fixture, or it is locked' using errcode='42501'; end if;
 select array_agg(home_rink_label order by fixture_rink_no) into current_labels from public.fixture_rinks where fixture_id=f.id;
 if f.start_at is distinct from p_expected_start_at or f.end_at is distinct from p_expected_end_at
 or f.green_area_id is distinct from p_expected_green_area_id or current_labels is distinct from p_expected_rink_labels
 then raise exception 'The booking has changed. Refresh before making another change.' using errcode='40001'; end if;
 if p_start_at is null or p_end_at is null or p_start_at<=now() or p_end_at<=p_start_at or p_end_at>p_start_at+interval '24 hours'
 then raise exception 'Choose a future start and valid end time'; end if;
 select g.venue_id into venue from public.green_areas g join public.venues v on v.id=g.venue_id
 where g.id=p_green_area_id and v.club_id=f.club_id and v.is_home_venue;
 if venue is null then raise exception 'Choose a home green for this Club'; end if;
 if p_rink_labels is null or cardinality(p_rink_labels)<>f.rinks_required
 or (select count(distinct label) from unnest(p_rink_labels) label where nullif(btrim(label),'') is not null)<>f.rinks_required
 or (select count(*) from public.fixture_rinks where fixture_id=f.id)<>f.rinks_required
 then raise exception 'Select the required number of different rinks'; end if;
 if (select count(*) from public.get_green_rink_availability(p_green_area_id,p_start_at,p_end_at,p_fixture_id) a
 where a.rink_label=any(p_rink_labels) and not a.is_booked and a.free_capacity_rinks>=f.rinks_required)<>f.rinks_required
 then raise exception 'The selected rinks are no longer available. Refresh and choose another rink or time.'; end if;
 if f.start_at=p_start_at and f.end_at=p_end_at and f.green_area_id=p_green_area_id
 and f.orientation::text is not distinct from nullif(btrim(p_orientation),'') and current_labels=p_rink_labels then return;end if;
 update public.fixtures set start_at=p_start_at,end_at=p_end_at,venue_id=venue,green_area_id=p_green_area_id,
 orientation=nullif(btrim(p_orientation),'')::public.orientation where id=f.id;
 with ordered as(select id,row_number() over(order by fixture_rink_no)::int as i from public.fixture_rinks where fixture_id=f.id)
 update public.fixture_rinks fr set home_rink_label=p_rink_labels[o.i] from ordered o where fr.id=o.id;
 insert into public.competition_fixture_management_events(club_id,fixture_id,match_id,actor_user_id,action,details)
 values(f.club_id,f.id,m.id,auth.uid(),'booking_changed',jsonb_build_object('previous',jsonb_build_object('start_at',f.start_at,'end_at',f.end_at,'green_area_id',f.green_area_id,'rinks',current_labels),
 'current',jsonb_build_object('start_at',p_start_at,'end_at',p_end_at,'green_area_id',p_green_area_id,'rinks',p_rink_labels))) returning id into comm_revision;
 perform competition_private.queue_booking_communications(f.id,'updated',
 'management:'||comm_revision::text,f.start_at,f.end_at);
end $function$;
commit;
