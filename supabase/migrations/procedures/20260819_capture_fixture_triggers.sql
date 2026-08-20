drop trigger if exists fixtures_set_time_range
on public.fixtures;

create trigger fixtures_set_time_range
before insert or update
on public.fixtures
for each row
execute function public.set_fixture_time_range();


drop trigger if exists fixtures_validate_links
on public.fixtures;

create trigger fixtures_validate_links
before insert or update
on public.fixtures
for each row
execute function public.validate_fixture_links();


drop trigger if exists trg_check_green_area_rink_capacity
on public.fixtures;

create trigger trg_check_green_area_rink_capacity
before insert or update
on public.fixtures
for each row
execute function public.check_green_area_rink_capacity();