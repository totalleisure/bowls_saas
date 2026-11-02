import test from 'node:test';import assert from 'node:assert/strict';
import {handleRequest} from '../supabase/functions/send-graph-email/handler.ts';
import {sendCompetitionMail} from '../supabase/functions/_shared/competition_mail_transport.mjs';
import {dispatchCompetitionPublication} from '../supabase/functions/_shared/competition_publication_dispatch.mjs';
const env=n=>({SUPABASE_URL:'https://server.invalid',SUPABASE_SERVICE_ROLE_KEY:'key',MS_TENANT_ID:'tenant',MS_CLIENT_ID:'client',MS_CLIENT_SECRET:'secret',MS_MAILBOX:'sender@example.org'}[n]);
const request=()=>new Request('https://server.invalid',{method:'POST',headers:{Authorization:'Bearer key'},body:JSON.stringify({to:['recipient@example.org'],subject:'Test',html:'Test'})});
test('Global 20/minute refusal occurs before Graph and is explicitly retryable',async()=>{
 let calls=0;const response=await handleRequest(request(),env,async url=>{calls++;assert.match(url,/reserve_outbound_mail_slot/);return Response.json({allowed:false,retry_after_seconds:42});});
 assert.equal(response.status,429);assert.equal(calls,1);assert.equal((await response.json()).retry_after_seconds,42);
});
test('Unavailable limiter fails closed without sending',async()=>{
 const response=await handleRequest(request(),env,async()=>Response.json({error:'unavailable'},{status:503}));assert.equal(response.status,503);
});
test('Allowed slot is reserved before Graph token and send',async()=>{
 const calls=[];const response=await handleRequest(request(),env,async url=>{calls.push(url);return url.includes('reserve_')?Response.json({allowed:true}):url.includes('oauth2')?Response.json({access_token:'token'}):new Response(null,{status:202});});
 assert.equal(response.status,200);assert.equal(calls.length,3);assert.match(calls[0],/reserve_outbound_mail_slot/);
});
test('Competition transport consumes successful responses and exposes only definite throttles as retryable',async()=>{
 const args={url:'https://server.invalid',key:'key',projectRef:'egxdkaotepgfjmszxlyn',recipient:'wayne@totalleisure.com',message:{subject:'Test',html:'Test'}};
 const ok=Response.json({success:true});await sendCompetitionMail({...args,fetcher:async()=>ok});assert.equal(ok.bodyUsed,true);
 await assert.rejects(()=>sendCompetitionMail({...args,fetcher:async()=>Response.json({retry_after_seconds:90},{status:429})}),e=>e.retryable===true&&e.retryAfterSeconds===90);
 await assert.rejects(()=>sendCompetitionMail({...args,fetcher:async()=>{throw Error('Network timeout');}}),e=>e.retryable!==true);
});
test('Only a definite throttle requeues; ambiguous transport errors remain uncertain',async()=>{
 for(const retryable of [true,false]) {
  const recorded=[];
  const result=await dispatchCompetitionPublication({projectRef:'egxdkaotepgfjmszxlyn',snapshot:{},deliveries:[{recipient:'wayne@totalleisure.com',status:'claimed',attempt_count:1}],prepareMessage:()=>({}),saveMessage:async()=>{},send:async()=>{throw Object.assign(new Error('Transport failure'),{retryable});},finish:async(d,status,detail)=>recorded.push({status,detail})});
  assert.equal(result[0].status,retryable?'pending':'uncertain');
  assert.match(recorded[0].detail.error,/transport:/);
 }
});
