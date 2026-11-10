-- Separate, server-owned sender identity: Club admins cannot claim it.
create schema if not exists mailing_private;
create table mailing_private.total_leisure_messages (
 message_id uuid primary key references public.mailing_list_messages(id) on delete cascade,
 request_id uuid not null unique,
 actor_user_id uuid references auth.users(id) on delete set null,
 request_fingerprint text not null,
 result jsonb not null,
 created_at timestamptz not null default now()
);
alter table mailing_private.total_leisure_messages enable row level security;
revoke all on mailing_private.total_leisure_messages from public,anon,authenticated;

create function public.queue_total_leisure_message(p_mailing_list_id uuid,p_subject text,p_message text,
 p_send_app boolean,p_send_email boolean,p_attachments jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j jsonb; old mailing_private.total_leisure_messages; fingerprint text;
begin
 if auth.uid() is null or not public.is_app_superuser() then
  raise exception 'App superuser access required to send from Total Leisure.' using errcode='42501';
 end if;
 if p_request_id is null then raise exception 'A send request ID is required.' using errcode='22023';end if;
 fingerprint:=md5(jsonb_build_array(p_mailing_list_id,p_subject,p_message,p_send_app,p_send_email,p_attachments)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into old from mailing_private.total_leisure_messages where request_id=p_request_id;
 if found then
  if old.actor_user_id is distinct from auth.uid() or old.request_fingerprint<>fingerprint then
   raise exception 'This send request was already used for a different message.' using errcode='22023';
  end if;
  return old.result;
 end if;
 j:=public.queue_mailing_list_message_with_attachments(p_mailing_list_id,p_subject,p_message,p_send_app,p_send_email,p_attachments);
 j:=j||jsonb_build_object('sender_identity','total_leisure');
 insert into mailing_private.total_leisure_messages(message_id,request_id,actor_user_id,request_fingerprint,result)
 values((j->>'mailing_list_message_id')::uuid,p_request_id,auth.uid(),fingerprint,j);
 return j;
end $$;
revoke all on function public.queue_total_leisure_message(uuid,text,text,boolean,boolean,jsonb,uuid) from public,anon;
grant execute on function public.queue_total_leisure_message(uuid,text,text,boolean,boolean,jsonb,uuid) to authenticated;

create function public.mailing_list_email_identity(p_message_id uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from mailing_private.total_leisure_messages where message_id=p_message_id)
 then 'total_leisure' else 'club' end;
$$;
revoke all on function public.mailing_list_email_identity(uuid) from public,anon,authenticated;
grant execute on function public.mailing_list_email_identity(uuid) to service_role;
