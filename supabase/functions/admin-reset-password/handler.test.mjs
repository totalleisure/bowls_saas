import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleReset } from './handler.mjs';
const club = '11111111-1111-4111-8111-111111111111';
const target = '22222222-2222-4222-8222-222222222222';
const other = '33333333-3333-4333-8333-333333333333';
function fixture({ role = 'admin', active = true, targetClub = club,
  targetSuper = false, foreignAdmin = false, authError = false, updateError = false,
  callerSuper = false, linked = true } = {}) {
  const rows = {
    app_superusers: [...(targetSuper ? [{ user_id: 'target-user' }] : []), ...(callerSuper ? [{ user_id: 'caller' }] : [])],
    member_profiles: [{ id: 'caller-profile', user_id: 'caller' }, { id: target, user_id: linked ? 'target-user' : null }],
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
      getUser: async () => ({ data: { user: authError ? null : { id: 'caller' } }, error: authError }),
      admin: {
        getUserById: async id => ({ data: { user: { id, email: 'member@example.invalid' } }, error: null }),
        updateUserById: async (...args) => { calls.push(args); return { error: updateError ? new Error('secret internal details') : null }; },
      },
    },
  };
  return { admin, calls };
}
const request = (overrides = {}, token = true) => new Request('https://example.invalid', {
  method: 'POST', headers: token ? { Authorization: 'Bearer test' } : {},
  body: JSON.stringify({ club_id: club, member_profile_id: target, password: 'Example9!Password', ...overrides }),
});
test('active admin resets only the linked member login, without returning password', async () => {
  const f = fixture(); const r = await handleReset(request(), f.admin);
  assert.equal(r.status, 200); assert.deepEqual(await r.json(), { reset: true, email: 'member@example.invalid' });
  assert.deepEqual(f.calls, [['target-user', { password: 'Example9!Password' }]]);
});
for (const [name, options, status] of [
  ['ordinary member', { role: 'member' }, 403], ['selector', { role: 'selector' }, 403],
  ['inactive admin', { active: false }, 403], ['foreign member', { targetClub: other }, 403],
  ['platform administrator target', { targetSuper: true }, 403],
  ['administrator in another club', { foreignAdmin: true }, 403],
  ['invalid session', { authError: true }, 401], ['no linked account', { linked: false }, 400],
]) test(`rejects ${name} without changing a password`, async () => {
  const f = fixture(options); const r = await handleReset(request(), f.admin);
  assert.equal(r.status, status); assert.equal(f.calls.length, 0);
});
test('requires bearer token and validates password before mutation', async () => {
  const f = fixture(); assert.equal((await handleReset(request({}, false), f.admin)).status, 401);
  assert.equal((await handleReset(request({ password: 'short' }), f.admin)).status, 400);
  assert.equal(f.calls.length, 0);
});
test('auth failure is reported without leaking password or internal errors', async () => {
  const f = fixture({ updateError: true }); const r = await handleReset(request(), f.admin);
  assert.equal(r.status, 400); const text = await r.text();
  assert.ok(!text.includes('Example9!Password')); assert.ok(!text.includes('secret internal'));
});
test('platform admin may assist a privileged member but still needs club membership', async () => {
  const f = fixture({ callerSuper: true, foreignAdmin: true });
  assert.equal((await handleReset(request(), f.admin)).status, 200);
});
