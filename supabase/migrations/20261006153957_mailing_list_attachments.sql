-- Existing clients keep the original five-argument RPC unchanged.
create schema if not exists mailing_private;
revoke all on schema mailing_private from public, anon;
grant usage on schema mailing_private to authenticated;

create or replace function mailing_private.queue_with_attachments(
 p_mailing_list_id uuid, p_subject text, p_message text,
 p_send_app boolean, p_send_email boolean, p_attachments jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 a jsonb; names text[] := '{}'; n text; data bytea; total integer := 0;
 clean jsonb := '[]'; result jsonb; updated integer;
begin
 if auth.uid() is null then raise exception 'You must be signed in.'; end if;
 if jsonb_typeof(p_attachments) is distinct from 'array' then
   raise exception 'Attachments must be a list.';
 end if;
 if jsonb_array_length(p_attachments) > 10 then
   raise exception 'You can attach up to 10 files.';
 end if;
 if jsonb_array_length(p_attachments) > 0 and not coalesce(p_send_email,false) then
   raise exception 'Enable email or remove the attachments before sending.';
 end if;
 -- Leave room for the encoded files and delivery footer in the Graph request.
 if length(p_subject) > 255 or length(p_message) > 50000 then
   raise exception 'Subject or message is too long.';
 end if;
 for a in select value from jsonb_array_elements(p_attachments) loop
   if jsonb_typeof(a) is distinct from 'object'
      or jsonb_typeof(a->'name') is distinct from 'string'
      or jsonb_typeof(a->'contentBytes') is distinct from 'string' then
     raise exception 'Invalid attachment.';
   end if;
   n := btrim(a->>'name');
   if length(n) not between 1 and 255 or n ~ '[[:cntrl:]/\\]'
      or lower(n) = any(names) then
     raise exception 'Attachment filenames must be valid and unique.';
   end if;
   names := array_append(names,lower(n));
   if length(a->>'contentBytes') > 2796204
      or (a->>'contentBytes') !~ '^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$' then
     raise exception 'Invalid attachment data or attachments exceed 2 MB.';
   end if;
   data := decode(a->>'contentBytes','base64');
   total := total + octet_length(data);
   if octet_length(data) = 0 or total > 2097152 then
     raise exception 'Attachments must be nonempty and total 2 MB or less.';
   end if;
   clean := clean || jsonb_build_array(jsonb_build_object(
     'name',n,'contentType','application/octet-stream',
     'contentBytes',replace(encode(data,'base64'),chr(10),'')
   ));
 end loop;
 -- The original routine checks active list/club-admin authorization and takes
 -- the recipient snapshot. The queue changes below commit in the same transaction.
 result := public.queue_mailing_list_message(
   p_mailing_list_id,p_subject,p_message,p_send_app,p_send_email);
 if jsonb_array_length(clean) > 0 then
   if (result->>'emails_queued')::integer = 0 then
     raise exception 'No active list members have an email address.';
   end if;
   update public.email_queue set attachments = clean
   where event_type = 'mailing_list_message'
     and payload->>'mailing_list_message_id' = result->>'mailing_list_message_id';
   get diagnostics updated = row_count;
   if updated <> (result->>'emails_queued')::integer then
     raise exception 'Attachment queue verification failed.';
   end if;
 end if;
 return result || jsonb_build_object('attachment_count',jsonb_array_length(clean));
end;
$$;
revoke all on function mailing_private.queue_with_attachments(uuid,text,text,boolean,boolean,jsonb) from public,anon;
grant execute on function mailing_private.queue_with_attachments(uuid,text,text,boolean,boolean,jsonb) to authenticated;

create or replace function public.queue_mailing_list_message_with_attachments(
 p_mailing_list_id uuid, p_subject text, p_message text,
 p_send_app boolean, p_send_email boolean, p_attachments jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
 select mailing_private.queue_with_attachments(
 p_mailing_list_id,p_subject,p_message,p_send_app,p_send_email,p_attachments);
$$;
revoke all on function public.queue_mailing_list_message_with_attachments(uuid,text,text,boolean,boolean,jsonb) from public,anon;
grant execute on function public.queue_mailing_list_message_with_attachments(uuid,text,text,boolean,boolean,jsonb) to authenticated;
notify pgrst, 'reload schema';
