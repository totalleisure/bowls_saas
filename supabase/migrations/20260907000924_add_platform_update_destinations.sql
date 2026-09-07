alter table public.app_version_policy
  add column if not exists update_url text,
  add column if not exists update_message text;

comment on column public.app_version_policy.update_url is
  'Platform-specific external update destination. Supported client schemes are https and itms-apps.';

comment on column public.app_version_policy.update_message is
  'Optional platform-specific instructions displayed by the minimum-version gate.';

do $migration$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.app_version_policy'::regclass
      and c.conname = 'app_version_policy_update_url_scheme_check'
  ) then
    alter table public.app_version_policy
      add constraint app_version_policy_update_url_scheme_check
      check (
        update_url is null
        or btrim(update_url) = ''
        or update_url ~* '^(https|itms-apps)://'
      );
  end if;
end;
$migration$;
