import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleRequest, processWrittenReply } from './handler.ts';
import { reminderText, responseTokenHash } from './written_reply.ts';
const mailbox='bowls-staging@totalleisure.com';
const values:Record<string,string>={SUPABASE_URL:'https://egxdkaotepgfjmszxlyn.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-key',MS_MAILBOX:mailbox,MS_TENANT_ID:'tenant',MS_CLIENT_ID:'client',MS_CLIENT_SECRET:'secret'};
const env=(name:string)=>values[name];
const fail=()=>{throw new Error('Unexpected dependency call')};
test('anonymous request rejected before database or Graph',async()=>assert.equal((await handleRequest(new Request('https://test',{method:'POST'}),{env,createClient:fail,fetch:fail})).status,401));
test('ordinary authenticated JWT cannot invoke privileged worker',async()=>assert.equal((await handleRequest(new Request('https://test',{method:'POST',headers:{Authorization:'Bearer user-jwt'}}),{env,createClient:fail,fetch:async(url,options)=>{assert(String(url).includes('/rest/v1/email_written_reply_settings'));assert.equal((options?.headers as any).Authorization,'Bearer user-jwt');return new Response(null,{status:403})}})).status,401));
test('production configuration cannot run staging worker',async()=>assert.equal((await handleRequest(new Request('https://test',{method:'POST',headers:{Authorization:'Bearer test-key'}}),{env:n=>n==='SUPABASE_URL'?'https://xfjelvvfoguzukgvxchh.supabase.co':env(n),createClient:fail,fetch:fail})).status,403));
const message={id:'graph',internetMessageId:'<reply@test>',subject:'Re: Selection',receivedDateTime:'2026-10-01T12:00:00Z',from:{emailAddress:{address:'member@example.test'}},body:{content:'Thanks'},internetMessageHeaders:[{name:'In-Reply-To',value:'<original@test>'}]};
const responseToken='RSP-'+'A'.repeat(48);
const original={internetMessageId:'<original@test>',subject:'Selection',sentDateTime:'2026-10-01T11:00:00Z',from:{emailAddress:{address:mailbox}},toRecipients:[{emailAddress:{address:'member@example.test'}}],body:{content:'ACCEPT DECLINE BWL-123456ABCDEF '+responseToken}};
for(const outcome of ['accepted','unknown','rejected','duplicate','lookup-empty','claim-error','lookup-error']) test('Graph integration '+outcome,async()=>{
 let claimed=false, sends=0, saved='';
 const db={rpc:async(name:string,args:any)=>{assert.equal(name,'claim_written_selection_reply');assert.equal(args.p_response_code,'BWL-123456ABCDEF');assert.equal(args.p_response_token_hash,await responseTokenHash(responseToken));assert(!JSON.stringify(args).includes(responseToken));claimed=true;return outcome==='claim-error'?{error:{message:'failed'}}:{data:{send_reminder:outcome!=='duplicate',recipient:'member@example.test',reply_id:'claim',response_protocol_version:2}}},from:(name:string)=>{assert.equal(name,'email_written_reply_reminders');return {update:(v:any)=>({eq:async()=>{saved=v.delivery_status;return {error:null}}})}}};
 const fetchMock=async(url:any,opts:any)=>{
   if(opts?.method==='POST') {assert(claimed);assert(String(url).endsWith('/sendMail'));sends++;const body=JSON.parse(opts.body);assert.equal(body.message.body.contentType,'HTML');assert(body.message.body.content.includes(reminderText));assert(body.message.body.content.includes('Accept selection'));assert(body.message.body.content.includes('Decline selection'));assert.deepEqual(body.message.toRecipients,[{emailAddress:{address:'member@example.test'}}]);if(outcome==='unknown')throw new Error('timeout');return new Response(null,{status:outcome==='rejected'?500:202});}
   assert(String(url).includes('/sentitems/messages?'));return new Response(JSON.stringify({value:outcome==='lookup-empty'?[]:[original]}),{status:outcome==='lookup-error'?500:200});
 };
 const run=()=>processWrittenReply(message,mailbox,'graph-token',db,fetchMock as typeof fetch);
 if(['claim-error','lookup-error'].includes(outcome)){await assert.rejects(run);assert.equal(sends,0);return;}
 await run();assert.equal(sends,['duplicate','lookup-empty'].includes(outcome)?0:1);
 if(sends)assert.equal(saved,outcome==='accepted'?'accepted':'failed_or_unknown');
});

for(const scenario of ['initial','historical-command','wrong-sender-command','support','support-quotes-selection','valid-command','verify','disabled']) test('full worker '+scenario,async()=>{
  let rpcCalls=0,sends=0,saved=0,reads=0;
  const cutoff=new Date(Date.now()-60000).toISOString();
  const cfg={enabled:scenario!=='disabled',enabled_at:cutoff,reminder_recipients:['member@example.test']};
  const db={from:(table:string)=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:table==='email_written_reply_settings'?cfg:{delta_link:scenario==='initial'?null:'https://graph.microsoft.com/delta',initialized_at:cutoff}})})}),upsert:async()=>{saved++;return {error:null}}}),rpc:async(name:string)=>{assert.equal(name,'apply_email_action_response');rpcCalls++;return {data:{ok:true,status:'processed'}}}};
  const http=async(url:any,opts:any)=>{
    const path=String(url);
    if(path.includes('oauth2'))return new Response(JSON.stringify({access_token:'test-token'}));
    if(path.includes('/mailFolders/inbox?$select=id'))return new Response(JSON.stringify({id:'inbox'}));
    if(path.includes('/sendMail')){sends++;throw new Error('Unexpected send');}
    if(path.includes('/messages/') && !path.includes('/messages/delta')){reads++;return new Response(JSON.stringify({...message,receivedDateTime:scenario==='historical-command'?'2020-01-01T00:00:00Z':new Date().toISOString(),from:{emailAddress:{address:scenario==='wrong-sender-command'?'someone@example.test':'member@example.test'}},subject:scenario.startsWith('support')?'Re: Support request':'Bowls response: ACCEPT BWL-123456ABCDEF',body:{content:scenario.startsWith('support')?'Can you fix this button?\n> ACCEPT BWL-123456ABCDEF':'ACCEPT BWL-123456ABCDEF'}}));}
    return new Response(JSON.stringify({value:[{id:'graph'}],'@odata.deltaLink':'https://graph.microsoft.com/new-delta'}));
  };
  const response=await handleRequest(new Request('https://test',{method:'POST',headers:{Authorization:'Bearer test-key'},body:JSON.stringify(scenario==='verify'?{mode:'verify'}:{})}),{env,createClient:()=>db,fetch:http as typeof fetch});
  assert.equal(response.status,scenario==='disabled'?409:200);
  assert.equal(sends,0);
  assert.equal(rpcCalls,scenario==='valid-command'?1:0);
  assert.equal(saved,['verify','disabled'].includes(scenario)?0:1);
  if(['initial','verify','disabled'].includes(scenario))assert.equal(reads,0);
});
