import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const source = ['../_shared/member_csv.ts', './email.ts', './index.ts'].map(p => readFileSync(new URL(p, import.meta.url), 'utf8')).join('\n');
const executable = stripTypeScriptTypes(source.replace(/^import\s[\s\S]*?;\s*/gm, '').replace(/export /g, ''));
const club = '11111111-1111-1111-1111-111111111111';
const header = 'first name,last name,title,email,mobile phone,gender,outdoor club,password';
const csv = `${header}\nWayne,Example,,wayne@example.test,,Male,,not-to-be-emailed`;
const plain = v => JSON.parse(JSON.stringify(v));

function setup({ authorized = true, active = true, graphStatus = 202, lostResponse = false, csvText = csv } = {}) {
  let handler;
  const tables = {
    app_superusers: authorized ? [{ user_id: 'admin' }] : [],
    clubs: [{ id: club, name: 'Lewisham & Crystal Palace' }],
    member_profiles: [{ id: 'profile', user_id: 'user', first_name: 'Wayne', last_name: 'Example', email_address: 'wayne@example.test' }],
    club_memberships: [{ id: 'membership', club_id: club, member_profile_id: 'profile', is_active: active }],
    member_invitation_guides: ['introduction','android'].map(kind => ({ club_id: club, kind, name: `${kind}.pdf`, path: `${club}/${kind}/version1.pdf` })),
    member_invitation_attempts: [],
  };
  const calls = { sends: [], downloads: [], uploads: [], userWrites: 0, reads: 0 };
  const accounts = { user: { id: 'user', email: 'wayne@example.test' } };
  const admin = {
    auth: { getUser: async token => token === 'valid' ? { data: { user: { id: 'admin' } } } : { data: { user: null }, error: 'invalid' }, admin: { getUserById: async id => ({ data: { user: accounts[id] } }) } },
    storage: { from: bucket => ({
      download: async path => { calls.downloads.push([bucket,path]); return { data: new Blob([bucket === 'Imports' ? csvText : '%PDF-1.7 test guide']) }; },
      upload: async (path, bytes, options) => { calls.uploads.push({path,bytes,options}); return {data: {path}}; },
      createSignedUrl: async path => ({ data: { signedUrl: `https://storage.example.test/${path}` } }),
    }) },
    from: table => {
      assert.ok(table in tables, table);
      let operation = 'read', payload, cached;
      const filters = [];
      const execute = () => {
        if (cached) return cached;
        calls.reads++;
        const matches = tables[table].filter(r => filters.every(f => f(r)));
        if (operation === 'read') return cached = { data: matches };
        assert.ok(table.startsWith('member_invitation_'), 'invitation-only must not write accounts/memberships');
        if (operation === 'update') { matches.forEach(r => Object.assign(r,payload)); return cached = {data:matches}; }
        if (operation === 'upsert') {
          const match = tables[table].find(r => r.club_id === payload.club_id && r.kind === payload.kind);
          if (match) { Object.assign(match,payload); return cached = { data:[match] }; }
        }
        const record = {status:'pending', created_at:new Date().toISOString(), ...plain(payload)};
        tables[table].push(record);
        return cached = {data:[record]};
      };
      const q = {
        select: () => q, eq: (k,v) => {filters.push(r=>r[k]===v);return q;},
        ilike: (k,v) => {filters.push(r=>r[k]?.toLowerCase()===v.replace(/\\([\\%_])/g,'$1').toLowerCase());return q;},
        in: (k,v) => {filters.push(r=>v.includes(r[k]));return q;},
        insert: p => {operation='insert';payload=p;return q;},
        upsert: p => {operation='upsert';payload=p;return q;},
        update: p => {operation='update';payload=p;return q;},
        maybeSingle: async () => { const r=execute(); return r.data.length>1 ? {error:'multiple'} : {data:r.data[0]||null}; },
        single: async () => {const r=execute();return r.data.length===1?{data:r.data[0]}:{error:'missing'};},
        then: (resolve,reject) => Promise.resolve(execute()).then(resolve,reject),
      };
      return q;
    },
    // The actual database claim is tested separately against PostgreSQL/PGlite.
    rpc: async (name, args) => {
      assert.equal(name,'claim_member_invitation');
      const a=tables.member_invitation_attempts.find(r=>r.id===args.p_id && r.club_id===args.p_club && r.created_by===args.p_caller);
      const previous=tables.member_invitation_attempts.find(r=>r.membership_id===a?.membership_id && ['sending','sent','unknown'].includes(r.status));
      if (!a || a.status!=='pending' || previous && (previous.status!=='sent' || previous.id!==a.previous_sent_id)) return {data:false};
      if (previous) previous.status='superseded';
      a.status='sending'; return {data:true};
    },
  };
  const context = vm.createContext({
    Request, Response, Blob, Uint8Array, Map, Set, Date, crypto, atob, btoa, URLSearchParams, AbortSignal,
    Deno: { env: {get: ()=>'configured'}, serve: h=>handler=h }, createClient: ()=>admin,
    fetch: async (url, args) => {
      if (url.includes('oauth2')) return new Response(JSON.stringify({access_token:'mail-token'}));
      calls.sends.push(JSON.parse(args.body));
      if (lostResponse) throw new Error('response lost');
      return new Response(null,{status:graphStatus});
    },
  });
  vm.runInContext(executable,context);
  return { tables, calls, accounts, context,
    request: async (body={}, token='valid') => {
      const response=await handler(new Request('https://example.test',{method:'POST',headers:token?{Authorization:`Bearer ${token}`}:{},body:JSON.stringify({club_id:club,...body})}));
      return {status:response.status,...await response.json()};
    },
    preview: async function(resend=false) {return this.request({action:'preview',storage_path:`${club}/committee.csv`,resend});},
    send: async function(id) {return this.request({action:'send',invitation_id:id,confirm:true});},
  };
}

test('preview creates no accounts and sends no email; personalisation contains no password', async()=>{
  const s=setup(), result=await s.preview();
  assert.equal(result.status,200); assert.equal(result.recipients.length,1);
  assert.equal(s.calls.sends.length,0);
  const a=s.tables.member_invitation_attempts[0];
  assert.match(a.html,/Hello Wayne/); assert.match(a.html,/id6762380407/);
  assert.match(a.html,/Forgotten password/); assert.doesNotMatch(a.html,/not-to-be-emailed/);
  assert.equal(a.guides.length,2);
});
test('send requires explicit confirmation and sends both PDFs privately to one recipient',async()=>{
  const s=setup(), p=await s.preview(), id=p.recipients[0].id;
  assert.equal((await s.request({action:'send',invitation_id:id})).status,400);
  assert.equal(s.calls.sends.length,0);
  assert.equal((await s.send(id)).status,'sent');
  assert.equal(s.calls.sends[0].message.attachments.length,2);
  assert.deepEqual(s.calls.sends[0].message.toRecipients,[{emailAddress:{address:'wayne@example.test'}}]);
  assert.equal(s.calls.sends[0].saveToSentItems,true);
});
test('repeat send is idempotent and a fresh review skips previously invited members',async()=>{
  const s=setup(), p=await s.preview(), id=p.recipients[0].id;
  await Promise.all([s.send(id),s.send(id)]);
  assert.equal(s.calls.sends.length,1);
  assert.equal((await s.preview()).recipients.length,0);
  const resend=await s.preview(true);
  assert.equal(resend.recipients[0].resend,true);
  await s.send(resend.recipients[0].id);
  assert.equal(s.calls.sends.length,2);
});
test('two overlapping reviews cannot both send',async()=>{
  const s=setup(), a=await s.preview(), b=await s.preview();
  await s.send(a.recipients[0].id); await s.send(b.recipients[0].id);
  assert.equal(s.calls.sends.length,1);
});
test('inactive, missing email and duplicated CSV rows are exceptions',async()=>{
  const s=setup({active:false,csvText:`${csv}\nWayne,Example,,wayne@example.test,,Male,,secret\nNo,Email,,,,,,`});
  const p=await s.preview(); assert.equal(p.recipients.length,0); assert.equal(p.exceptions.length,3);
});
test('failed imports are excluded from invitations even if a membership exists',async()=>{
  const s=setup(); const p=await s.request({action:'preview',storage_path:`${club}/committee.csv`,resend:false,excluded_emails:['wayne@example.test']});
  assert.equal(p.recipients.length,0); assert.match(p.exceptions[0].reason,/failed during import/);
});
test('unmatched CSV address does not create a member',async()=>{
  const s=setup({csvText:csv.replace('wayne@example.test','other@example.test')});
  const p=await s.preview(); assert.equal(p.recipients.length,0); assert.match(p.exceptions[0].reason,/No unique/);
});
test('ambiguous profile emails and mismatched login emails are not invited',async()=>{
  const s=setup();s.accounts.user.email='changed@example.test';
  assert.equal((await s.preview()).recipients.length,0);
  s.tables.member_profiles.push({...s.tables.member_profiles[0],id:'duplicate'});
  assert.equal((await s.preview()).recipients.length,0);
});
for (const change of ['inactive','email','owner','club','expired']) test(`send rechecks ${change}`,async()=>{
  const s=setup(),p=await s.preview(),id=p.recipients[0].id;
  if(change==='inactive')s.tables.club_memberships[0].is_active=false;
  if(change==='email')s.accounts.user.email='changed@example.test';
  if(change==='owner')s.tables.member_invitation_attempts[0].created_by='other';
  if(change==='club')s.tables.member_invitation_attempts[0].club_id='other';
  if(change==='expired')s.tables.member_invitation_attempts[0].created_at='2020-01-01';
  assert.ok((await s.send(id)).status>=400);assert.equal(s.calls.sends.length,0);
});
for (const options of [{graphStatus:400},{graphStatus:429}]) test(`definite Graph rejection ${options.graphStatus} can be reviewed and retried`,async()=>{
  const s=setup(options), p=await s.preview();
  assert.equal((await s.send(p.recipients[0].id)).status,'failed');
  assert.equal((await s.preview()).recipients.length,1);
});
for (const options of [{lostResponse:true},{graphStatus:500},{graphStatus:408}]) test(`uncertain result ${JSON.stringify(options)} never automatically resends`,async()=>{
  const s=setup(options),p=await s.preview();
  assert.equal((await s.send(p.recipients[0].id)).status,'unknown');
  assert.equal((await s.preview(true)).recipients.length,0);
});
test('missing either guide blocks preview; replacement keeps reviewed paths immutable',async()=>{
  const s=setup(),p=await s.preview(),old=plain(s.tables.member_invitation_attempts[0].guides);
  await s.request({action:'upload_guide',kind:'android',content:btoa('%PDF-1.7 new')});
  assert.notEqual(s.tables.member_invitation_guides[1].path,old[1].path);
  await s.send(p.recipients[0].id);
  assert.ok(s.calls.downloads.some(([b,path])=>b==='MemberInvitationGuides'&&path===old[1].path));
  s.tables.member_invitation_guides.pop();assert.equal((await s.preview()).status,400);
});
test('upload rejects non-PDF and oversized content',async()=>{
  const s=setup();
  for(const content of [btoa('not pdf'),'x'.repeat(2000001)])assert.equal((await s.request({action:'upload_guide',kind:'android',content})).status,400);
  assert.equal(s.calls.uploads.length,0);
});
test('authentication and club authorization happen before storage or invitation reads',async()=>{
  for(const token of ['', 'invalid']) {const s=setup();assert.equal((await s.request({action:'guides'},token)).status,401);assert.equal(s.calls.reads,0);}
  const s=setup({authorized:false});assert.equal((await s.preview()).status,403);assert.equal(s.calls.downloads.length,0);assert.equal(s.tables.member_invitation_attempts.length,0);
});
test('cross-club and traversal storage paths are rejected',async()=>{
  for(const path of ['other/file.csv',`${club}/../file.csv`,`${club}/%2e/file.csv`,`${club}/a\\b.csv`]) {
    const s=setup();assert.equal((await s.request({action:'preview',storage_path:path,resend:false})).status,400);assert.equal(s.calls.downloads.length,0);
  }
});
test('HTML escapes all personal and club values',()=>{
  const s=setup();const html=vm.runInContext(`invitationHtml(invitationContent('<script>', 'a&b@example.test', '<Club>'))`,s.context);
  assert.doesNotMatch(html,/<script>|<Club>/);assert.match(html,/&lt;script&gt;/);assert.match(html,/a&amp;b/);
});

