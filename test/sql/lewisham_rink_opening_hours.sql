begin;
do $$
declare club uuid:='8ae87bbe-cb16-4330-a5b0-e62366479f07'; ft uuid; venue uuid; green uuid:=gen_random_uuid();
 u uuid:=gen_random_uuid(); actor uuid; f uuid; bad uuid; d date; st timestamptz; en timestamptz; t record; checks int:=0;
begin
 select id into strict ft from public.competition_types where club_id=club and is_active and uses_rinks limit 1;
 select id into strict venue from public.venues where club_id=club and is_home_venue limit 1;
 insert into public.green_areas(id,club_id,venue_id,name,discipline,rink_count,scheme_type,scheme_prefix,orientation_mode,allowed_orientations)
 values(green,club,venue,'Synthetic opening-hours verification','indoor',1,'numeric','R','not_applicable','{}');
 insert into auth.users(id,email,raw_user_meta_data) values(u,'hours-test-'||u||'@example.invalid',jsonb_build_object('first_name','Synthetic','last_name','Hours Test'));
 select id into actor from public.member_profiles where user_id=u;
 if actor is null then insert into public.member_profiles(user_id,display_name,first_name,last_name) values(u,'Synthetic Hours Test','Synthetic','Hours Test') returning id into actor; end if;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,actor,'admin',true);
 perform set_config('request.jwt.claim.sub',u::text,true);
 foreach d in array array[date '2031-01-14',date '2031-07-14'] loop
  for t in select * from (values(time '09:00',time '10:00',0,true),(time '20:00',time '22:00',0,true),(time '08:59',time '10:00',0,false),(time '20:00',time '22:01',0,false),(time '21:00',time '09:00',1,false)) x(s,e,extra,allowed) loop
   st:=(d+t.s) at time zone 'Europe/London'; en:=(d+t.extra+t.e) at time zone 'Europe/London';
   begin
    insert into public.fixtures(club_id,start_at,end_at,is_home,section,rinks_required,players_per_rink,competition_type_id,venue_id,green_area_id,captain_member_profile_id,requires_rsvp,team_name)
    values(club,st,en,true,'open',1,1,ft,venue,green,actor,false,'Synthetic hours test') returning id into f;
    if not t.allowed then raise exception 'TEST FAILURE: outside-hours insertion accepted'; end if;
   exception when raise_exception then
    if t.allowed or sqlerrm not like 'Rink bookings must start at or after 09:00%' then raise; end if;
   end;
   checks:=checks+1;
  end loop;
 end loop;
 -- A raw reschedule must also be rejected, independent of client/RPC version.
 begin update public.fixtures set start_at=(date '2031-07-14'+time '08:00') at time zone 'Europe/London' where id=f;
 raise exception 'TEST FAILURE: before-opening reschedule accepted';
 exception when raise_exception then if sqlerrm not like 'Rink bookings must start at or after 09:00%' then raise; end if; end;
 begin update public.fixtures set end_at=(date '2031-07-14'+time '22:01') at time zone 'Europe/London' where id=f;
 raise exception 'TEST FAILURE: after-closing reschedule accepted';
 exception when raise_exception then if sqlerrm not like 'Rink bookings must start at or after 09:00%' then raise; end if; end;
 if checks<>10 then raise exception 'Missing seasonal boundary tests'; end if;
end $$;
rollback;
select 'PASS: direct database inserts and reschedules reject outside 09:00-22:00 and overnight bookings; exact boundaries accepted in winter and summer; synthetic changes rolled back' result;
