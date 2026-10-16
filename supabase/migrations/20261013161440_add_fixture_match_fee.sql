-- Additive: old clients and existing fixtures continue to work unchanged.
alter table public.fixtures add column match_fee_pence integer
  constraint fixtures_match_fee_nonnegative check (match_fee_pence >= 0);
comment on column public.fixtures.match_fee_pence is 'GBP match fee per player, in whole pence. NULL means not set; zero means free.';

-- Keep the established creation function intact. Delegate to it in the SAME
-- transaction so a failed fee write cannot leave a partially created fixture.
do $migration$
declare
  source_oid oid;
  arguments text;
  forwarded text;
  signature text;
begin
  select oid into strict source_oid from pg_proc
  where pronamespace='public'::regnamespace and proname='create_fixture_with_setup_v2';
  arguments := pg_get_function_arguments(source_oid);
  select string_agg(format('%I => %I',name,name), ', ' order by ord)
    into forwarded from pg_proc p,
    unnest(p.proargnames) with ordinality n(name,ord) where p.oid=source_oid;
  execute format($ddl$
    create function public.create_fixture_with_match_fee(%s, p_match_fee_pence integer default null)
    returns uuid language plpgsql security definer set search_path = '' as $body$
    declare fixture_id uuid;
    begin
      if auth.uid() is null then raise exception 'You must be signed in.' using errcode='42501'; end if;
      if p_match_fee_pence < 0 then raise exception 'Match fee cannot be negative.' using errcode='22023'; end if;
      fixture_id := public.create_fixture_with_setup_v2(%s);
      update public.fixtures set match_fee_pence=p_match_fee_pence where id=fixture_id;
      return fixture_id;
    end;
    $body$;
  $ddl$,arguments,forwarded);
  select pg_get_function_identity_arguments(oid) into signature from pg_proc
  where pronamespace='public'::regnamespace and proname='create_fixture_with_match_fee';
  execute 'revoke all on function public.create_fixture_with_match_fee('||signature||') from public, anon';
  execute 'grant execute on function public.create_fixture_with_match_fee('||signature||') to authenticated';
end;
$migration$;

create function public.set_fixture_match_fee(p_fixture_id uuid, p_match_fee_pence integer,
  p_expected_match_fee_pence integer)
returns void language plpgsql security definer set search_path='' as $body$
declare current_fee integer;
begin
  if auth.uid() is null or not (public.can_manage_fixture(p_fixture_id)
    or public.is_active_fixture_creator(p_fixture_id)) then
    raise exception 'You do not have permission to amend this fixture.' using errcode='42501';
  end if;
  if p_match_fee_pence < 0 then raise exception 'Match fee cannot be negative.' using errcode='22023'; end if;
  select match_fee_pence into current_fee from public.fixtures where id=p_fixture_id for update;
  if not found then raise exception 'Fixture not found.'; end if;
  if current_fee is distinct from p_expected_match_fee_pence then
    raise exception 'The fee was changed by someone else. Refresh and try again.' using errcode='40001';
  end if;
  update public.fixtures set match_fee_pence=p_match_fee_pence where id=p_fixture_id;
end;
$body$;
revoke all on function public.set_fixture_match_fee(uuid,integer,integer) from public,anon;
grant execute on function public.set_fixture_match_fee(uuid,integer,integer) to authenticated;

-- Preserve the local deployed repeat function, adding only fee inheritance.
do $migration$
declare definition text;
begin
  select pg_get_functiondef(oid) into strict definition from pg_proc
  where pronamespace='public'::regnamespace and proname='create_repeated_fixture_from_source';
  if (length(definition)-length(replace(definition,'return v_fixture_id;','')))/length('return v_fixture_id;') <> 1 then
    raise exception 'Unexpected repeat function definition; review before applying.';
  end if;
  execute replace(definition,'return v_fixture_id;',
    'update public.fixtures set match_fee_pence=v_source.match_fee_pence where id=v_fixture_id; return v_fixture_id;');
end;
$migration$;
notify pgrst, 'reload schema';
