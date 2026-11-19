import { automated, authoredText, header, normalise } from './written_reply.ts';
import type { Mail } from './written_reply.ts';
const tokenPattern = /\bMRK-[A-F0-9]{64}\b/gi;
export function markerBodyCommand(m: Mail): { command: string; code: string } | null {
 const text=authoredText(m.body?.content ?? '').trim();
 const line=text.split(/\r?\n/).find(l=>l.trim());
 const match=line?.match(/^\s*(OFFER_TO_MARK|UNABLE_TO_MARK|OFFER_MARKER|UNABLE_MARKER|LEAVE_MARKERS|CONFIRM_LEAVE_MARKERS|KEEP_MARKERS)\s+((?:MRK|MLV)-[A-F0-9]{64})\s*$/i);
 if(!match) return null;
 const commands=text.split(/\r?\n/).filter(l=>/^\s*(OFFER_TO_MARK|UNABLE_TO_MARK|OFFER_MARKER|UNABLE_MARKER|LEAVE_MARKERS|CONFIRM_LEAVE_MARKERS|KEEP_MARKERS)\b/i.test(l));
 if(commands.length!==1) return null;
 return {command:match[1].toUpperCase(),code:match[2].toUpperCase()};
}
export function markerCommand(m: Mail): { command: string; code: string } | null {
 const parsed=markerBodyCommand(m); if(!parsed)return null;
 const expected=`Bowls response: ${parsed.command} ${parsed.code}`.toLowerCase();
 return normalise(m.subject?.replace(/^(?:\s*re\s*:)+\s*/i,''))===expected ? parsed : null;
}
export function markerReplyCode(reply: Mail, original: Mail, mailbox: string): string | null {
 if(automated(reply,mailbox) || !reply.internetMessageId || !/^\s*re\s*:/i.test(reply.subject??'') || !authoredText(reply.body?.content??'')) return null;
 if(original.internetMessageId!==header(reply,'in-reply-to') || normalise(original.from?.emailAddress?.address)!==normalise(mailbox)) return null;
 if(original.toRecipients?.length!==1 || normalise(original.toRecipients[0].emailAddress?.address)!==normalise(reply.from?.emailAddress?.address)) return null;
 if(normalise(reply.subject?.replace(/^(?:\s*re\s*:)+\s*/i,''))!==normalise(original.subject)) return null;
 if(!Number.isFinite(Date.parse(original.sentDateTime??'')) || Date.parse(original.sentDateTime!)>Date.parse(reply.receivedDateTime??'')) return null;
 const codes=[...new Set((original.body?.content?.match(tokenPattern)??[]).map(c=>c.toUpperCase()))];
 return codes.length===1 ? codes[0] : null;
}
export async function processMarkerMail(message: Mail, mailbox: string, token: string, supabase: any, fetch: typeof globalThis.fetch): Promise<boolean> {
 const command=markerCommand(message);
 if(command){
  const {error}=await supabase.rpc(['LEAVE_MARKERS','CONFIRM_LEAVE_MARKERS','KEEP_MARKERS'].includes(command.command) ? 'marker_list_email_action' : 'record_marker_volunteer_response',{p_code:command.code,p_sender:normalise(message.from?.emailAddress?.address),p_command:command.command,p_message_id:message.internetMessageId,p_received_at:message.receivedDateTime});
  if(error) throw new Error('Marker response could not be recorded');
  return true;
 }
 // Only correlate replies; never scan arbitrary inbound mail for quoted credentials.
 const reference=header(message,'in-reply-to');
 if(automated(message,mailbox) || !/^\s*re\s*:/i.test(message.subject??'') || !/^<[^<>\s]+>$/.test(reference) || !message.internetMessageId) return false;
 const query=new URLSearchParams({'$filter':`internetMessageId eq '${reference.replaceAll("'","''")}'`,'$select':'internetMessageId,subject,body,from,toRecipients,sentDateTime','$top':'2'});
 const response=await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/mailFolders/sentitems/messages?${query}`,{headers:{Authorization:`Bearer ${token}`,Prefer:'outlook.body-content-type="text"'}});
 if(!response.ok) throw new Error('Unable to correlate marker reply');
 const originals=await response.json(); if(originals.value?.length!==1) return false;
 const original=originals.value[0]; const code=markerReplyCode(message,original,mailbox); if(!code) return false;
 const manual=markerBodyCommand(message);
 if(manual && manual.code===code && ['OFFER_TO_MARK','UNABLE_TO_MARK','OFFER_MARKER','UNABLE_MARKER'].includes(manual.command)) {
  const {error}=await supabase.rpc('record_marker_volunteer_response',{p_code:manual.code,p_sender:normalise(message.from?.emailAddress?.address),p_command:manual.command,p_message_id:message.internetMessageId,p_received_at:message.receivedDateTime});
  if(error)throw new Error('Marker response could not be recorded');
  return true;
 }
 const excerpt=authoredText(message.body?.content??'').replace(tokenPattern,'[private response reference]').replace(/\b(?:RSP-[A-F0-9]{48}|BWL-[A-F0-9]{12})\b/gi,'[private response reference]').slice(0,4000);
 const {data,error}=await supabase.rpc('forward_marker_written_reply',{p_code:code,p_sender:normalise(message.from?.emailAddress?.address),p_message_id:message.internetMessageId,p_received_at:message.receivedDateTime,p_original_subject:original.subject,p_excerpt:excerpt});
 if(error) throw new Error('Unable to queue marker reply forwarding');
 return data?.handled===true;
}
