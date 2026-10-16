import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isVerifiedWorker } from '../supabase/functions/process-email-queue/worker_auth.ts';
test('missing token rejected without network', async () => {
  assert.equal(await isVerifiedWorker('', 'key', 'https://example.invalid', () => {throw Error('network');}), false);
});
test('current server key retains existing path', async () => {
  assert.equal(await isVerifiedWorker('key', 'key', 'https://example.invalid', () => {throw Error('network');}), true);
});
test('alternate worker credential must pass service-only database probe', async () => {
  assert.equal(await isVerifiedWorker('alternate', 'key', 'https://example.invalid', async (url, opts) => {
    assert.equal(url, 'https://example.invalid/rest/v1/email_written_reply_settings?select=mailbox&limit=0');
    assert.equal(opts.headers.Authorization, 'Bearer alternate');
    assert.equal(opts.headers.apikey, 'key');
    return Response.json([]);
  }), true);
});
for (const code of [401,403]) test(`denied token ${code} is not treated as server`, async () => {
  assert.equal(await isVerifiedWorker('forged', 'key', 'https://example.invalid', async () => new Response(null,{status:code})), false);
});
test('network failure fails closed', async () => {
  await assert.rejects(isVerifiedWorker('alternate','key','https://example.invalid',async()=>{throw Error('offline');}));
});
for (const response of [()=>new Response(null,{status:500}),()=>Response.json({role:'service_role'}),()=>Response.json([{mailbox:'unexpected'}])]) {
  test('unexpected probe response fails closed', async () => {
    await assert.rejects(isVerifiedWorker('alternate','key','https://example.invalid',async()=>response()));
  });
}
