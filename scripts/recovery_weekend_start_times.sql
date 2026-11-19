-- Remove only the weekend filter, preserving other booking protections.
begin;
do $$ declare d text; anchor text:='and t.booking_start_times_enabled and extract(isodow from f.start_at at time zone ''Europe/London'') in (6,7) then'; begin
 select pg_get_functiondef(oid) into strict d from pg_proc where pronamespace='public'::regnamespace and proname='enforce_fixture_type_booking_rules';
 if position(anchor in d)=0 then raise exception 'Weekend booking policy changed; review before recovery';end if;
 execute replace(d,anchor,'and t.booking_start_times_enabled then');
end $$;
notify pgrst,'reload schema';
commit;
