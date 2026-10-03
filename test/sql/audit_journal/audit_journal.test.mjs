import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();
const schema=JSON.parse(await fs.readFile(new URL('./schema.json',import.meta.url),'utf8'));
await db.exec(`create role anon; create role authenticated; create role service_role;
create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
create function auth.role() returns text language sql as $$ select nullif(current_setting('test.role',true),'') $$;
grant usage on schema auth to authenticated,anon,service_role; grant execute on all functions in schema auth to authenticated,anon,service_role;`);
for(const table of new Set(schema.map(c=>c.table_name))){
 const cols=schema.filter(c=>c.table_name===table).map(c=>`"${c.column_name}" ${c.data_type==='USER-DEFINED'?'text':c.data_type==='ARRAY'?'text[]':c.data_type==='timestamp with time zone'?'timestamptz':c.data_type==='timestamp without time zone'?'timestamp':c.data_type}`).join(',');
 await db.exec(`create table public.${table} (${cols});`);
}
// fixture_rsvps predates the migration history represented by this harness.
await db.exec(`create table public.fixture_rsvps (
  id uuid, fixture_id uuid, member_profile_id uuid, status text,
  responded_at timestamptz
);`);
await db.exec(`alter table public.fixtures add column created_by_user_id uuid;`);
await db.exec(`create function public.can_manage_fixture(uuid) returns boolean language sql as $$ select auth.uid()='00000000-0000-0000-0000-000000000001'::uuid $$;
alter table public.fixtures enable row level security; create policy fixtures_read on public.fixtures for select to authenticated using(true);
grant select on public.app_superusers,public.fixtures to authenticated;`);
await db.exec(await fs.readFile(new URL('../../../supabase/migrations/20260920215825_durable_audit_journal.sql',import.meta.url),'utf8'));
await db.exec(await fs.readFile(new URL('../../../supabase/migrations/20260922154703_correct_audit_selection_delete_event.sql',import.meta.url),'utf8'));
await db.exec(await fs.readFile(new URL('../../../supabase/migrations/20260922195312_simplify_fixture_deletion_remove_archiving.sql',import.meta.url),'utf8'));
await db.exec(await fs.readFile(new URL('../../../supabase/migrations/20260923002205_audit_fixture_rsvp_changes.sql',import.meta.url),'utf8'));
const admin='00000000-0000-0000-0000-000000000001',member='00000000-0000-0000-0000-000000000002',club='00000000-0000-0000-0000-000000000003',fixture='00000000-0000-0000-0000-000000000004';
const count=async()=>Number((await db.query('select count(*) as n from public.audit_journal')).rows[0].n);
await db.exec(`insert into public.app_superusers values('${admin}'); insert into public.member_profiles(id,user_id,first_name,last_name) values('${admin}','${admin}','Audit','Admin'); insert into public.clubs(id,name) values('${club}','Test club'); select set_config('test.uid','${admin}',false); select set_config('test.role','authenticated',false);`);
await db.exec(`insert into public.fixtures(id,club_id,team_name,start_at,end_at) values('${fixture}','${club}','Friendly','2026-10-10T10:00Z','2026-10-10T12:00Z')`);
const rsvp='00000000-0000-0000-0000-000000000005';
await db.exec(`insert into public.fixture_rsvps(id,fixture_id,member_profile_id,status,responded_at) values('${rsvp}','${fixture}','${member}','yes',now()); update public.fixture_rsvps set status='maybe',responded_at=now() where id='${rsvp}'`);
let rsvpAudit=(await db.query("select action,record_label,before_values,after_values from public.audit_journal where record_type='fixture_rsvps' order by id")).rows;
assert.deepEqual(rsvpAudit.map(r=>r.action),['insert','update'],'RSVP insert and response change audited');
assert.match(rsvpAudit[1].record_label,/Friendly/);
assert.equal(rsvpAudit[1].before_values.status,'yes');
assert.equal(rsvpAudit[1].after_values.status,'maybe');
await db.exec(`delete from public.fixture_rsvps where id='${rsvp}'`);
assert.equal((await db.query("select action from public.audit_journal where record_type='fixture_rsvps' order by id desc limit 1")).rows[0].action,'delete');
let n=await count(); await db.exec(`update public.fixtures set team_name=team_name where id='${fixture}'`); assert.equal(await count(),n,'no-op suppressed');
await db.exec(`update public.fixtures set start_at='2026-10-11T10:00Z' where id='${fixture}'`);
assert.equal((await db.query("select action from public.audit_journal order by id desc limit 1")).rows[0].action,'rescheduled');
await db.exec('set role authenticated');
assert.equal((await db.query('select count(*)::int as n from public.fixtures')).rows[0].n,1,'fixture remains visible');
assert.ok((await db.query('select count(*)::int as n from public.audit_journal')).rows[0].n>0);
await assert.rejects(db.exec("delete from public.audit_journal"),/permission denied/);
await db.exec(`select set_config('test.uid','${member}',false)`);
assert.equal((await db.query('select count(*)::int as n from public.audit_journal')).rows[0].n,0,'ordinary member denied');
await assert.rejects(db.exec('select public.audit_filter_options()'),/Superuser/);
await db.exec(`select set_config('test.uid','${admin}',false)`);
await db.exec('reset role');
await assert.rejects(db.exec(`delete from public.fixtures where id='${fixture}'`),/audited fixture deletion/);
await assert.rejects(db.exec(`select * from public.admin_force_delete_fixture('${fixture}','DELETE FIXTURE')`),/Permanent deletion/);
await db.exec(`insert into public.member_invitation_attempts(id,club_id,html,preview,status) values('00000000-0000-0000-0000-000000000009','${club}','secret-password','{"password":"secret-password"}','sent')`);
assert.ok(!JSON.stringify((await db.query('select * from public.audit_journal')).rows).includes('secret-password'));
await db.exec(`insert into public.feature_revision_policy(id,enabled_revision) values(true,1); update public.feature_revision_policy set enabled_revision=2 where id=true`);
await assert.rejects(db.exec('update public.audit_journal set actor_name=\'tamper\''),/cannot be changed/);
await assert.rejects(db.exec('truncate public.audit_journal'),/cannot be changed/);
n=await count(); await db.exec(`begin; update public.fixtures set team_name='rolled back' where id='${fixture}'; rollback;`);assert.equal(await count(),n,'rollback not logged as success');
// Publication, team deletion and service attribution are exercised against SQL, not source matching.
await db.exec(`select set_config('test.uid','${admin}',false); select set_config('test.role','authenticated',false);
insert into public.team_selections(id,fixture_id,status) values('00000000-0000-0000-0000-000000000010','${fixture}','draft');
update public.team_selections set status='published' where id='00000000-0000-0000-0000-000000000010';`);
assert.equal((await db.query("select action from public.audit_journal order by id desc limit 1")).rows[0].action,'published');
await db.exec(`insert into public.teams(id,club_id,name) values('00000000-0000-0000-0000-000000000011','${club}','Test team'); delete from public.teams where id='00000000-0000-0000-0000-000000000011'`);
assert.equal((await db.query("select record_label from public.audit_journal order by id desc limit 1")).rows[0].record_label,'Test team');
await db.exec(`set role authenticated`);
await assert.rejects(db.query('select public.audit_member_import($1,$2,$3,$4)',[admin,club,'members.csv',false]),/permission denied/);
await db.exec(`reset role; select set_config('test.uid','',false); select set_config('test.role','service_role',false); set role service_role`);
await assert.rejects(db.query('select public.audit_member_import($1,$2,$3,$4)',[member,club,'members.csv',false]),/administrator/);
const run=(await db.query('select public.audit_member_import($1,$2,$3,$4) as id',[admin,club,'members.csv',false])).rows[0].id;
await db.query('select public.audit_member_import($1,$2,$3,$4,$5,$6)',[admin,club,'members.csv',false,run,{created:2,errors:0,password:'never retain'}]);
await assert.rejects(db.query('select public.audit_member_import($1,$2,$3,$4,$5,$6)',[admin,club,'members.csv',false,run,{created:2}]),/not found/);
await db.exec('reset role');
const summary=(await db.query("select * from public.audit_journal where record_type='member_import' order by id desc limit 1")).rows[0];
assert.equal(summary.actor_user_id,admin); assert.equal(summary.after_values.created,2); assert.ok(!JSON.stringify(summary).includes('never retain'));
await db.exec(`update public.member_invitation_attempts set created_by='${admin}',status='failed' where id='00000000-0000-0000-0000-000000000009'`);
const invitation=(await db.query("select * from public.audit_journal order by id desc limit 1")).rows[0];
assert.equal(invitation.actor_user_id,admin);assert.equal(invitation.outcome,'failed');

await db.exec(`select set_config('test.uid','',false); select set_config('test.role','',false); select set_config('app.audit_delete_mode','ordinary',false); delete from public.fixtures where id='${fixture}'; delete from public.member_profiles where user_id='${admin}';`);
assert.ok((await db.query(`select actor_name from public.audit_journal where record_id='${fixture}' and actor_user_id='${admin}'`)).rows.every(r=>r.actor_name==='Audit Admin'),'actor name retained');
assert.equal((await db.query(`select count(*)::int as n from public.audit_journal where record_id='${fixture}' and action='delete'`)).rows[0].n,1,'maintenance delete survives');
console.log('PASS: trigger capture, no-op suppression, reschedule, legacy deletion guards, member denial, immutable audit, secrets excluded, numeric IDs, rollback and retained actor identity.');
// Exercise all three trigger operations on every audited table in this isolated database.
const auditSpecs = [
  ['fixtures', {id: null, club_id: club, team_name: 'Audit fixture', start_at: '2026-11-01T10:00Z', end_at: '2026-11-01T12:00Z'}, 'team_name', 'Changed fixture'],
  ['teams', {id: null, club_id: club, name: 'Audit team'}, 'name', 'Changed team'],
  ['team_members', {id: null, team_id: fixture, member_profile_id: member, is_active: true}, 'is_active', false],
  ['team_selections', {id: null, fixture_id: fixture, status: 'draft'}, 'status', 'published'],
  ['team_selection_members', {id: null, team_selection_id: fixture, member_profile_id: member, is_selected: true}, 'is_selected', false],
  ['fixture_rink_assignments', {id: null, fixture_id: fixture, member_profile_id: member, display_name: 'Audit player'}, 'display_name', 'Changed player'],
  ['club_memberships', {id: null, club_id: club, member_profile_id: member, role: 'member', is_active: true}, 'is_active', false],
  ['member_profiles', {id: null, user_id: member, first_name: 'Audit', last_name: 'Member'}, 'first_name', 'Changed'],
  ['app_superusers', {user_id: null}, 'user_id', null],
  ['clubs', {id: null, name: 'Audit club'}, 'name', 'Changed club'],
  ['club_schedule_items', {id: null, club_id: club, title: 'Audit diary'}, 'title', 'Changed diary'],
  ['member_invitation_attempts', {id: null, club_id: club, user_id: member, status: 'pending'}, 'status', 'sent'],
  ['email_queue', {id: null, fixture_id: fixture, member_profile_id: member, status: 'pending'}, 'status', 'sent'],
  ['feature_revision_policy', {id: false, enabled_revision: 1}, 'enabled_revision', 2],
];
for (let i = 0; i < auditSpecs.length; i++) {
  const [table, seed, updateColumn, updateValueRaw] = auditSpecs[i];
  const id = `00000000-0000-0000-0000-${String(500 + i).padStart(12, '0')}`;
  const row = Object.fromEntries(Object.entries(seed).map(([k, v]) => [k, v === null ? id : v]));
  const key = table === 'app_superusers' ? 'user_id' : 'id';
  const before = (await db.query('select action from public.audit_journal where record_type=$1 order by id', [table])).rows.length;
  const columns = Object.keys(row);
  await db.query(`insert into public.${table} (${columns.join(',')}) values (${columns.map((_, j) => `$${j + 1}`).join(',')})`, Object.values(row));
  const updateValue = updateValueRaw === null ? `00000000-0000-0000-0000-${String(600 + i).padStart(12, '0')}` : updateValueRaw;
  await db.query(`update public.${table} set ${updateColumn}=$1 where ${key}=$2`, [updateValue, row[key]]);
  const currentKey = updateColumn === key ? updateValue : row[key];
  await db.query(`delete from public.${table} where ${key}=$1`, [currentKey]);
  const events = (await db.query('select action from public.audit_journal where record_type=$1 order by id', [table])).rows.slice(before).map(r => r.action);
  assert.deepEqual(events, ['insert', table === 'team_selections' ? 'published' : 'update', 'delete'], `${table}: insert/update/delete audit path`);
}
console.log('PASS: insert, meaningful update and delete audit entries for all 14 original audited tables plus fixture RSVPs.');
await db.exec(`select set_config('test.uid','${admin}',false); select set_config('test.role','authenticated',false);`);
await db.query('select public.record_audit_export($1)', [42]);
const exportEntry = (await db.query("select action,after_values from public.audit_journal where record_type='audit_journal' order by id desc limit 1")).rows[0];
assert.equal(exportEntry.action, 'export requested');
assert.equal(exportEntry.after_values.row_count, 42);
await db.exec(`select set_config('test.uid','${member}',false)`);
await assert.rejects(db.query('select public.record_audit_export($1)', [1]), /Superuser/);
console.log('PASS: audit export records count and denies ordinary members.');
await db.close();
