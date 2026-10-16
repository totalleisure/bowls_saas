-- Local review only. Do not apply to either hosted project automatically.
create schema if not exists account_private;
revoke all on schema account_private from public, anon, authenticated;

create table account_private.usernames (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  updated_at timestamptz not null default now(),
  constraint username_format check (
    username = lower(username) and username ~ '^[a-z0-9][a-z0-9_.-]{2,29}$'
    and username not in ('admin','administrator','support','system','root','moderator')
  )
);
alter table account_private.usernames enable row level security;
revoke all on account_private.usernames from public, anon, authenticated;

create table account_private.login_limits (
  key text primary key,
  window_start timestamptz not null,
  attempts integer not null
);
alter table account_private.login_limits enable row level security;
revoke all on account_private.login_limits from public, anon, authenticated;

create function public.my_account_username() returns text
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  return (select username from account_private.usernames where user_id=auth.uid());
end;
$$;
revoke all on function public.my_account_username() from public, anon;
grant execute on function public.my_account_username() to authenticated;

create function public.set_account_username(requested_username text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  normalized text := nullif(lower(btrim(requested_username)), '');
begin
  if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if normalized is not null and (
    normalized !~ '^[a-z0-9][a-z0-9_.-]{2,29}$'
    or normalized in ('admin','administrator','support','system','root','moderator')
  ) then raise exception 'Invalid username' using errcode='22023'; end if;
  -- Serialize edits for this Auth account; there is no caller-supplied owner ID.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text, 0));
  if exists(select 1 from account_private.usernames where user_id=actor and updated_at > now()-interval '30 seconds') then
    raise exception 'Please wait before changing your username again' using errcode='P0001';
  end if;
  -- Retain the timestamp even on removal so remove/recreate cannot bypass limits.
  insert into account_private.usernames(user_id,username) values(actor,normalized)
  on conflict(user_id) do update set username=excluded.username,updated_at=now();
  return normalized;
end;
$$;
revoke all on function public.set_account_username(text) from public, anon;
grant execute on function public.set_account_username(text) to authenticated;

-- Service-only rate limiting. Each counter uses an atomic upsert across instances.
create function public.consume_username_login_limit(limit_key text, max_attempts integer) returns boolean
language plpgsql security definer set search_path = '' as $$
declare count_now integer;
begin
  if limit_key is null or length(limit_key)>128 or max_attempts not between 1 and 120 then
    raise exception 'Invalid limit';
  end if;
  insert into account_private.login_limits(key,window_start,attempts)
  values(limit_key,now(),1)
  on conflict(key) do update set
    window_start=case when account_private.login_limits.window_start <= now()-interval '1 minute' then now() else account_private.login_limits.window_start end,
    attempts=case when account_private.login_limits.window_start <= now()-interval '1 minute' then 1 else account_private.login_limits.attempts+1 end
  returning attempts into count_now;
  delete from account_private.login_limits where window_start < now()-interval '10 minutes';
  return count_now <= max_attempts;
end;
$$;
revoke all on function public.consume_username_login_limit(text,integer) from public,anon,authenticated;
grant execute on function public.consume_username_login_limit(text,integer) to service_role;

create function public.resolve_username_login(requested_username text) returns text
language sql stable security definer set search_path = '' as $$
  select u.email from account_private.usernames n join auth.users u on u.id=n.user_id
  where n.username=requested_username and u.deleted_at is null
    and (u.banned_until is null or u.banned_until <= now());
$$;
revoke all on function public.resolve_username_login(text) from public,anon,authenticated;
grant execute on function public.resolve_username_login(text) to service_role;
