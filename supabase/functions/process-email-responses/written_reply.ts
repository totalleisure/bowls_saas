export type Mail = {
  id?: string;
  internetMessageId?: string;
  subject?: string;
  receivedDateTime?: string;
  sentDateTime?: string;
  from?: { emailAddress?: { address?: string } };
  toRecipients?: { emailAddress?: { address?: string } }[];
  body?: { contentType?: string; content?: string };
  internetMessageHeaders?: { name: string; value: string }[];
};

export const reminderText = "Thanks for your reply. Your reply has not yet recorded your selection response. Please choose below to accept or decline your selection.";
const escapeHtml = (value: string) => value.replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]!));
export async function responseTokenHash(token: string | null): Promise<string | null> {
  if (!token) return null;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest),byte=>byte.toString(16).padStart(2,'0')).join('');
}
export function buildReminderHtml(mailbox: string, code: string, token: string | null, protocol: number): string {
  if (!/^BWL-[A-F0-9]{12}$/.test(code) || ![1,2].includes(protocol) ||
      (protocol===2 && !/^RSP-[A-F0-9]{48}$/.test(token ?? '')) ||
      (protocol===1 && token!==null)) throw new Error('Validated response credentials required');
  const credential = token ? `${code} ${token}` : code;
  const buttons = ['ACCEPT','DECLINE'].map(command=>{
    const href=`mailto:${mailbox}?subject=${encodeURIComponent(`Bowls response: ${command} ${credential}`)}&body=${encodeURIComponent(`${command} ${credential}`)}`;
    return `<a href="${escapeHtml(href)}" style="display:inline-block;padding:12px 18px;margin:8px 8px 8px 0;border-radius:6px;background:${command==='ACCEPT'?'#18794e':'#b3261e'};color:#ffffff;text-decoration:none;font-weight:700">${command==='ACCEPT'?'Accept selection':'Decline selection'}</a>`;
  }).join(' ');
  return `<div style="font-family:Arial,sans-serif;line-height:1.5;color:#202124;max-width:600px"><p>${reminderText}</p><p>${buttons}</p><p>Each button opens a prepared email. Please send it without changing the subject or message. You can also respond in the app.</p><p>Your written reply has been flagged for the captain or organiser. Thank you.</p><p>If a button does not open your email application, send a new email to ${escapeHtml(mailbox)} with exactly one of these lines as the message:</p><pre style="white-space:pre-wrap;overflow-wrap:anywhere">ACCEPT ${escapeHtml(credential)}<br>DECLINE ${escapeHtml(credential)}</pre></div>`;
}
export const normalise = (s: string | undefined) => (s ?? '').trim().toLowerCase();
export function writtenReplySenderEnabled(config: {
  enabled?: boolean; sender_scope?: string; reminder_recipients?: string[];
} | null | undefined, sender: string): boolean {
  const email = normalise(sender);
  if (!config?.enabled || !email) return false;
  // The claim RPC authoritatively checks membership in the original request's Club.
  if (config.sender_scope === 'active_members') return true;
  if (config.sender_scope && config.sender_scope !== 'allowlist') return false;
  return (config.reminder_recipients ?? []).some(value => normalise(value) === email);
}
export function header(m: Mail, name: string): string {
  return (m.internetMessageHeaders ?? []).filter(h => normalise(h.name) === name)
    .map(h => h.value.trim()).join(' ');
}
export function authoredText(body: string): string {
  const lines = body.split(/\r?\n/);
  const end = lines.findIndex(line => /^\s*(?:>|From:\s|On .+ wrote:|[-]{2,}\s*(?:Original Message|Forwarded message))/i.test(line));
  return lines.slice(0, end < 0 ? lines.length : end).join('\n').trim();
}
export function automated(m: Mail, mailbox: string): boolean {
  const sender = normalise(m.from?.emailAddress?.address);
  return !sender || sender === normalise(mailbox) || /^(?:mailer-daemon|postmaster|no-?reply)@/i.test(sender) ||
    !!(header(m, 'auto-submitted') && normalise(header(m, 'auto-submitted')) !== 'no') ||
    /\b(bulk|list|junk)\b/i.test(header(m, 'precedence')) ||
    ['x-autoreply','x-autorespond','list-id','x-bowls-selection-reminder'].some(k => !!header(m,k)) ||
    /^(automatic reply|auto(?:matic)?[- ]?reply|out of office|undeliverable|delivery status notification)\b/i.test(m.subject?.trim() ?? '');
}
// Conservative routing: technical/support questions remain in the support mailbox.
export function candidate(m: Mail, mailbox: string, enabledAt: string, now: string): boolean {
  const received = Date.parse(m.receivedDateTime ?? '');
  const start = Date.parse(enabledAt);
  const current = Date.parse(now);
  const text = authoredText(m.body?.content ?? '');
  return [received,start,current].every(Number.isFinite) && received >= start && received <= current + 300000 &&
    !!m.id && !!m.internetMessageId && !automated(m,mailbox) && /^\s*re\s*:/i.test(m.subject ?? '') &&
    /^<[^<>\s]+>$/.test(header(m,'in-reply-to')) && !!text && !text.includes('?') &&
    !/\b(support|help|troubleshoot(?:ing)?|forward(?:ed|ing)?|error|bug|problem|issue|broken|log\s?in|sign\s?in|password|button|link|app|website)\b/i.test(`${m.subject}\n${text}`);
}
export function correlate(m: Mail, original: Mail, mailbox: string): { code: string; responseToken: string | null; excerpt: string } | null {
  if (original.internetMessageId !== header(m,'in-reply-to') || normalise(original.from?.emailAddress?.address) !== normalise(mailbox)) return null;
  const sender = normalise(m.from?.emailAddress?.address);
  if (original.toRecipients?.length !== 1 || normalise(original.toRecipients[0].emailAddress?.address) !== sender) return null;
  if (normalise(m.subject?.replace(/^(?:\s*re\s*:)+\s*/i,'')) !== normalise(original.subject)) return null;
  const sent = Date.parse(original.sentDateTime ?? '');
  if (!Number.isFinite(sent) || sent > Date.parse(m.receivedDateTime ?? '')) return null;
  const body = original.body?.content ?? '';
  const codes = [...new Set((body.match(/\bBWL-[A-F0-9]{12}\b/gi) ?? []).map(x=>x.toUpperCase()))];
  // The referenced sent message must itself contain the original response block.
  if (codes.length !== 1 || !/ACCEPT/i.test(body) || !/DECLINE/i.test(body)) return null;
  const tokens = [...new Set((body.match(/\bRSP-[A-F0-9]{48}\b/gi) ?? []).map(x=>x.toUpperCase()))];
  if (tokens.length > 1) return null;
  const inboundCodes = [...new Set(((m.body?.content ?? '').match(/\bBWL-[A-F0-9]{12}\b/gi) ?? []).map(x=>x.toUpperCase()))];
  if (inboundCodes.some(code => code !== codes[0])) return null;
  const excerpt = authoredText(m.body?.content ?? '').replace(/\b(?:BWL-[A-F0-9]{12}|RSP-[A-F0-9]{48})\b/gi,'[response reference]').slice(0,1500);
  return { code: codes[0], responseToken: tokens[0] ?? null, excerpt };
}
