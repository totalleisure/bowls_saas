import { test } from 'node:test';
import assert from 'node:assert/strict';
const now=()=>Date.parse('2026-11-10T12:00:00Z');
import { handleConfirmation } from './handler.mjs';
const club = '11111111-1111-4111-8111-111111111111';
const target = '22222222-2222-4222-8222-222222222222';
const other = '33333333-3333-4333-8333-333333333333';
const request=(action='resend', extra={}, token=true)=>new Request('https://example.invalid',{
  method:'POST',headers:token?{Authorization:'Bearer test'}:{},
  body:JSON.stringify({club_id:club,member_profile_id:target,action,expected_email:'member@example.invalid',...extra}),
});
test('Status reads but never sends; resend uses verified login only and confirms native timestamp',async()=>{
  const f=fixture();let r=await handleConfirmation(request('status'),f.admin,now);
  assert.deepEqual(await r.json(),{eligible:true,email:'member@example.invalid'});assert.equal(f.calls.length,0);
  r=await handleConfirmation(request('resend',{email:'attacker@example.invalid'}),f.admin,now);
  assert.equal(r.status,200);assert.equal((await r.json()).sent,true);
  assert.deepEqual(f.calls,[{type:'signup',email:'member@example.invalid'}]);
});
for(const [name,options,status] of [
  ['member',{role:'member'},403],['selector',{role:'selector'},403],['inactive admin',{active:false},403],
  ['foreign club member',{targetClub:other},403],['platform admin target',{targetSuper:true},403],
  ['other club admin target',{foreignAdmin:true},403],['invalid session',{authError:true},401],
]) test(`Rejects ${name} without sending`,async()=>{
  const f=fixture(options);assert.equal((await handleConfirmation(request(),f.admin,now)).status,status);assert.equal(f.calls.length,0);
});
test('Confirmed, unlinked and recently contacted members cannot be resent',async()=>{
  for(const options of [{confirmed:true},{linked:false},{recent:true}]){
    const f=fixture(options);const r=await handleConfirmation(request(),f.admin,now);
    assert.equal(r.status,options.recent?429:200);assert.equal(f.calls.length,0);
    if(!options.recent) assert.equal((await r.json()).eligible,false);
  }
});
test('Invalid, spoofed and stale requests are rejected',async()=>{
  const f=fixture();
  assert.equal((await handleConfirmation(request('send'),f.admin,now)).status,400);
  assert.equal((await handleConfirmation(request('resend',{},false),f.admin,now)).status,401);
  assert.equal((await handleConfirmation(request('resend',{expected_email:'old@example.invalid'}),f.admin,now)).status,409);
  assert.equal(f.calls.length,0);
});
test('Provider errors are sanitized',async()=>{
  const f=fixture({updateError:true});const r=await handleConfirmation(request(),f.admin,now);
  assert.equal(r.status,502);assert(!(await r.text()).includes('secret'));
});
test('A successful HTTP response without a new confirmation timestamp never reports success',async()=>{
  const f=fixture();f.admin.auth.admin.getUserById=async()=>({data:{user:{email:'member@example.invalid'}}});
  const r=await handleConfirmation(request(),f.admin,now);assert.equal(r.status,503);
});
function fixture({ role = 'admin', active = true, targetClub = club,
  targetSuper = false, foreignAdmin = false, authError = false, updateError = false,
  callerSuper = false, linked = true, confirmed = false, recent = false } = {}) {
  const rows = {
    app_superusers: [...(targetSuper ? [{ user_id: 'target-user' }] : []), ...(callerSuper ? [{ user_id: 'caller' }] : [])],
    member_profiles: [{ id: 'caller-profile', user_id: 'caller' }, { id: target, user_id: linked ? 'target-user' : null, email_address:'member@example.invalid' }],
    club_memberships: [
      { id: 'caller-membership', club_id: club, member_profile_id: 'caller-profile', role, is_active: active },
      { id: 'target-membership', club_id: targetClub, member_profile_id: target, role: 'member', is_active: true },
      ...(foreignAdmin ? [{ club_id: other, member_profile_id: target, role: 'admin', is_active: true }] : []),
    ],
  };
  const calls = [];
  const admin = {
    from(table) {
      const filters = [];
      const q = {
        select() { return q; },
        eq(key, val) { filters.push([key, val]); return q; },
        async maybeSingle() { return { data: rows[table].find(r => filters.every(([k,v]) => r[k] === v)) ?? null, error: null }; },
        then(resolve) { return Promise.resolve({ data: rows[table].filter(r => filters.every(([k,v]) => r[k] === v)), error: null }).then(resolve); },
      }; return q;
    },
    auth: {
      resend: async args => { calls.push(args); return {error:updateError?{status:502,message:'secret token'}:null}; },
      getUser: async () => ({ data: { user: authError ? null : { id: 'caller' } }, error: authError }),
      admin: {
        getUserById: async id => ({ data: { user: { id, email: 'member@example.invalid', email_confirmed_at:confirmed?'2026-01-01':null, confirmation_sent_at:calls.length?'2026-11-10T12:00:00Z':recent?'2026-11-10T11:59:50Z':null } }, error: null }),
        updateUserById: async (...args) => { calls.push(args); return { error: updateError ? new Error('secret internal details') : null }; },
      },
    },
  };
  return { admin, calls };
}
