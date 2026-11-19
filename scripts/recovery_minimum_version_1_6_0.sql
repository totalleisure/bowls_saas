-- Production-only rollback to the verified pre-change policy. URLs and optional update_message are untouched.
begin;
update public.app_version_policy set minimum_build=17,latest_build=17,
 force_update_message='This version of the Total Leisure Bowls App is no longer supported. Please update to the latest version before continuing.',updated_at=clock_timestamp()
where platform in ('ios','android','windows') and minimum_build=28 and latest_build=28
 and force_update_message='Please update Total Leisure Bowls to version 1.6.0 or later before continuing.';
commit;
-- Staging previously had no policy rows: to undo only this change in staging,
-- delete the three rows only after verifying their values still match this migration.
