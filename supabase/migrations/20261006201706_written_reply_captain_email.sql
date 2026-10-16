-- Add captain email review without enabling written replies or changing response acceptance.
CREATE OR REPLACE FUNCTION public.claim_written_selection_reply(p_mailbox text, p_internet_message_id text, p_graph_message_id text, p_received_at timestamp with time zone, p_response_code text, p_sender_email text, p_original_subject text, p_excerpt text, p_response_token_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  cfg public.email_written_reply_settings%rowtype;
  r public.email_action_requests%rowtype;
  reply_id uuid;
  reviewer_ids uuid[];
  claimed uuid;
  member_name text;
  review_body text;
  review_email_count integer := 0;
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
  if not ('ACCEPT'=any(r.allowed_actions) and 'DECLINE'=any(r.allowed_actions)) or
    (r.response_protocol_version=2 and (r.response_token_hash is null or p_response_token_hash is null or
      p_response_token_hash !~ '^[0-9a-f]{64}$' or p_response_token_hash<>r.response_token_hash)) or
    (r.response_protocol_version=1 and p_response_token_hash is not null) or r.response_protocol_version not in (1,2)
  then return jsonb_build_object('status','invalid_response_credentials'); end if;
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

  -- Email the highest-priority reachable reviewers: captain(s), then vice(s),
  -- publisher, then active club administrators. Synthetic tests retain the
  -- existing reviewer_ids restriction to the test member only.
  select
    'Written selection reply - review required' || chr(10) || chr(10) ||
    'Member: ' || member_name || chr(10) ||
    'Member email: ' || p_sender_email || chr(10) ||
    'Fixture: ' || coalesce(nullif(f.team_name,''),nullif(ct.name,''),'Club fixture') ||
    case when nullif(f.opponent_name,'') is not null then ' v ' || f.opponent_name else '' end || chr(10) ||
    'When: ' || to_char(f.start_at at time zone 'Europe/London','FMDay DD FMMonth YYYY HH24:MI') || ' (UK time)' || chr(10) ||
    'Venue: ' || coalesce(nullif(v.name,''),'Not specified') || chr(10) ||
    'Original selection email: ' || regexp_replace(p_original_subject,'(BWL-[A-Fa-f0-9]{12}|RSP-[A-Fa-f0-9]{48})','[response reference]','g') || chr(10) ||
    'Reply received: ' || to_char(p_received_at at time zone 'Europe/London','DD Mon YYYY HH24:MI') || ' (UK time)' || chr(10) || chr(10) ||
    'Member written reply (up to 1,500 characters):' || chr(10) ||
    '---' || chr(10) ||
    left(regexp_replace(p_excerpt,'(BWL-[A-Fa-f0-9]{12}|RSP-[A-Fa-f0-9]{48})','[response reference]','g'),1500) ||
    chr(10) || '---' || chr(10) || chr(10) ||
    'This written reply has not recorded an acceptance or decline. The selection response was still pending when this reply was processed.' ||
    chr(10) || 'Please review the reply and check the current response in the fixture before taking any action. The member can use Accept or Decline in their selection email or respond in the app.'
  into review_body
  from public.fixtures f
  left join public.competition_types ct on ct.id=f.competition_type_id
  left join public.venues v on v.id=f.venue_id
  where f.id=r.fixture_id;

  with candidates as (
    select mp.id,lower(btrim(mp.email_address)) email,
      case
        when mp.id in (f.captain_member_profile_id,s.captain_member_profile_id) then 1
        when mp.id in (f.vice_captain_member_profile_id,s.vice_captain_member_profile_id) then 2
        when mp.id=s.published_by_member_profile_id then 3
        else 4
      end priority
    from public.member_profiles mp
    join public.fixtures f on f.id=r.fixture_id
    join public.team_selections s on s.id=r.team_selection_id
    where mp.id=any(reviewer_ids) and nullif(btrim(mp.email_address),'') is not null
  ), recipients as (
    select distinct on (email) id,email
    from candidates where priority=(select min(priority) from candidates)
    order by email,id
  )
  insert into public.email_queue(member_profile_id,event_type,recipient_email,
    subject,body,payload,fixture_id,team_selection_id,attachments)
  select id,'selection_written_reply_review',email,
    'Written selection reply needs review: ' || left(member_name,120),
    review_body,jsonb_build_object('written_reply_id',reply_id,
      'fixture_id',r.fixture_id,'team_selection_id',r.team_selection_id),
    r.fixture_id,r.team_selection_id,'[]'::jsonb
  from recipients;
  get diagnostics review_email_count = row_count;

  -- Atomic one-time claim; delivery failures are reviewed, never blindly resent.
  insert into public.email_written_reply_reminders(target_record_id,reply_id)
  values(r.target_record_id,reply_id) on conflict(target_record_id) do nothing returning target_record_id into claimed;
  return jsonb_build_object('status','recorded','send_reminder',claimed is not null,'reply_id',reply_id,'recipient',r.recipient_email,'response_protocol_version',r.response_protocol_version,'review_emails_queued',review_email_count);
end;
$function$
;
