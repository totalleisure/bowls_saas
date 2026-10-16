import assert from 'node:assert/strict';
import { handleRequest } from '../supabase/functions/send-graph-email/handler.ts';

const files = [
  { name: 'Guide.pdf', contentType: 'application/octet-stream', contentBytes: 'UERG' },
  { name: 'Times.csv', contentType: 'application/octet-stream', contentBytes: 'YSxi' },
];
let sent;
const fakeFetch = async (url, options) => {
  if (url.includes('oauth2')) return Response.json({ access_token: 'test-token' });
  assert.ok(url.includes('/sendMail'));
  sent = JSON.parse(options.body);
  return new Response(null, { status: 202 });
};
const response = await handleRequest(new Request('https://example.invalid', {
  method: 'POST', headers: { Authorization: 'Bearer test-only' },
  body: JSON.stringify({ to: 'recipient@example.invalid', subject: 'Test', html: '<p>Test</p>', attachments: files }),
}), () => 'test-only', fakeFetch);
assert.equal(response.status, 200);
assert.equal((await response.json()).attachment_count, 2);
assert.deepEqual(sent.message.attachments, files.map(file => ({
  '@odata.type': '#microsoft.graph.fileAttachment', ...file,
})));
assert.equal(sent.message.toRecipients.length, 1);
console.log('PASS: both filenames and exact bytes forwarded to Microsoft Graph; mocked transport, no email sent.');
