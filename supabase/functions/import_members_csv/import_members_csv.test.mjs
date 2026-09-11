import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
const executable = stripTypeScriptTypes(source.replace(/^import .*;?$/gm, '').replace(/export function/g, 'function'));
const club = '11111111-1111-1111-1111-111111111111';
const otherClub = '22222222-2222-2222-2222-222222222222';
const header = 'first name,last name,title,email,mobile phone,gender,outdoor club,password';
const csv = (...rows) => [header, ...rows].join('\n');
const row = (n, extra = {}) => {
  const values = { first: `Person${n}`, last: 'Example', title: 'Dr', email: `person${n}@example.test`, phone: `07000000${n}`, gender: 'Female', outdoor: 'Example Club', password: 'test-pass-123', ...extra };
  return Object.values(values).join(',');
};
const plain = value => JSON.parse(JSON.stringify(value));

function setup({ role = 'admin', active = true, callerClub = club, superuser = false, validToken = true, failPermission = false, failMemberProfile = false } = {}) {
  const users = [{ id: 'caller', email: 'caller@example.test' }];
  const tables = {
    app_superusers: superuser ? [{ user_id: 'caller' }] : [],
    member_profiles: [{ id: 'caller-profile', user_id: 'caller', display_name: 'Caller' }],
    club_memberships: [{ id: 'caller-membership', club_id: callerClub, member_profile_id: 'caller-profile', role, is_active: active }],
  };
  const calls = { downloads: 0, lists: 0, creations: 0, writes: 0, auth: 0 };
  let text = '', handler, nextId = 1;
  const admin = {
    auth: {
      getUser: async token => { calls.auth++; return validToken && token === 'valid-token' ? { data: { user: { id: 'caller', user_metadata: { role: 'admin' } } } } : { data: { user: null }, error: new Error('Invalid token') }; },
      admin: {
        listUsers: async ({ page, perPage }) => { calls.lists++; return { data: { users: users.slice((page - 1) * perPage, page * perPage) } }; },
        createUser: async args => {
          if (users.some(u => u.email === args.email)) return { error: new Error('Account already exists') };
          calls.creations++;
          const user = { id: `u${nextId++}`, email: args.email };
          users.push(user);
          // Mirrors the inspected handle_new_user trigger.
          tables.member_profiles.push({ id: `p-${user.id}`, user_id: user.id, display_name: args.user_metadata?.display_name ?? args.email });
          return { data: { user } };
        },
        inviteUserByEmail: async () => { throw new Error('Unexpected invitation: tests never send emails'); },
      },
    },
    storage: { from: bucket => ({ download: async path => { assert.equal(bucket, 'Imports'); assert.ok(path.startsWith(club + '/')); calls.downloads++; return { data: new Blob([text]) }; } }) },
    from: table => {
      assert.ok(table in tables, `Unexpected table ${table}`);
      const filters = [];
      let operation = 'read', payload, options, result;
      const execute = () => {
        if (result) return result;
        if (failPermission && table === 'app_superusers') return { error: new Error('Permission lookup unavailable') };
        const matches = tables[table].filter(r => filters.every(([key, value]) => r[key] === value));
        if (failMemberProfile && table === 'member_profiles' && filters.some(([key, value]) => key === 'user_id' && value !== 'caller')) return { error: new Error('Profile read failed') };
        if (operation === 'read') return result = { data: matches };
        calls.writes++;
        if (operation === 'update') { for (const r of matches) Object.assign(r, payload); return result = { data: matches }; }
        if (operation === 'upsert') {
          assert.equal(options.onConflict, 'club_id,member_profile_id');
          const existing = tables[table].find(r => r.club_id === payload.club_id && r.member_profile_id === payload.member_profile_id);
          if (existing && options.ignoreDuplicates) return result = { data: [] };
          if (existing) { Object.assign(existing, payload); return result = { data: [existing] }; }
        }
        const inserted = { id: `r${nextId++}`, ...payload };
        tables[table].push(inserted);
        return result = { data: [inserted] };
      };
      const query = {
        select: () => query,
        eq: (key, value) => { filters.push([key, value]); return query; },
        maybeSingle: async () => { const r = execute(); return r.error ? r : { data: r.data[0] ?? null }; },
        single: async () => { const r = execute(); return r.error ? r : { data: r.data[0] }; },
        insert: v => { operation = 'insert'; payload = v; return query; },
        update: v => { operation = 'update'; payload = v; return query; },
        upsert: (v, opts) => { operation = 'upsert'; payload = v; options = opts; return query; },
        then: (resolve, reject) => Promise.resolve(execute()).then(resolve, reject),
      };
      return query;
    },
  };
  const context = vm.createContext({ Response, Error, Deno: { env: { get: () => 'test' } }, createClient: () => admin, serve: fn => { handler = fn; } });
  vm.runInContext(executable, context);
  return {
    users, tables, calls, context,
    async run(input = csv(row(1)), { method = 'POST', token = 'valid-token', body = {}, rawBody } = {}) {
      text = input;
      const request = new Request('http://localhost', {
        method, headers: token === null ? {} : { Authorization: `Bearer ${token}` },
        ...(method === 'POST' ? { body: rawBody ?? JSON.stringify({ club_id: club, storage_path: `${club}/members.csv`, new_members_active: false, ...body }) } : {}),
      });
      const response = await handler(request);
      return { status: response.status, headers: response.headers, data: method === 'OPTIONS' ? await response.text() : await response.json() };
    },
    memberProfiles: () => tables.member_profiles.filter(p => p.user_id !== 'caller'),
    memberships: () => tables.club_memberships.filter(m => m.member_profile_id !== 'caller-profile'),
  };
}

test('two records, repeat two, then full nine: separate accounts/profiles and no duplicates', async () => {
  const app = setup();
  const first = await app.run(csv(row(1), row(2)));
  assert.equal(first.data.summary.created, 2);
  assert.equal(first.data.summary.linked, 2);
  const repeated = await app.run(csv(row(1), row(2)), { body: { new_members_active: true } });
  assert.equal(repeated.data.summary.created, 0);
  assert.equal(repeated.data.summary.linked, 0);
  assert.equal(repeated.data.summary.existing_memberships, 2);
  const all = await app.run(csv(...Array.from({ length: 9 }, (_, n) => row(n + 1))));
  assert.equal(all.data.summary.created, 7);
  assert.equal(all.data.summary.linked, 7);
  assert.equal(all.data.summary.existing_memberships, 2);
  assert.equal(app.users.length, 10); // nine imports plus the caller
  assert.equal(app.memberProfiles().length, 9);
  assert.equal(app.memberships().length, 9);
  assert.equal(new Set(app.memberships().map(m => m.member_profile_id)).size, 9);
  assert.ok(app.memberships().every(m => m.is_active === false && m.role === 'member'));
  for (const p of app.memberProfiles()) assert.equal(p.display_name, `${p.first_name} ${p.last_name}`);
});

for (const active of [false, true]) test(`explicit starting status ${active}; CSV/request role overrides ignored`, async () => {
  const app = setup();
  const response = await app.run(header + ',role\n' + row(1) + ',admin', { body: { new_members_active: active, default_role: 'admin' } });
  assert.equal(response.data.summary.errors, 0);
  assert.equal(app.memberships()[0].is_active, active);
  assert.equal(app.memberships()[0].role, 'member');
});

test('existing membership roles/status and populated profile values are preserved in both modes', async () => {
  const app = setup();
  await app.run(csv(row(1)));
  const membership = app.memberships()[0];
  membership.role = 'admin'; membership.is_active = true;
  const profile = app.memberProfiles()[0];
  profile.display_name = 'Custom name'; profile.gender = 'non_binary';
  const before = plain(profile);
  for (const active of [false, true]) {
    const r = await app.run(csv(row(1, { title: '', outdoor: '', gender: '', password: '' })), { body: { new_members_active: active } });
    assert.equal(r.data.summary.errors, 0);
    assert.deepEqual(profile, before);
    assert.equal(membership.role, 'admin'); assert.equal(membership.is_active, true);
  }
});

test('blank optional fields are null/unsupplied and missing fields can be filled later', async () => {
  const app = setup();
  await app.run(csv(row(1, { title: '', gender: '', outdoor: '', phone: '' })));
  const profile = app.memberProfiles()[0];
  for (const field of ['title', 'gender', 'outdoor_club', 'phone']) assert.equal(profile[field] ?? null, null);
  await app.run(csv(row(1)));
  assert.equal(profile.title, 'Dr'); assert.equal(profile.gender, 'female'); assert.equal(profile.outdoor_club, 'Example Club');
});

test('trigger-created profiles receive proper display names; email placeholders repaired, custom names preserved', async () => {
  const app = setup();
  await app.run(csv(row(1)));
  const profile = app.memberProfiles()[0];
  assert.equal(profile.display_name, 'Person1 Example');
  profile.display_name = profile.email_address;
  await app.run(csv(row(1)));
  assert.equal(profile.display_name, 'Person1 Example');
  profile.display_name = 'Preferred Name';
  await app.run(csv(row(1)));
  assert.equal(profile.display_name, 'Preferred Name');
});

test('ambiguous gender is warned about without inference or member rejection', async () => {
  const app = setup();
  const response = await app.run(csv(row(1, { gender: 'ambiguous' })));
  assert.equal(response.data.summary.errors, 0);
  assert.equal(response.data.report[0].warnings.length, 1);
  assert.equal(app.memberProfiles()[0].gender ?? null, null);
});

test('missing contacts set aside; phone-only records reported; no writes', async () => {
  const app = setup();
  const r = await app.run(csv(row(1, { email: '', phone: '' }), row(2, { email: '' })));
  assert.equal(r.data.summary.manual_review, 1);
  assert.equal(r.data.summary.errors, 1);
  assert.equal(app.calls.creations, 0); assert.equal(app.calls.writes, 0);
});

test('duplicate CSV email is skipped case-insensitively', async () => {
  const app = setup();
  const r = await app.run(csv(row(1), row(1, { email: 'PERSON1@EXAMPLE.TEST' })));
  assert.equal(r.data.summary.created, 1);
  assert.equal(r.data.report[1].status, 'skipped_duplicate_in_csv');
});

for (const active of [true, false]) test(`missing new-account password errors without sending invitations (${active})`, async () => {
  const app = setup();
  const r = await app.run(csv(row(1, { password: '' })), { body: { new_members_active: active } });
  assert.equal(r.data.summary.errors, 1); assert.match(r.data.report[0].message, /password/);
  assert.equal(app.calls.creations, 0); assert.equal(app.calls.writes, 0);
});

for (const token of [null, 'invalid']) test(`rejects missing/invalid session (${token}) before CSV reads or writes`, async () => {
  const app = setup(); const r = await app.run(undefined, { token });
  assert.equal(r.status, 401); assert.equal(app.calls.downloads, 0); assert.equal(app.calls.lists, 0); assert.equal(app.calls.writes, 0);
});

for (const options of [{ role: 'member' }, { role: 'selector' }, { active: false }, { callerClub: otherClub }]) test(`rejects unauthorized caller ${JSON.stringify(options)}`, async () => {
  const app = setup(options); const r = await app.run();
  assert.equal(r.status, 403); assert.equal(app.calls.downloads, 0); assert.equal(app.calls.lists, 0); assert.equal(app.calls.writes, 0);
});

test('verified superuser can import without a club admin membership', async () => {
  const app = setup({ superuser: true, role: 'member', active: false });
  assert.equal((await app.run()).data.summary.linked, 1);
});
test('permission query failure fails closed before CSV access', async () => {
  const app = setup({ failPermission: true }); assert.equal((await app.run()).status, 500);
  assert.equal(app.calls.downloads, 0); assert.equal(app.calls.creations, 0);
});

for (const path of [`${otherClub}/members.csv`, `${club}/../other.csv`, `${club}/%2e%2e/other.csv`]) test(`rejects a CSV path outside the authorized club (${path})`, async () => {
  const app = setup(); assert.equal((await app.run(undefined, { body: { storage_path: path } })).status, 400);
  assert.equal(app.calls.downloads, 0);
});
for (const value of [null, 'false', 1]) test(`requires an explicit boolean starting status (${value})`, async () => {
  const app = setup(); assert.equal((await app.run(undefined, { body: { new_members_active: value } })).status, 400);
  assert.equal(app.calls.downloads, 0);
});
test('old clients without a status choice fail safely', async () => {
  const app = setup(); assert.equal((await app.run(undefined, { rawBody: JSON.stringify({ club_id: club, storage_path: `${club}/members.csv` }) })).status, 400);
});
test('browser preflight and method restrictions require no privileged access', async () => {
  const app = setup(); const preflight = await app.run(undefined, { method: 'OPTIONS', token: null });
  assert.equal(preflight.status, 200); assert.equal(preflight.headers.get('Access-Control-Allow-Origin'), '*');
  assert.equal((await app.run(undefined, { method: 'GET' })).status, 405);
  assert.equal(app.calls.auth, 0); assert.equal(app.calls.downloads, 0);
});
test('malformed CSV fails before account creation', async () => {
  const app = setup(); assert.equal((await app.run(csv('A,B'))).status, 400); assert.equal(app.calls.creations, 0);
});
test('quoted CSV accepts BOM, commas, escaped quotes and multiline fields', () => {
  const { context } = setup();
  const result = context.parseCsv('\ufeff' + csv('A,Person,,a@example.test,,,"Club, ""quoted""\nname",pass'));
  assert.equal(result[0].outdoor_club, 'Club, "quoted"\nname');
  assert.throws(() => context.parseCsv(csv('"open')), /unterminated/);
});
test('profile errors are reported accurately and do not create a membership', async () => {
  const app = setup({ failMemberProfile: true }); const r = await app.run();
  assert.equal(r.data.summary.errors, 1); assert.equal(r.data.report[0].message, 'Profile read failed');
  assert.equal(app.memberships().length, 0);
});
test('pagination finds an existing account beyond the first page', async () => {
  const app = setup();
  for (let i = 0; i < 1000; i++) app.users.push({ id: `old${i}`, email: `old${i}@example.test` });
  const r = await app.run(csv(row(1, { email: 'old999@example.test', password: '' })));
  assert.equal(r.data.summary.created, 0); assert.equal(r.data.summary.linked, 1); assert.equal(app.calls.lists, 2);
});

for (const gender of ['Male', 'Female', ' male ', ' FEMALE ']) test(`explicit ${gender} populates both fields on initial and repeat import`, async () => {
  const app = setup();
  await app.run(csv(row(1, { gender })));
  const profile = app.memberProfiles()[0];
  assert.equal(profile.gender, gender.trim().toLowerCase());
  assert.equal(profile.sex_at_birth, gender.trim().toLowerCase());
  delete profile.sex_at_birth;
  await app.run(csv(row(1, { gender })));
  assert.equal(profile.sex_at_birth, gender.trim().toLowerCase());
});

for (const gender of ['', 'ambiguous', 'Non-binary', 'Prefer not to say']) test(`does not infer sex at birth from ${gender || 'blank'}`, async () => {
  const app = setup();
  await app.run(csv(row(1, { gender })));
  assert.equal(app.memberProfiles()[0].sex_at_birth ?? null, null);
});

test('re-import preserves a populated sex-at-birth value for blank or conflicting gender', async () => {
  const app = setup();
  await app.run(csv(row(1, { gender: 'Female' })));
  const profile = app.memberProfiles()[0];
  profile.sex_at_birth = 'intersex';
  for (const gender of ['', 'Male']) {
    await app.run(csv(row(1, { gender })));
    assert.equal(profile.sex_at_birth, 'intersex');
    assert.equal(profile.gender, 'female');
  }
});
