import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleRequest } from './handler.ts';

const production=process.env.WORKER_ENV==='production';
const mailbox=production?'bowls@totalleisure.com':'bowls-staging@totalleisure.com';
const project=production?'xfjelvvfoguzukgvxchh':'egxdkaotepgfjmszxlyn';
for(const scenario of ['active_members','allowlisted','not_allowlisted','historical']) {
  test(`${production?'production':'staging'} worker routes written reply: ${scenario}`,async()=>{
    const received=new Date(Date.now()-(scenario==='historical'?120000:0)).toISOString();
    const sent=new Date(Date.now()-180000).toISOString();
    const sender='new-member@example.test';
    const code='BWL-123456ABCDEF';
    const credential='RSP-'+'A'.repeat(48);
    const message={id:'inbound',internetMessageId:'<new-reply@test>',subject:'Re: Team selection',receivedDateTime:received,
      from:{emailAddress:{address:sender}},body:{content:'Thanks, I can play'},
      internetMessageHeaders:[{name:'In-Reply-To',value:'<original@test>'}]};
    const original={internetMessageId:'<original@test>',subject:'Team selection',sentDateTime:sent,
      from:{emailAddress:{address:mailbox}},toRecipients:[{emailAddress:{address:sender}}],
      body:{content:`ACCEPT DECLINE ${code} ${credential}`}};
    let claims=0,sends=0;
    const config={enabled:true,enabled_at:new Date(Date.now()-60000).toISOString(),
      sender_scope:scenario==='active_members'?'active_members':'allowlist',
      reminder_recipients:scenario==='not_allowlisted'?[]:[sender]};
    const db={from:(name:string)=>{
      if(name==='email_written_reply_settings')return {select:()=>({eq:()=>({maybeSingle:async()=>({data:config})})})};
      if(name==='email_inbox_sync_state')return {select:()=>({eq:()=>({maybeSingle:async()=>({data:{delta_link:'https://graph.microsoft.com/delta'}})})}),upsert:async()=>({error:null})};
      if(name==='member_profiles')return {select:()=>({ilike:()=>({eq:()=>({limit:async()=>({data:[{id:'member'}]})})})})};
      throw Error('Unexpected table '+name);
    },rpc:async(name:string,args:any)=>{
      assert.equal(name,'claim_written_selection_reply');
      assert.equal(args.p_sender_email,sender);
      assert.equal(args.p_excerpt,'Thanks, I can play');
      assert.equal(args.p_response_token_hash.length,64);
      claims++;return {data:{status:'recorded',send_reminder:false}};
    }};
    const fetchMock=async(url:any,options:any)=>{
      const u=String(url);
      if(u.includes('oauth2'))return new Response(JSON.stringify({access_token:'graph-test'}));
      if(u.includes('/sendMail')){sends++;throw Error('Unexpected send');}
      if(u.includes('/sentitems/messages?'))return new Response(JSON.stringify({value:[original]}));
      if(u.includes('/messages/inbound'))return new Response(JSON.stringify(message));
      if(u==='https://graph.microsoft.com/delta')return new Response(JSON.stringify({value:[{id:'inbound'}],'@odata.deltaLink':'https://graph.microsoft.com/next'}));
      throw Error('Unexpected URL '+u);
    };
    const env=(key:string)=>({SUPABASE_URL:`https://${project}.supabase.co`,SUPABASE_SERVICE_ROLE_KEY:'worker-test',MS_MAILBOX:mailbox,MS_TENANT_ID:'tenant',MS_CLIENT_ID:'client',MS_CLIENT_SECRET:'secret'} as Record<string,string>)[key];
    const response=await handleRequest(new Request('https://test',{method:'POST',headers:{Authorization:'Bearer worker-test'},body:'{}'}),{env,createClient:()=>db,fetch:fetchMock as typeof fetch});
    assert.equal(response.status,200,await response.text());
    assert.equal(claims,['active_members','allowlisted'].includes(scenario)?1:0);
    assert.equal(sends,0);
  });
}
