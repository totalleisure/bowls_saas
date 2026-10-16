-- Private, owner-managed avatars. Club-directory sharing is not enabled by default.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photos','profile-photos',false,5242880,array['image/png'])
on conflict(id) do nothing;

create table public.account_photos (
  user_id uuid primary key references auth.users(id) on delete cascade,
  object_path text,
  updated_at timestamptz not null default now(),
  constraint account_photo_path check(object_path is null or (
    split_part(object_path,'/',1)=user_id::text
    and object_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.png$'))
);
alter table public.account_photos enable row level security;
revoke all on public.account_photos from public,anon,authenticated;
grant select on public.account_photos to authenticated;
create policy account_photos_read_own on public.account_photos
for select to authenticated using(user_id=(select auth.uid()));

create function public.set_account_photo(expected_path text, new_path text) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); current_path text;
begin
  if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text,1));
  select object_path into current_path from public.account_photos where user_id=actor;
  if current_path is distinct from expected_path then raise exception 'Photo changed. Reload and try again.' using errcode='40001'; end if;
  if new_path is not null and (
    split_part(new_path,'/',1) <> actor::text
    or new_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.png$'
    or not exists(select 1 from storage.objects where bucket_id='profile-photos' and name=new_path)
  ) then raise exception 'Invalid photo' using errcode='22023'; end if;
  insert into public.account_photos(user_id,object_path) values(actor,new_path)
  on conflict(user_id) do update set object_path=excluded.object_path,updated_at=now();
end;
$$;
revoke all on function public.set_account_photo(text,text) from public,anon;
grant execute on function public.set_account_photo(text,text) to authenticated;

create policy profile_photo_select on storage.objects for select to authenticated
using(bucket_id='profile-photos' and split_part(name,'/',1)=(select auth.uid())::text);
create policy profile_photo_insert on storage.objects for insert to authenticated
with check(bucket_id='profile-photos' and split_part(name,'/',1)=(select auth.uid())::text
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.png$');
-- Versioned uploads deliberately have no overwrite policy.
create policy profile_photo_delete on storage.objects for delete to authenticated
using(bucket_id='profile-photos' and split_part(name,'/',1)=(select auth.uid())::text
  and not exists(select 1 from public.account_photos p where p.user_id=(select auth.uid()) and p.object_path=name));
