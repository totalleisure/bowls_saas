begin;
create temp table diagnostic_results(test text,passed boolean);
grant insert,select on diagnostic_results to anon,authenticated,service_role;
do $$
declare r text; op text; denied boolean;
begin
 foreach r in array array['anon','authenticated'] loop
  perform set_config('request.jwt.claims','{}',true);
  execute format('set local role %I',r);
  foreach op in array array[
   'select * from public.debug_member_identity_links()',
   'select * from public.admin_find_orphaned_records()',
   'select * from public.marker_volunteer_directory',
   'delete from public.marker_volunteer_directory where false',
   'delete from public.debug_login_users where false',
   'update public.debug_login_users set email=email where false'
  ] loop
   denied:=false;
   begin execute op; exception when insufficient_privilege then denied:=true; end;
   insert into diagnostic_results values(r||' denied '||op,denied);
  end loop;
  perform count(*) from public.debug_login_users;
  insert into diagnostic_results values(r||' staging picker still readable',true);
  reset role;
 end loop;
 set local role service_role;
 perform count(*) from public.debug_member_identity_links();
 perform count(*) from public.admin_find_orphaned_records();
 perform count(*) from public.marker_volunteer_directory;
 insert into diagnostic_results values('server diagnostics remain available',true);
 reset role;
 if exists(select 1 from diagnostic_results where not passed) then raise exception 'Diagnostic tests failed'; end if;
end $$;
select * from diagnostic_results;
rollback;
