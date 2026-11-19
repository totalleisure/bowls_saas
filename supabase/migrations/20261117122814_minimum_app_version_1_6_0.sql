-- Version 1.6.0 begins at build 28 (98f76cf); 1.5.6 was build 27.
begin;
insert into public.app_version_policy(platform,minimum_build,latest_build,force_update_message)
select p,28,28,'Please update Total Leisure Bowls to version 1.6.0 or later before continuing.'
from unnest(array['ios','android','windows']) p
on conflict(platform) do update set
 minimum_build=greatest(public.app_version_policy.minimum_build,28),
 latest_build=greatest(public.app_version_policy.latest_build,public.app_version_policy.minimum_build,28),
 force_update_message=excluded.force_update_message,
 updated_at=clock_timestamp();
commit;
