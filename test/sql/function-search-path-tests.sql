begin;
create temp table path_results(test text,passed boolean);
create temp table stamp_test(updated_at timestamptz);
create trigger stamp before insert on stamp_test for each row execute function public.set_updated_at();
create temp table touch_test(updated_at timestamptz);
create trigger touch before insert on touch_test for each row execute function public.touch_updated_at();
create temp table range_test(start_at timestamptz,end_at timestamptz,time_range tstzrange);
create trigger range_set before insert on range_test for each row execute function public.set_fixture_time_range();
create temp table immutable_test(id integer);
create trigger imm before update or delete on immutable_test for each row execute function audit_private.immutable();
insert into stamp_test values(null);
insert into touch_test values(null);
insert into range_test(start_at) values('2030-01-01 12:00Z');
insert into immutable_test values(1);
insert into path_results select 'set_updated_at trigger',updated_at=now() from stamp_test;
insert into path_results select 'touch_updated_at trigger',updated_at=now() from touch_test;
insert into path_results select 'default four hour range',time_range=tstzrange('2030-01-01 12:00Z','2030-01-01 16:00Z','[)') from range_test;
do $$
declare denied boolean:=false; a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); pa uuid; pb uuid; c uuid:=gen_random_uuid(); f uuid;
begin
 begin update immutable_test set id=2; exception when raise_exception then denied:=sqlerrm='Audit entries cannot be changed or removed'; end;
 insert into path_results values('audit immutability preserved',denied);
 insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data) values
 (a,a::text||'@example.invalid','{"display_name":"Path test admin"}','{}'),
 (b,b::text||'@example.invalid','{"display_name":"Path test member"}','{}');
 select id into pa from public.member_profiles where user_id=a;
 select id into pb from public.member_profiles where user_id=b;
 insert into path_results values('new user profile trigger',pa is not null and pb is not null);
 insert into public.clubs(id,name) values(c,'ROLLBACK search path');
 insert into public.club_memberships(club_id,member_profile_id,role,is_active) values(c,pa,'admin',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 if public.add_member_to_club_by_email(c,b::text||'@example.invalid')<>pb then raise exception 'Member addition failed'; end if;
 insert into path_results values('authorised membership addition',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
 denied:=false;
 begin perform public.add_member_to_club_by_email(c,a::text||'@example.invalid'); exception when raise_exception then denied:=sqlerrm='Not authorized'; end;
 insert into path_results values('ordinary member addition denied',denied);
 select id into f from public.fixtures limit 1;
 update public.fixtures set captain_member_profile_id=pb where id=f;
 insert into path_results values('captain helper finds caller',public.is_fixture_captain(f));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 insert into path_results values('captain helper rejects other caller',not public.is_fixture_captain(f));
 if exists(select 1 from path_results where not passed) then raise exception 'Search path tests failed'; end if;
end $$;
select * from path_results;
rollback;
