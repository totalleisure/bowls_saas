import {PGlite} from './audit_journal/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const migration=fs.readFileSync(new URL('../../supabase/migrations/20261005222629_edit_open_fixture_rink_requirements.sql',import.meta.url),'utf8');
// Synthetic storage isolates the RPC. Real RLS, capacity and audit integration
// are additionally exercised in a rolled-back staging transaction.
try {
await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
GRANT USAGE ON SCHEMA auth TO authenticated;
CREATE TABLE public.competition_types(id uuid PRIMARY KEY,selection_mode text,uses_rinks boolean);
CREATE TABLE public.fixtures(id uuid PRIMARY KEY, competition_type_id uuid, rinks_required integer,players_per_rink integer,cancelled_at timestamptz,archived_at timestamptz);
CREATE TABLE public.fixture_rinks(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),fixture_id uuid REFERENCES fixtures(id),fixture_rink_no integer,home_rink_label text,format text,players_per_rink integer,marker_required boolean DEFAULT false,UNIQUE(fixture_id,fixture_rink_no));
CREATE TABLE public.fixture_rink_assignments(id uuid DEFAULT gen_random_uuid(),fixture_rink_id uuid REFERENCES fixture_rinks(id) ON DELETE CASCADE);
CREATE TABLE public.fixture_marker_requests(id uuid DEFAULT gen_random_uuid(),fixture_rink_id uuid REFERENCES fixture_rinks(id) ON DELETE CASCADE);
CREATE TABLE public.team_selections(id uuid DEFAULT gen_random_uuid(),fixture_id uuid REFERENCES fixtures(id),status text,published_at timestamptz);
CREATE TABLE public.team_selection_members(id uuid DEFAULT gen_random_uuid(),team_selection_id uuid);
CREATE FUNCTION public.can_manage_fixture(uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT current_setting('test.manager',true)='yes' $$;
CREATE FUNCTION public.is_active_fixture_creator(uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION public.test_capacity() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.rinks_required>6 THEN RAISE EXCEPTION 'Not enough rinks available'; END IF; RETURN NEW; END $$;
CREATE TRIGGER capacity BEFORE UPDATE ON fixtures FOR EACH ROW EXECUTE FUNCTION test_capacity();
SELECT set_config('test.uid','11111111-1111-4111-8111-111111111111',false);
SELECT set_config('test.manager','yes',false);
INSERT INTO competition_types VALUES('22222222-2222-4222-8222-222222222222','open',true);
INSERT INTO fixtures VALUES('33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222',4,3,null,null);
INSERT INTO fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label)
SELECT '33333333-3333-4333-8333-333333333333',i,'triples',3,case when i=1 then null else 'R'||i end FROM generate_series(1,4)i;
`);
await db.exec(migration);
await db.exec(fs.readFileSync(new URL('../../supabase/migrations/20261005223338_guard_open_fixture_selection_members.sql',import.meta.url),'utf8'));
const f='33333333-3333-4333-8333-333333333333';
async function state(){return (await db.query(`select jsonb_build_object('required',f.rinks_required,'rinks',(select jsonb_agg(to_jsonb(r) order by id) from fixture_rinks r where fixture_id=f.id)) s from fixtures f where id='${f}'`)).rows[0].s;}
async function save(n,s){
 s ??= await state();
 const snapshot=s.rinks.map(r=>({id:r.id,home_rink_label:r.home_rink_label}));
 await db.exec('SET ROLE authenticated');
 try {await db.query('select public.set_open_fixture_rinks_required($1,$2,$3,$4)',[f,n,s.required,JSON.stringify(snapshot)]);} finally {await db.exec('RESET ROLE');}
}
const original=await state();
await save(3); const reduced=await state();
assert.equal(reduced.required,3); assert.equal(reduced.rinks.length,3);
assert.deepEqual(reduced.rinks,original.rinks.filter(r=>r.home_rink_label!==null));
await assert.rejects(save(2),/Unassign a physical rink first/);
assert.deepEqual(await state(),reduced);
await assert.rejects(save(4,original),/have changed/);
await save(4); assert.equal((await state()).rinks.filter(r=>r.home_rink_label===null).length,1);
await assert.rejects(save(7),/Not enough rinks/); assert.equal((await state()).rinks.length,4);
await assert.rejects(save(0),/between 1 and 99/);
await db.exec("SELECT set_config('test.manager','no',false)"); await assert.rejects(save(3),/permission/);
await db.exec("SELECT set_config('test.manager','yes',false)");
for(const mode of ['team','rsvp','preselect']) {
 await db.query('update competition_types set selection_mode=$1',[mode]); await assert.rejects(save(3),/only.*Open/);
}
await db.exec("update competition_types set selection_mode='open'");
for(const col of ['cancelled_at','archived_at']) {
 await db.exec(`update fixtures set ${col}=now()`); await assert.rejects(save(3),/cannot be changed/); await db.exec(`update fixtures set ${col}=null`);
}
for(const table of ['fixture_rink_assignments','fixture_marker_requests']) {
 await db.exec(`insert into ${table}(fixture_rink_id) select id from fixture_rinks where home_rink_label is null`);
 await assert.rejects(save(3),/team or marker records/); assert.equal((await state()).rinks.length,4); await db.exec(`delete from ${table}`);
}
await db.exec(`insert into team_selections(fixture_id,status,published_at) values('${f}','published',now())`);
await assert.rejects(save(3),/team or marker records/); await db.exec('delete from team_selections');
await db.exec(`insert into team_selections(id,fixture_id,status) values('44444444-4444-4444-8444-444444444444','${f}','draft'); insert into team_selection_members(team_selection_id) values('44444444-4444-4444-8444-444444444444')`);
await assert.rejects(save(3),/team or marker records/); await db.exec('delete from team_selection_members; delete from team_selections');
const stale=await state();
await db.exec("update fixture_rinks set home_rink_label='R1' where home_rink_label is null");
await assert.rejects(save(3,stale),/have changed/);
await db.exec("SELECT set_config('test.uid','',false)"); await assert.rejects(save(5),/signed in/);
await db.exec('SET ROLE anon');
await assert.rejects(db.query(`select public.set_open_fixture_rinks_required('${f}',3,4,'[]')`),/permission denied/);
console.log('PASS: removal preserves assigned rows; assigned minimum; stale counts/labels; increase; capacity rollback; limits; authorization; all non-Open modes; archived/cancelled; players/markers/publication; signed-out and anonymous denied.');
} finally {await db.close();}
