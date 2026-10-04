import {PGlite} from './audit_journal/node_modules/@electric-sql/pglite/dist/index.js';
import {btree_gist} from './audit_journal/node_modules/@electric-sql/pglite/dist/contrib/btree_gist.js';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite({extensions:{btree_gist}});
const root=new URL('../../',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1');
const baseline=process.argv[2];
if (!baseline) throw new Error('Pass the path to the production-shaped rehearsal-baseline.sql (synthetic schema only).');
try {
await db.exec('CREATE ROLE supabase_admin; CREATE EXTENSION btree_gist;');
await db.exec(fs.readFileSync(baseline,'utf8'));
await db.exec("SET bowls.release_155_approved='yes'");
await db.exec(fs.readFileSync(root+'docs/releases/1.5.5/database-deployment/20261003110620_release_155_production_backend.sql','utf8'));
await db.exec(fs.readFileSync(root+'supabase/migrations/20261004023022_fix_fixture_creator_lifecycle.sql','utf8'));
const u='11111111-1111-4111-8111-111111111111',m='22222222-2222-4222-8222-222222222222',c='33333333-3333-4333-8333-333333333333';
const other='44444444-4444-4444-8444-444444444444',om='55555555-5555-4555-8555-555555555555';
await db.exec(`INSERT INTO auth.users(id,email) VALUES('${u}','owner@example.invalid'),('${other}','other@example.invalid');
INSERT INTO public.member_profiles(id,user_id,display_name) VALUES('${m}','${u}','Owner'),('${om}','${other}','Other');
INSERT INTO public.clubs(id,name) VALUES('${c}','Synthetic creator test');
INSERT INTO public.club_memberships(club_id,member_profile_id,is_active,role) VALUES('${c}','${m}',true,'member'),('${c}','${om}',true,'member');
SELECT set_config('test.uid','${u}',false); SELECT set_config('test.role','authenticated',false);`);
const v=(await db.query(`INSERT INTO public.venues(club_id,name,is_home_venue) VALUES('${c}','Away venue',false) RETURNING id`)).rows[0].id;
async function fixture(){return (await db.query(`INSERT INTO public.fixtures(club_id,start_at,end_at,is_home,venue_id,rinks_required,players_per_rink) VALUES('${c}','2030-01-01 10:00Z','2030-01-01 12:00Z',false,'${v}',1,4) RETURNING id`)).rows[0].id;}
const f=await fixture(),g=await fixture();
// Synthetic label: bypass local-only rink triggers to isolate transaction rollback.
await db.exec(`ALTER TABLE public.fixture_rinks DISABLE TRIGGER USER;
INSERT INTO public.fixture_rinks(fixture_id,fixture_rink_no,format,players_per_rink,home_rink_label) VALUES('${f}',1,'fours',4,'1');
ALTER TABLE public.fixture_rinks ENABLE TRIGGER USER;
CREATE FUNCTION public.test_reject_time() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
IF NEW.start_at='2030-01-01 15:00Z'::timestamptz THEN RAISE EXCEPTION 'Synthetic booking conflict'; END IF; RETURN NEW; END $$;
CREATE TRIGGER test_reject_time BEFORE UPDATE ON public.fixtures FOR EACH ROW EXECUTE FUNCTION public.test_reject_time();`);
await db.exec('SET ROLE authenticated');
await assert.rejects(db.query(`SELECT public.change_fixture_time_safe('${f}','2030-01-01 15:00Z','2030-01-01 17:00Z','2030-01-01 10:00Z','2030-01-01 12:00Z')`),/Synthetic booking conflict/);
await db.exec('RESET ROLE');
assert.equal((await db.query(`SELECT home_rink_label FROM public.fixture_rinks WHERE fixture_id='${f}'`)).rows[0].home_rink_label,'1');
assert.equal(new Date((await db.query(`SELECT start_at FROM public.fixtures WHERE id='${f}'`)).rows[0].start_at).getUTCHours(),10);
await db.exec('SET ROLE authenticated');
await db.query(`SELECT public.change_fixture_time_safe('${f}','2030-01-01 11:00Z','2030-01-01 13:00Z','2030-01-01 10:00Z','2030-01-01 12:00Z')`);
assert.equal(new Date((await db.query(`SELECT start_at FROM public.fixtures WHERE id='${f}'`)).rows[0].start_at).getUTCHours(),11);
await db.exec('RESET ROLE');
assert.equal((await db.query(`SELECT home_rink_label FROM public.fixture_rinks WHERE fixture_id='${f}'`)).rows[0].home_rink_label,null);
await db.exec('SET ROLE authenticated');
async function denied(sql,pattern){await assert.rejects(db.query(sql),pattern);}
await denied(`SELECT public.change_fixture_time_safe('${f}','2030-01-01 12:00Z','2030-01-01 14:00Z','2030-01-01 10:00Z','2030-01-01 12:00Z')`,/has changed/);
await db.exec(`RESET ROLE;SELECT set_config('test.uid','${other}',false);SET ROLE authenticated;`);
await denied(`SELECT public.change_fixture_time_safe('${f}','2030-01-01 12:00Z','2030-01-01 14:00Z','2030-01-01 11:00Z','2030-01-01 13:00Z')`,/permission/);
await denied(`SELECT public.cancel_fixture_safe('${f}',NULL)`,/permission/);
await db.exec(`RESET ROLE;SELECT set_config('test.uid','${u}',false);SET ROLE authenticated;`);
await db.query(`SELECT public.cancel_fixture_safe('${f}',NULL)`);
await db.exec(`RESET ROLE;SELECT set_config('test.uid','${other}',false);SET ROLE authenticated;`);
await denied(`SELECT public.reschedule_cancelled_fixture_safe('${f}','2030-01-02 11:00Z','2030-01-02 13:00Z')`,/permission/);
await db.exec(`RESET ROLE;SELECT set_config('test.uid','${u}',false);SET ROLE authenticated;`);
const replacement=(await db.query(`SELECT public.reschedule_cancelled_fixture_safe('${f}','2030-01-02 11:00Z','2030-01-02 13:00Z') id`)).rows[0].id;
assert.equal((await db.query(`SELECT created_by_user_id FROM public.fixtures WHERE id='${replacement}'`)).rows[0].created_by_user_id,u);
await denied(`SELECT public.reschedule_cancelled_fixture_safe('${f}','2030-01-03 11:00Z','2030-01-03 13:00Z')`,/already been rescheduled/);
await db.query(`SELECT public.cancel_and_reschedule_fixture_safe('${g}','2030-01-04 11:00Z','2030-01-04 13:00Z',NULL)`);
await db.exec(`RESET ROLE;UPDATE public.club_memberships SET is_active=false WHERE member_profile_id='${m}';SET ROLE authenticated;`);
await denied(`SELECT public.cancel_fixture_safe('${replacement}',NULL)`,/permission/);
await db.exec(`RESET ROLE;UPDATE public.club_memberships SET is_active=true,role='guest' WHERE member_profile_id='${m}';SET ROLE authenticated;`);
await denied(`SELECT public.cancel_fixture_safe('${replacement}',NULL)`,/permission/);
console.log('PASS: creator time persistence, stale edit rejection, unrelated member denied, optional cancellation reason, creator reschedule, replacement ownership, duplicate reschedule rejection, combined cancel/reschedule, inactive and guest denied.');
} catch(e){ console.error(e.message); process.exitCode=1; } finally {await db.close();}
