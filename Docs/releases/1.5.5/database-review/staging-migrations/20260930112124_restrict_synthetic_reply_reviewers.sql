create or replace function public.claim_written_selection_reply(
  p_mailbox text, p_internet_message_id text, p_graph_message_id text,
  p_received_at timestamptz, p_response_code text, p_sender_email text,
  p_original_subject text, p_excerpt text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  cfg public.email_written_reply_settings%rowtype;
  r public.email_action_requests%rowtype;
  reply_id uuid;
  reviewer_ids uuid[];
  claimed uuid;
  member_name text;
begin
  select * into cfg from public.email_written_reply_settings where mailbox=p_mailbox;
  if not found or not cfg.enabled or p_received_at is null or p_received_at < cfg.enabled_at
    or p_received_at > now()+interval '5 minutes' or coalesce(p_internet_message_id,'')='' or coalesce(p_graph_message_id,'')=''
    or coalesce(p_excerpt,'')='' then return jsonb_build_object('status','ignored'); end if;
  -- Sender allowlist keeps staging tests from contacting real members.
  if not (lower(btrim(p_sender_email))=any(cfg.reminder_recipients)) then
    return jsonb_build_object('status','recipient_not_enabled');
  end if;
  select * into r from public.email_action_requests
  where response_code_hash=encode(extensions.digest(upper(btrim(p_response_code)),'sha256'),'hex')
    and lower(btrim(recipient_email))=lower(btrim(p_sender_email))
    and status='pending' and expires_at>now() and created_at<=p_received_at
  for update;
  if not found then return jsonb_build_object('status','no_current_request'); end if;
  if not exists (
    select 1 from public.team_selection_members m
    join public.team_selections s on s.id=m.team_selection_id
    join public.fixtures f on f.id=s.fixture_id
    join public.email_queue q on q.id=r.source_email_queue_id
    where m.id=r.target_record_id and m.member_profile_id=r.member_profile_id
      and m.is_selected and m.acceptance='pending' and s.status='published'
      and s.id=r.team_selection_id and f.id=r.fixture_id and f.club_id=r.club_id
      and f.cancelled_at is null and f.archived_at is null and f.start_at>now()
      and q.status='sent' and q.subject=p_original_subject and q.sent_at<=p_received_at
      and lower(btrim(q.recipient_email))=lower(btrim(p_sender_email))
      and exists (
        select 1 from public.fixture_rink_assignments a
        join public.fixture_rinks fr on fr.id=a.fixture_rink_id and fr.fixture_id=f.id
        where a.fixture_id=f.id and a.member_profile_id=m.member_profile_id
          and ((r.action_type='marker_assignment' and m.role::text='marker' and a.position=201)
            or (r.action_type='team_selection' and m.role::text in ('player','opponent')
              and (a.position between 1 and fr.players_per_rink or a.position between 101 and 100+fr.players_per_rink)))
      )
  ) then return jsonb_build_object('status','selection_not_pending'); end if;
  select array_agg(distinct cm.member_profile_id) into reviewer_ids
  from public.club_memberships cm
  join public.fixtures f on f.club_id=cm.club_id and f.id=r.fixture_id
  join public.team_selections s on s.id=r.team_selection_id
  where cm.is_active
    and (not exists(select 1 from public.email_queue q where q.id=r.source_email_queue_id
      and q.payload->>'written_reply_test'='true') or cm.member_profile_id=r.member_profile_id)
    and (cm.member_profile_id=any(array[
    f.captain_member_profile_id,f.vice_captain_member_profile_id,
    s.captain_member_profile_id,s.vice_captain_member_profile_id,s.published_by_member_profile_id
  ]) or cm.role::text='admin');
  if coalesce(cardinality(reviewer_ids),0)=0 then return jsonb_build_object('status','no_reviewer'); end if;
  insert into public.email_written_replies(mailbox,internet_message_id,graph_message_id,request_id,received_at)
  values(p_mailbox,p_internet_message_id,p_graph_message_id,r.id,p_received_at)
  on conflict(mailbox,internet_message_id) do nothing returning id into reply_id;
  if reply_id is null then return jsonb_build_object('status','duplicate'); end if;
  select coalesce(nullif(display_name,''),'A selected member') into member_name from public.member_profiles where id=r.member_profile_id;
  insert into public.app_notifications(member_profile_id,type,title,body,data,fixture_id,team_selection_id)
  select reviewer,'selection_written_reply','Written selection reply needs review',
    member_name || ' sent a written reply. Their selection response is still pending.' || E'\n\n' ||
    left(regexp_replace(p_excerpt,'(BWL-[A-Fa-f0-9]{12}|RSP-[A-Fa-f0-9]{48})','[response reference]','g'),1500),
    jsonb_build_object('fixture_id',r.fixture_id,'team_selection_id',r.team_selection_id,'written_reply_id',reply_id),r.fixture_id,r.team_selection_id
  from unnest(reviewer_ids) reviewer;
  -- Atomic one-time claim; delivery failures are reviewed, never blindly resent.
  insert into public.email_written_reply_reminders(target_record_id,reply_id)
  values(r.target_record_id,reply_id) on conflict(target_record_id) do nothing returning target_record_id into claimed;
  return jsonb_build_object('status','recorded','send_reminder',claimed is not null,'reply_id',reply_id,'recipient',r.recipient_email);
end;
$$;
