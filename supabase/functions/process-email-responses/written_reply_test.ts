import { test } from 'node:test';
import assert from 'node:assert/strict';
import { candidate, correlate, automated } from './written_reply.ts';
import type { Mail } from './written_reply.ts';
const mailbox='bowls-staging@totalleisure.com';
const code='BWL-123456ABCDEF';
const now='2026-10-01T12:00:00Z', enabled='2026-10-01T10:00:00Z';
const base: Mail={id:'m',internetMessageId:'<reply@example.test>',subject:'Re: Team selection',receivedDateTime:'2026-10-01T11:00:00Z',from:{emailAddress:{address:'member@example.test'}},body:{content:'Thanks, I can play.\n> ACCEPT '+code},internetMessageHeaders:[{name:'In-Reply-To',value:'<original@example.test>'}]};
const original: Mail={internetMessageId:'<original@example.test>',subject:'Team selection',sentDateTime:'2026-10-01T09:00:00Z',from:{emailAddress:{address:mailbox}},toRecipients:[{emailAddress:{address:'member@example.test'}}],body:{content:'ACCEPT or DECLINE '+code}};
test('prose is correlated without inferring acceptance',()=>{assert(candidate(base,mailbox,enabled,now));assert.equal(correlate(base,original,mailbox)?.code,code);});
const negatives: [string,Partial<Mail>][]=[
 ['plain support email',{subject:'Support enquiry',body:{content:'Please help'}}],
 ['Re support conversation',{subject:'Re: Support enquiry',body:{content:'Thank you'}}],
 ['support sender with outstanding selection',{subject:'Re: Login',body:{content:'I cannot sign in'}}],
 ['support question quoting selection',{body:{content:'The Accept button does not work.\n> ACCEPT '+code}}],
 ['forwarded selection for troubleshooting',{subject:'Fwd: Team selection',body:{content:'Troubleshooting this\n> ACCEPT '+code}}],
 ['support quote with ambiguous context',{body:{content:'Can you help with this?\n> ACCEPT '+code}}],
 ['unclear question about quoted selection',{body:{content:'What does this mean?\n> ACCEPT '+code}}],
 ['historical message',{receivedDateTime:'2026-09-30T12:00:00Z'}],
 ['invalid date',{receivedDateTime:'invalid'}],
 ['future message',{receivedDateTime:'2027-10-01T12:00:00Z'}],
 ['missing stable ID',{internetMessageId:undefined}],
 ['missing reply reference',{internetMessageHeaders:[]}],
 ['multiple reply references',{internetMessageHeaders:[{name:'In-Reply-To',value:'<a> <b>'}]}],
 ['empty authored text',{body:{content:'> ACCEPT '+code}}],
 ['self sender',{from:{emailAddress:{address:mailbox}}}],
 ['OOO subject',{subject:'Automatic reply: Team selection'}],
 ['auto submitted',{internetMessageHeaders:[...base.internetMessageHeaders!,{name:'Auto-Submitted',value:'auto-replied'}]}],
 ['list mail',{internetMessageHeaders:[...base.internetMessageHeaders!,{name:'List-Id',value:'club'}]}],
 ['prior reminder',{internetMessageHeaders:[...base.internetMessageHeaders!,{name:'x-bowls-selection-reminder',value:'1'}]}],
 ['bulk mail',{internetMessageHeaders:[...base.internetMessageHeaders!,{name:'Precedence',value:'bulk'}]}],
];
for(const [name,changes] of negatives) test(name,()=>assert.equal(candidate({...base,...changes},mailbox,enabled,now),false));
const badOriginals: [string,Partial<Mail>][]=[
 ['unrelated support mail',{subject:'Support enquiry'}],
 ['wrong original ID',{internetMessageId:'<different@example.test>'}],
 ['wrong original sender',{from:{emailAddress:{address:'someone@example.test'}}}],
 ['wrong original recipient',{toRecipients:[{emailAddress:{address:'other@example.test'}}]}],
 ['multi recipient original',{toRecipients:[...original.toRecipients!,{emailAddress:{address:'other@example.test'}}]}],
 ['no response block',{body:{content:'Thank you for contacting support'}}],
 ['multiple codes',{body:{content:'ACCEPT DECLINE '+code+' BWL-000000000000'}}],
 ['original sent after reply',{sentDateTime:now}],
];
for(const [name,changes] of badOriginals) test(name,()=>assert.equal(correlate(base,{...original,...changes},mailbox),null));
test('inbound mismatched quoted code bypasses',()=>assert.equal(correlate({...base,body:{content:'Thanks\n> BWL-000000000000'}},original,mailbox),null));
test('response token removed from organiser excerpt',()=>assert(!correlate({...base,body:{content:'My reference RSP-'+ 'A'.repeat(48)}},original,mailbox)?.excerpt.includes('RSP-')));
test('case insensitive automatic header name',()=>assert(automated({...base,internetMessageHeaders:[{name:'AUTO-SUBMITTED',value:'AUTO-REPLIED'}]},mailbox)));
