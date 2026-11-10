-- Synthetic member fixtures only. Run in a transaction and roll back.
do $$
declare club uuid; ft uuid; green uuid; label text; f uuid; rink uuid; selection uuid;
 u uuid:=gen_random_uuid(); opponent_user uuid:=gen_random_uuid(); actor uuid; opponent uuid;
 original_label text; data jsonb; denied boolean; setup_match uuid:=gen_random_uuid();
begin
 select ct.club_id,ct.id into strict club,ft from public.competition_types ct
 where ct.is_active and ct.is_internal and ct.bookable_by_members and ct.uses_rinks
 and ct.team_selection_enabled and ct.selection_mode='preselect' limit 1;
 select ga.id into strict green from public.green_areas ga join public.venues v on v.id=ga.venue_id
 where ga.club_id=club and v.is_home_venue and ga.rink_count>0 limit 1;
 select rink_label into strict label from public.get_green_rink_availability(green,'2041-01-14 10:00Z','2041-01-14 12:30Z')
 where not is_booked and free_capacity_rinks>0 limit 1;
 insert into auth.users(id,email,raw_user_meta_data) values
 (u,'maintenance-'||u||'@example.invalid','{"first_name":"Synthetic","last_name":"Captain"}'),
 (opponent_user,'maintenance-'||opponent_user||'@example.invalid','{"first_name":"Synthetic","last_name":"Opponent"}');
 select id into strict actor from public.member_profiles where user_id=u;
 select id into strict opponent from public.member_profiles where user_id=opponent_user;
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(club,actor,'member',true),(club,opponent,'member',true);
 perform set_config('request.jwt.claim.sub',u::text,true);
 execute 'set local role authenticated';
 f:=public.create_member_rink_booking(club,ft,green,'2041-01-14 10:00Z',label);
 select team_name into original_label from public.fixtures where id=f;
 data:=public.save_fixture_label_safe(f,'Synthetic revised booking',original_label,array['greys']);
 if data->>'team_name'<>'Synthetic revised booking' then raise exception 'Label response mismatch'; end if;
 denied:=false;
 begin perform public.save_fixture_label_safe(f,'Stale overwrite',original_label,null);
 exception when others then if sqlerrm not like '%label has changed%' then raise;end if;denied:=true;end;
 if not denied then raise exception 'Stale label overwrite accepted';end if;
 perform public.change_fixture_time_safe(f,'2041-01-15 11:00Z','2041-01-15 13:30Z','2041-01-14 10:00Z','2041-01-14 12:30Z');
 if not exists(select 1 from public.fixtures where id=f and team_name='Synthetic revised booking' and dress_code::text[]=array['greys'] and start_at='2041-01-15 11:00Z') then raise exception 'Time change lost label/dress';end if;
 execute 'reset role';
 select id into rink from public.fixture_rinks where fixture_id=f;
 select id into selection from public.team_selections where fixture_id=f;
 insert into public.fixture_rink_assignments(fixture_id,fixture_rink_id,member_profile_id,position) values(f,rink,opponent,101);
 insert into public.team_selection_members(team_selection_id,member_profile_id,role,acceptance,is_selected) values(selection,opponent,'opponent','accepted',true);
 perform set_config('request.jwt.claim.sub',opponent_user::text,true);
 denied:=false;
 begin perform public.save_fixture_label_safe(f,'Opponent overwrite','Synthetic revised booking',null);
 exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Opponent can change label';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 begin
  insert into scorecard_private.fixture_matches(id,fixture_id,club_id) values(setup_match,f,club);
  insert into scorecard_private.fixture_rink_setups(match_id,fixture_rink_id,source_snapshot,conditions,created_by) values(setup_match,rink,'{}','{}',u);
  data:=public.fixture_deletion_preview(f);
  if (data->>'can_delete')::boolean then raise exception 'Prepared scorecard deletion allowed';end if;
  -- Roll back this temporary setup using a subtransaction, without deleting
  -- any stored scorecard setup records.
  raise sqlstate 'ZP001' using message='Rollback synthetic setup';
 exception when sqlstate 'ZP001' then null;
 end;
 update public.fixtures set fixture_type='competition' where id=f;
 data:=public.fixture_deletion_preview(f);
 if (data->>'can_delete')::boolean then raise exception 'Competition fixture deletion allowed';end if;
 update public.fixtures set fixture_type='friendly' where id=f;
 execute 'set local role authenticated';
 data:=public.fixture_deletion_preview(f);
 if not (data->>'can_delete')::boolean or not (data->>'captain_member_delete')::boolean then raise exception 'Captain cannot delete attached-player booking';end if;
 perform public.delete_fixture(f,'Synthetic cleanup verification');
 execute 'reset role';
 if exists(select 1 from public.fixtures where id=f) then raise exception 'Deleted fixture retained';end if;
 if not exists(select 1 from public.audit_journal where fixture_id=f and action='delete') then raise exception 'Deletion audit missing';end if;
 if (select count(*) from public.notification_queue where event_type='fixture_cancelled' and payload->>'deleted_fixture_id'=f::text and fixture_id is null)<>1 then raise exception 'Expected one surviving cancellation notice';end if;
 if has_function_privilege('anon','public.save_fixture_label_safe(uuid,text,text,text[])','execute') then raise exception 'Anonymous label mutation grant';end if;
end $$;
