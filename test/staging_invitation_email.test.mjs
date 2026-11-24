import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareClubInvitation,clubInvitationHtml,initialPassword,STORE_LINKS} from '../supabase/functions/send-graph-email/club_invitation.mjs';
const context={club:'Coney <Hall>',email:'wayne.s.sayers+member003@gmail.com',first_name:'Wayne',user_id:'test-user',new_user:true};
const input={queueId:'queue',to:context.email,url:'https://example.invalid',key:'test-only',html:'Original mail'};
test('new user receives the generated password; it is not included in the queue/context request',async()=>{
 const calls=[];let password;
 const html=await prepareClubInvitation({...input,fetcher:async(url,options={})=>{
  calls.push({url,options});
  if(url.includes('/rpc/')){assert.ok(!options.body.includes('password'));return Response.json(context);}
  if(options.method==='PUT'){password=JSON.parse(options.body).password;return Response.json({});}
  return Response.json({email:context.email,last_sign_in_at:null});
 }});
 assert.equal(calls.filter(c=>c.options.method==='PUT').length,1);
 assert.match(password,/^[A-Z][a-z]{2}[0-9]{5}$/);assert.ok(html.includes(password));
 assert.ok(html.includes('Coney &lt;Hall&gt;'));assert.ok(html.includes('staging App already installed'));
 assert.ok(html.includes('Accept invitation'));assert.ok(html.includes('stays inactive'));
 for(const [,url] of STORE_LINKS)assert.ok(html.includes(url));
});
test('existing user password is never read or changed, including another club user',async()=>{
 let calls=0;
 const html=await prepareClubInvitation({...input,fetcher:async(url)=>{
  calls++;assert.ok(url.includes('/rpc/'));return Response.json({...context,new_user:false});
 }});
 assert.equal(calls,1);assert.ok(html.includes('Use your current password'));
 assert.ok(!html.includes('Initial password:'));
});
test('new account that has since signed in keeps its chosen password',async()=>{
 const html=await prepareClubInvitation({...input,fetcher:async(url,options={})=>{
  assert.notEqual(options.method,'PUT');
  return Response.json(url.includes('/rpc/')?context:{email:context.email,last_sign_in_at:'2026-11-22'});
 }});
 assert.ok(!html.includes('Initial password:'));
});
test('unrelated queued emails retain their original content',async()=>{
 assert.equal(await prepareClubInvitation({...input,fetcher:async()=>Response.json(null)}),'Original mail');
});
test('failed eligibility, changed login email, or password preparation fails closed',async()=>{
 await assert.rejects(prepareClubInvitation({...input,fetcher:async()=>new Response(null,{status:403})}));
 await assert.rejects(prepareClubInvitation({...input,fetcher:async url=>Response.json(url.includes('/rpc/')?context:{email:'changed@example.org'})}));
 await assert.rejects(prepareClubInvitation({...input,fetcher:async(url,options={})=>options.method==='PUT'?new Response(null,{status:500}):Response.json(url.includes('/rpc/')?context:{email:context.email})}));
});
test('generated passwords differ and existing template has no credential placeholder',()=>{
 assert.notEqual(initialPassword(),initialPassword());
 assert.ok(!clubInvitationHtml({...context,new_user:false}).includes('[generated password]'));
});
