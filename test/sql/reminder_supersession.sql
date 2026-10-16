begin;
do $test$
declare v record; q uuid; previous_q uuid; block jsonb;
begin
 select f.id fixture,ts.id selection,tsm.id member_row,tsm.member_profile_id,mp.email_address
 into strict v from public.fixtures f join public.team_selections ts on ts.fixture_id=f.id
 join public.team_selection_members tsm on tsm.team_selection_id=ts.id
 join public.member_profiles mp on mp.id=tsm.member_profile_id
 join public.fixture_rink_assignments fra on fra.fixture_id=f.id and fra.member_profile_id=tsm.member_profile_id
 join public.fixture_rinks fr on fr.id=fra.fixture_rink_id
 where ts.status='published' and tsm.is_selected=true and tsm.role='player'
 and fra.position between 1 and fr.players_per_rink and f.cancelled_at is null and f.start_at>now() limit 1;
 update public.team_selection_members set acceptance='pending' where id=v.member_row;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
 values(v.member_profile_id,'acceptance_reminder',v.email_address,'Test reminder','Test',v.fixture,v.selection) returning id into q;
 select payload->'action_block' into block from public.email_queue where id=q;
 assert block->>'version'='2' and jsonb_array_length(block->'actions')=2,'Reminder missing existing v2 actions';
 assert block->'actions'->0->>'command'='ACCEPT' and block->'actions'->1->>'command'='DECLINE','Commands changed';
 assert exists(select 1 from public.email_action_requests where source_email_queue_id=q and target_record_id=v.member_row),'Wrong action target';
 previous_q := q;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
 values(v.member_profile_id,'acceptance_reminder',v.email_address,'Second reminder','Test',v.fixture,v.selection) returning id into q;
 assert exists(select 1 from public.email_queue where id=previous_q and status='cancelled' and last_error is null),'Superseded unsent message not cancelled';
 assert exists(select 1 from public.email_action_requests where source_email_queue_id=previous_q and status='cancelled'),'Previous action not cancelled';
 assert exists(select 1 from public.email_action_requests where source_email_queue_id=q and status='pending'),'Latest action missing';
 update public.team_selection_members set acceptance='accepted' where id=v.member_row;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
 values(v.member_profile_id,'acceptance_reminder',v.email_address,'Test reminder','Test',v.fixture,v.selection) returning id into q;
 assert not exists(select 1 from public.email_action_requests where source_email_queue_id=q),'Answered player received action';
 update public.team_selections set status='draft' where id=v.selection;
 update public.team_selection_members set acceptance='pending' where id=v.member_row;
 insert into public.email_queue(member_profile_id,event_type,recipient_email,subject,body,fixture_id,team_selection_id)
 values(v.member_profile_id,'acceptance_reminder',v.email_address,'Test reminder','Test',v.fixture,v.selection) returning id into q;
 assert not exists(select 1 from public.email_action_requests where source_email_queue_id=q),'Draft received actions';
end $test$;
rollback;


