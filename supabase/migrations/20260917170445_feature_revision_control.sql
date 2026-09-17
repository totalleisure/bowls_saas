-- PROPOSED ONLY. Production approval required before execution.
-- Target: xfjelvvfoguzukgvxchh. Apply this delta only; do not replay staging baseline.
BEGIN;
create table public.feature_revision_policy (
 id boolean primary key default true check (id),
 enabled_revision integer not null default 0 check (enabled_revision between 0 and 1),
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);
insert into public.feature_revision_policy(id) values (true);
alter table public.feature_revision_policy enable row level security;
revoke all on public.feature_revision_policy from public, anon, authenticated;
grant select on public.feature_revision_policy to authenticated;
grant update(enabled_revision, updated_at, updated_by) on public.feature_revision_policy to authenticated;
create policy feature_revision_read on public.feature_revision_policy for select to authenticated using (true);
create policy feature_revision_update on public.feature_revision_policy for update to authenticated
 using ((select public.is_app_superuser()))
 with check ((select public.is_app_superuser()) and updated_by = (select auth.uid()));

create function public.set_feature_revision(p_revision integer, p_expected_revision integer)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.is_app_superuser() then
  raise exception 'Superuser access required.' using errcode='42501';
 end if;
 if p_revision is null or p_revision not between 0 and 1 then
  raise exception 'Supported feature revisions are 0 and 1.' using errcode='22023';
 end if;
 update public.feature_revision_policy
 set enabled_revision=p_revision, updated_at=clock_timestamp(), updated_by=auth.uid()
 where id=true and enabled_revision=p_expected_revision
 returning to_jsonb(feature_revision_policy.*) into result;
 if result is null then
  raise exception 'Revision changed or policy missing. Refresh and try again.' using errcode='40001';
 end if;
 return result;
end;
$$;

create function public.require_feature_revision(p_required integer)
returns void language plpgsql security invoker set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
 if p_required is null or p_required < 1 or not exists (
  select 1 from public.feature_revision_policy where id=true and enabled_revision>=p_required
 ) then
  raise exception 'This feature is not enabled.' using errcode='42501';
 end if;
end;
$$;

-- Read-only demonstration. Business RPCs must choose their own fixed revision;
-- never trust a client-supplied revision to authorise a business operation.
create function public.feature_revision_demo()
returns text language plpgsql security invoker set search_path = '' as $$
begin
 perform public.require_feature_revision(1);
 return 'Revision 1 is enabled. The database accepted this demonstration.';
end;
$$;
revoke all on function public.set_feature_revision(integer,integer) from public, anon;
revoke all on function public.require_feature_revision(integer) from public, anon;
revoke all on function public.feature_revision_demo() from public, anon;
grant execute on function public.set_feature_revision(integer,integer) to authenticated;
grant execute on function public.require_feature_revision(integer) to authenticated;
grant execute on function public.feature_revision_demo() to authenticated;

COMMIT;
