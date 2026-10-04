import {PGlite} from './audit_journal/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const before=JSON.parse(fs.readFileSync(new URL('./amendment-fixtures/before.json',import.meta.url),'utf8'));
try {
await db.exec(`CREATE SCHEMA auth; CREATE SCHEMA invitation_private; CREATE SCHEMA extensions;
CREATE TABLE green_areas(id uuid primary key,rink_count int,scheme_type text,custom_labels text[],scheme_prefix text,scheme_padding int);
CREATE TABLE fixtures(id uuid primary key,green_area_id uuid,cancelled_at timestamptz,time_range tstzrange,rinks_required int,start_at timestamptz,end_at timestamptz,competition_type_id uuid,captain_member_profile_id uuid,opponent_venue_id uuid);
CREATE TABLE green_rink_maintenance(green_area_id uuid,rink_number int,status text,time_range tstzrange,reason text,start_at timestamptz,end_at timestamptz);
CREATE TABLE fixture_rinks(id uuid,fixture_id uuid,home_rink_label text);
CREATE TABLE competition_types(id uuid,name text,is_internal boolean,colour_scheme_id uuid);
CREATE TABLE fixture_colour_schemes(id uuid,background_hex text,foreground_hex text);
CREATE TABLE member_profiles(id uuid,user_id uuid,first_name text,last_name text);
CREATE TABLE venues(id uuid,name text);
CREATE TABLE auth.users(id uuid,encrypted_password text,last_sign_in_at timestamptz);
CREATE TABLE club_memberships(club_id uuid,member_profile_id uuid,is_active boolean);
CREATE TABLE invitation_private.imported_accounts(user_id uuid,club_id uuid,password_fingerprint text);
-- Only the crypt primitive is stubbed: tests cover routine eligibility, not hashing.
CREATE FUNCTION extensions.crypt(text,text) RETURNS text LANGUAGE sql AS $$ SELECT $1 $$;`);
for(const f of before)await db.exec(f.definition);
for(const f of before){const r=(await db.query(`SELECT pg_get_functiondef(p.oid) AS definition,md5(pg_get_functiondef(p.oid)) AS hash FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=$1 AND p.proname=$2`,[f.schema,f.name])).rows[0];assert.equal(r.hash,f.hash,`${f.name} baseline fidelity`);}
const green='11111111-1111-4111-8111-111111111111';
await db.exec(`INSERT INTO green_areas VALUES('${green}',6,'numeric',null,'R',0)`);
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
async function fixture(n,start,end,rinks,cancelled=false){await db.exec(`INSERT INTO fixtures(id,green_area_id,start_at,end_at,time_range,rinks_required,cancelled_at) VALUES('${id(n)}','${green}','2030-10-12 ${start}Z','2030-10-12 ${end}Z',tstzrange('2030-10-12 ${start}Z','2030-10-12 ${end}Z','[)'),${rinks},${cancelled?"now()":"null"})`);}
async function capacity(start,end){return (await db.query(`SELECT capacity_booked_rinks FROM get_green_rink_availability('${green}','2030-10-12 ${start}Z','2030-10-12 ${end}Z',null) LIMIT 1`)).rows[0].capacity_booked_rinks;}
await fixture(1,'09:00','11:10',3);await fixture(2,'11:10','13:40',5);await fixture(3,'09:30','12:30',1);await fixture(4,'13:45','16:15',6);
assert.equal(await capacity('09:30','12:30'),9,'reproduce original regression');
await db.exec(fs.readFileSync(new URL('../../supabase/migrations/20261004203050_restore_production_amendments.sql',import.meta.url),'utf8'));
assert.equal(await capacity('09:30','12:30'),6);
assert.equal(await capacity('13:00','14:00'),6);
assert.equal(await capacity('13:40','13:45'),0);
await db.exec(`CREATE TRIGGER capacity_check BEFORE INSERT OR UPDATE ON fixtures FOR EACH ROW EXECUTE FUNCTION check_green_area_rink_capacity()`);
await assert.rejects(fixture(5,'11:20','11:40',1),/Not enough rinks/);
await db.exec(`UPDATE fixtures SET cancelled_at=now() WHERE id='${id(3)}'`);
assert.equal(await capacity('09:30','12:30'),5);
await fixture(6,'09:30','12:30',1); // valid after cancellation, despite sequential sessions
await db.exec(`UPDATE fixtures SET rinks_required=1 WHERE id='${id(6)}'`); // self exclusion
await fixture(7,'09:30','12:30',6,true); // cancelled demand ignored by trigger
await db.exec(`INSERT INTO green_rink_maintenance VALUES('${green}',1,'active',tstzrange('2030-10-12 17:00Z','2030-10-12 18:00Z','[)'),'test','2030-10-12 17:00Z','2030-10-12 18:00Z'),('${green}',1,'active',tstzrange('2030-10-12 17:00Z','2030-10-12 18:00Z','[)'),'duplicate','2030-10-12 17:00Z','2030-10-12 18:00Z')`);
assert.equal(await capacity('16:00','18:00'),6,'sequential maintenance does not add to prior full session');
assert.equal(await capacity('17:00','18:00'),1,'duplicate maintenance counts once');
await assert.rejects(fixture(8,'17:00','18:00',6),/Not enough rinks/);
const u=id(50),m=id(51),c=id(52);
await db.exec(`INSERT INTO auth.users VALUES('${u}','test-password',null);INSERT INTO member_profiles(id,user_id) VALUES('${m}','${u}');INSERT INTO club_memberships VALUES('${c}','${m}',true)`);
async function eligible(password='test-password'){return (await db.query(`SELECT invitation_private.check_initial_password($1,$2,$3) AS ok`,[u,c,password])).rows[0].ok;}
assert.equal(await eligible(),true,'legacy account with no import record');
assert.equal(await eligible('wrong'),false);
await db.exec(`UPDATE club_memberships SET is_active=false`);assert.equal(await eligible(),false);
await db.exec(`UPDATE club_memberships SET is_active=true;UPDATE auth.users SET last_sign_in_at=now()`);assert.equal(await eligible(),false);
await db.exec(`UPDATE auth.users SET last_sign_in_at=null;INSERT INTO invitation_private.imported_accounts VALUES('${u}','${c}',md5('test-password'))`);assert.equal(await eligible(),true);
await db.exec(`UPDATE invitation_private.imported_accounts SET password_fingerprint='changed'`);assert.equal(await eligible(),false);
await db.exec(fs.readFileSync(new URL('./amendment-fixtures/recovery.sql',import.meta.url),'utf8'));
assert.equal(await capacity('09:30','12:30'),9,'recovery restores original routine');
await db.exec(fs.readFileSync(new URL('../../supabase/migrations/20261004203050_restore_production_amendments.sql',import.meta.url),'utf8'));
assert.equal(await capacity('09:30','12:30'),6,'reapply succeeds');
console.log('PASS: original bug reproduced; peak usage; boundaries; valid bookings; excess rejection; cancellation; self exclusion; maintenance; legacy/imported password eligibility; recovery and reapply.');
} catch(e) {console.error(e.message);process.exitCode=1;} finally {await db.close();}
