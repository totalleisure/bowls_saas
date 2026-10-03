import { parseResponse } from './response_parser.ts';
import { responseTokenHash } from './written_reply.ts';

// Read-only synthetic-test diagnostic. Never return message bodies or credentials.
export async function verifySentReminder(requestId: string, mailbox: string, graphToken: string, db: any, fetch: typeof globalThis.fetch) {
  const {data:request,error} = await db.from('email_action_requests')
    .select('id,recipient_email,response_code_hash,response_token_hash,status,source_email_queue_id')
    .eq('id',requestId).maybeSingle();
  if(error || request?.recipient_email!=='wayne@totalleisure.com') throw new Error('Wayne-only test request required');
  const {data:source,error:sourceError} = await db.from('email_queue').select('payload').eq('id',request.source_email_queue_id).maybeSingle();
  if(sourceError || source?.payload?.written_reply_test!==true) throw new Error('Synthetic test required');
  const {data:reply,error:replyError} = await db.from('email_written_replies').select('created_at').eq('request_id',requestId).order('created_at',{ascending:true}).limit(1).maybeSingle();
  if(replyError || !reply) throw new Error('No written reply record');
  const since=new Date(Date.parse(reply.created_at)-60000).toISOString();
  const query=new URLSearchParams({'$filter':`subject eq 'Your selection response' and sentDateTime ge ${since}`,'$select':'body,toRecipients,from,internetMessageHeaders','$top':'50'});
  const response=await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/mailFolders/sentitems/messages?${query}`,{headers:{Authorization:`Bearer ${graphToken}`}});
  if(!response.ok) throw new Error(`Sent reminder verification failed (${response.status})`);
  const page=await response.json();
  if(page['@odata.nextLink']) throw new Error('Narrower verification window required');
  let matches=0;
  for(const message of page.value ?? []) {
    if(message.toRecipients?.length!==1 || message.toRecipients[0].emailAddress?.address?.toLowerCase()!=='wayne@totalleisure.com' || message.from?.emailAddress?.address?.toLowerCase()!==mailbox) continue;
    const headers=message.internetMessageHeaders ?? [];
    if(!headers.some((h:any)=>h.name.toLowerCase()==='x-bowls-selection-reminder' && h.value==='1'))continue;
    if(await validReminderButtons(String(message.body?.content ?? ''),mailbox,request.response_code_hash,request.response_token_hash)) matches++;
  }
  return {mode:'verify_test_reminder',request_id:requestId,matching_sent_reminders:matches,
    correct_accept_and_decline_buttons:matches===1,recipient_wayne_only:matches===1,request_status:request.status};
}

export async function validReminderButtons(html: string, mailbox: string, codeHash: string, tokenHash: string): Promise<boolean> {
  const commands=new Set<string>();
  for(const link of html.matchAll(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    try {
      const url=new URL(link[1].replace(/&amp;/gi,'&'));
      if(url.protocol!=='mailto:' || url.pathname.toLowerCase()!==mailbox) continue;
      const parsed=parseResponse({subject:url.searchParams.get('subject') ?? '',bodyText:url.searchParams.get('body') ?? ''});
      if(parsed?.kind!=='match' || !parsed.responseToken) continue;
      if(await responseTokenHash(parsed.responseCode)!==codeHash || await responseTokenHash(parsed.responseToken)!==tokenHash)continue;
      const label=link[2].replace(/<[^>]+>/g,'').trim().toLowerCase();
      if(label!==`${parsed.command.toLowerCase()} selection`)continue;
      commands.add(parsed.command);
    } catch { /* Ignore unrelated or malformed links. */ }
  }
  return commands.has('ACCEPT') && commands.has('DECLINE');
}
