export const MAX_ATTEMPTS = 6;
export const RETRY_SECONDS = [300, 900, 3600, 14400, 43200];

export function classifySendFailure(status, data = {}) {
  const stage = data.stage;
  if (data.send_outcome === 'not_submitted' || status === 429) {
    return { outcome: status === 429 ? 'deferred' :
      (status >= 500 ? 'retry' : 'permanent'),
      delay: Math.max(60, Number(data.retry_after_seconds) || 0) };
  }
  if (status === 408 || status >= 500 || !status) return { outcome: 'uncertain', delay: 600 };
  return { outcome: 'permanent', delay: 0 };
}

export function normaliseText(value) {
  return String(value ?? '').replace(/<[^>]*>/g, ' ')
    .replace(/&(?:nbsp|#160);/gi, ' ').replace(/&amp;/gi, '&')
    .replace(/&#39;|&apos;/gi, "'").replace(/&quot;/gi, '"')
    .replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ').trim();
}

export function matchesSentMessage(message, email) {
  const to = message.toRecipients ?? [];
  if (to.length !== 1 || String(to[0]?.emailAddress?.address).toLowerCase() !==
    String(email.recipient_email).toLowerCase() || message.subject !== email.subject) return false;
  const header = (message.internetMessageHeaders ?? []).find(h =>
    String(h.name).toLowerCase() === 'x-bowls-email-queue-id');
  if (header) return header.value === email.id;
  // Only pre-upgrade messages may use the legacy body correlation.
  if (!email.delivery_last_details?.legacy) return false;
  const body = normaliseText(email.body);
  return body.length >= 40 && normaliseText(message.body?.content).includes(body);
}

export async function graphToken(env, fetcher = fetch) {
  const tenant = env('MS_TENANT_ID'), client = env('MS_CLIENT_ID'), secret = env('MS_CLIENT_SECRET');
  if (!tenant || !client || !secret) throw new Error('Microsoft mail configuration is missing');
  const response = await fetcher(`https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token`, {
    method: 'POST', headers: {'Content-Type':'application/x-www-form-urlencoded'},
    body: new URLSearchParams({client_id:client,client_secret:secret,
      scope:'https://graph.microsoft.com/.default',grant_type:'client_credentials'}),
    signal: AbortSignal.timeout(15000),
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) throw new Error(`Microsoft token request failed (${response.status})`);
  return data.access_token;
}

export async function findSentMessages(email, mailbox, token, fetcher = fetch) {
  const start = new Date(Date.parse(email.last_attempt_at || email.created_at) - 120000).toISOString();
  const end = new Date().toISOString();
  const url = new URL(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/mailFolders/sentitems/messages`);
  url.searchParams.set('$filter', `sentDateTime ge ${start} and sentDateTime le ${end}`);
  url.searchParams.set('$select', 'id,internetMessageId,internetMessageHeaders,subject,toRecipients,sentDateTime,body');
  url.searchParams.set('$top', '100');
  let next = url.href; const matches = []; let scanned = 0;
  const deadline = Date.now() + 20000;
  for (let page = 0; next && page < 20; page++) {
    if (Date.now() >= deadline) throw new Error('Sent Items scan time budget reached; no absence conclusion recorded');
    const parsed = new URL(next);
    if (parsed.origin !== 'https://graph.microsoft.com' || !parsed.pathname.startsWith('/v1.0/users/')) {
      throw new Error('Unexpected Microsoft pagination URL');
    }
    const response = await fetcher(next, {headers: {Authorization:`Bearer ${token}`,
      Prefer:'outlook.body-content-type="text"'},signal:AbortSignal.timeout(Math.max(1,Math.min(15000,deadline-Date.now())))});
    if (!response.ok) throw new Error(`Sent Items check failed (${response.status})`);
    const data = await response.json();
    if (!Array.isArray(data.value)) throw new Error('Incomplete Sent Items response');
    scanned += data.value.length;
    matches.push(...data.value.filter(m => matchesSentMessage(m, email)).map(m => ({
      id:m.id,internet_message_id:m.internetMessageId,sent_at:m.sentDateTime,
    })));
    next = data['@odata.nextLink'] || '';
  }
  if (next) throw new Error('Sent Items check exceeded page limit; manual review required');
  return {matches,scanned,window_start:start,window_end:end};
}
