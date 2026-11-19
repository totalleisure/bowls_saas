begin;
do $$ declare d text; anchor text:='if check_times and f.is_home and t.bookable_by_members and t.booking_start_times_enabled then'; begin
 select pg_get_functiondef(oid) into strict d from pg_proc where pronamespace='public'::regnamespace and proname='enforce_fixture_type_booking_rules';
 if md5(replace(d,chr(13),''))<>'2beefec45d835a3379ef91b070c53291' or position(anchor in d)=0 then raise exception 'Fixture booking policy changed; review before weekend amendment';end if;
 execute replace(d,anchor,'if check_times and f.is_home and t.bookable_by_members and t.booking_start_times_enabled and extract(isodow from f.start_at at time zone ''Europe/London'') in (6,7) then');
end $$;
notify pgrst,'reload schema';
commit;
