import { test } from 'node:test';
import assert from 'node:assert/strict';
import { writtenReplySenderEnabled } from './written_reply.ts';

test('missing or disabled settings never capture written replies', () => {
  assert.equal(writtenReplySenderEnabled(null, 'member@example.test'), false);
  assert.equal(writtenReplySenderEnabled({enabled:false,sender_scope:'active_members'}, 'member@example.test'), false);
});
test('legacy and explicit pilot scopes preserve sender isolation', () => {
  for (const sender_scope of [undefined,'allowlist']) {
    const config={enabled:true,sender_scope,reminder_recipients:['PILOT@example.test']};
    assert.equal(writtenReplySenderEnabled(config,' pilot@EXAMPLE.test '),true);
    assert.equal(writtenReplySenderEnabled(config,'new@example.test'),false);
  }
});
test('active-member mode admits candidates for authoritative Club membership checks', () => {
  const config={enabled:true,sender_scope:'active_members',reminder_recipients:[]};
  assert.equal(writtenReplySenderEnabled(config,'new@example.test'),true);
  assert.equal(writtenReplySenderEnabled(config,''),false);
  assert.equal(writtenReplySenderEnabled({...config,sender_scope:'invalid'},'new@example.test'),false);
});
