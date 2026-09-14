import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
import { pathToFileURL } from 'node:url';

// Set PGLITE_MODULE to a locally installed @electric-sql/pglite dist/index.js.
// Tests run a disposable PostgreSQL engine, never the Supabase project.
const { PGlite } = await import(pathToFileURL(process.env.PGLITE_MODULE).href);
const migration = readFileSync(new URL('../../migrations/20260912005337_member_invitations.sql',import.meta.url),'utf8');
const club='11111111-1111-1111-1111-111111111111';
const caller='22222222-2222-2222-2222-222222222222';
const membership='33333333-3333-3333-3333-333333333333';
const id = n => `44444444-4444-4444-4444-${String(n).padStart(12,'0')}`;
async function setup() {
  const db=new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key);
    create table public.clubs(id uuid primary key);
    create table public.club_memberships(id uuid primary key,club_id uuid,is_active boolean);
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    insert into auth.users values('${caller}'); insert into public.clubs values('${club}');
    insert into public.club_memberships values('${membership}','${club}',true);
    grant usage on schema public to service_role; grant select,update on public.club_memberships to service_role;`);
  await db.exec(migration);
  const insert=async(n,previous=null)=>db.query(`insert into public.member_invitation_attempts(id,club_id,membership_id,created_by,email,user_id,first_name,subject,html,preview,guides,previous_sent_id) values($1,$2,$3,$4,'test@example.test',$4,'Test','Subject','<p>test</p>','{}','[]',$5)`,[id(n),club,membership,caller,previous]);
  const claim=async(n,who=caller,where=club)=>(await db.query('select public.claim_member_invitation($1,$2,$3) as claimed',[id(n),where,who])).rows[0].claimed;
  return {db,insert,claim};
}
test('migration executes and claims serialize overlapping reviews',async()=>{
  const {db,insert,claim}=await setup();
  try {
    await insert(1);await insert(2);
    const results=await Promise.all([claim(1),claim(2)]);
    assert.equal(results.filter(Boolean).length,1);
    assert.equal(await claim(1),false);
    assert.equal((await db.query("select count(*)::int as n from public.member_invitation_attempts where status='sending'")).rows[0].n,1);
  } finally {await db.close();}
});
test('sent invitation requires the exact reviewed previous attempt for resend',async()=>{
  const {db,insert,claim}=await setup();
  try {
    await insert(1);await claim(1);await db.exec(`update public.member_invitation_attempts set status='sent' where id='${id(1)}'`);
    await insert(2);assert.equal(await claim(2),false);
    await insert(3,id(1));assert.equal(await claim(3),true);
    await db.exec(`update public.member_invitation_attempts set status='sent' where id='${id(3)}'`);
    await insert(4,id(1));assert.equal(await claim(4),false);
  } finally {await db.close();}
});
test('uncertain outcomes block new attempts; failed outcomes allow a fresh review',async()=>{
  const {db,insert,claim}=await setup();
  try {
    await insert(1);await claim(1);await db.exec(`update public.member_invitation_attempts set status='unknown' where id='${id(1)}'`);
    await insert(2,id(1));assert.equal(await claim(2),false);
    await db.exec(`update public.member_invitation_attempts set status='failed' where id='${id(1)}'`);
    await insert(3);assert.equal(await claim(3),true);
  } finally {await db.close();}
});
test('claim rejects wrong owner, wrong club, inactive membership and expired review',async()=>{
  const {db,insert,claim}=await setup();
  try {
    await insert(1);
    assert.equal(await claim(1,id(9)),false);assert.equal(await claim(1,caller,id(9)),false);
    await db.exec('update public.club_memberships set is_active=false');assert.equal(await claim(1),false);
    await db.exec("update public.club_memberships set is_active=true; update public.member_invitation_attempts set created_at=now()-interval '25 hours'");
    assert.equal(await claim(1),false);
  } finally {await db.close();}
});
test('clients cannot read/write tracking or call claim; service role can claim',async()=>{
  const {db,insert,claim}=await setup();
  try {
    await insert(1);
    for(const role of ['anon','authenticated']) {
      await db.exec(`set role ${role}`);
      await assert.rejects(db.query('select * from public.member_invitation_attempts'),/permission denied/);
      await assert.rejects(claim(1),/permission denied/);
      await db.exec('reset role');
    }
    await db.exec('set role service_role');assert.equal(await claim(1),true);
  } finally {await db.close();}
});
test('account deletion is not blocked by invitation history',async()=>{
  const {db,insert,claim}=await setup();
  try {
    await insert(1);await claim(1);
    await db.exec(`update public.member_invitation_attempts set status='sent'; delete from auth.users where id='${caller}'`);
    const row=(await db.query('select status,created_by,user_id from public.member_invitation_attempts')).rows[0];
    assert.deepEqual(row,{status:'sent',created_by:null,user_id:null});
  } finally {await db.close();}
});

