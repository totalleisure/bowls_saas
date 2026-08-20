CREATE OR REPLACE FUNCTION public.set_fixture_time_range()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.time_range :=
    tstzrange(
      new.start_at,
      coalesce(new.end_at, new.start_at + interval '4 hours'),
      '[)'
    );
  return new;
end;
$function$