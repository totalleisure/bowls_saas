-- Reviewed, frozen marketing email layouts are writable only by backend operators.
create table mailing_private.approved_message_html (
 email_queue_id uuid primary key references public.email_queue(id) on delete cascade,
 html text not null check(length(html) between 1 and 200000),
 approved_at timestamptz not null default now()
);
alter table mailing_private.approved_message_html enable row level security;
revoke all on mailing_private.approved_message_html from public,anon,authenticated;
create function public.mailing_list_approved_html(p_email_queue_id uuid) returns text
language sql stable security definer set search_path='' as $$
 select h.html from mailing_private.approved_message_html h
 join public.email_queue q on q.id=h.email_queue_id
 join public.mailing_list_messages m on m.id::text=q.payload->>'mailing_list_message_id'
 where q.id=p_email_queue_id and q.event_type='mailing_list_message'
 and m.mailing_list_id::text=q.payload->>'mailing_list_id';
$$;
revoke all on function public.mailing_list_approved_html(uuid) from public,anon,authenticated;
grant execute on function public.mailing_list_approved_html(uuid) to service_role;
