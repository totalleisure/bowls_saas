import test from 'node:test';
import assert from 'node:assert/strict';
import {clubSetupEnvironment,STAGING_URL,PRODUCTION_URL} from '../supabase/functions/_shared/club_setup_environment.mjs';
import {clubInvitationHtml} from '../supabase/functions/send-graph-email/club_invitation.mjs';
import {handleRequest} from '../supabase/functions/send-graph-email/handler.ts';
test('project and mailbox mapping is explicit and unknown environments fail closed',()=>{
 assert.deepEqual(clubSetupEnvironment(STAGING_URL),{staging:true,mailbox:'bowls-staging@totalleisure.com'});
 assert.deepEqual(clubSetupEnvironment(PRODUCTION_URL),{staging:false,mailbox:'bowls@totalleisure.com'});
 assert.throws(()=>clubSetupEnvironment('https://unknown.invalid'));
});
test('production invitation contains live app instructions and no staging directions',()=>{
 for(const password of [null,'Abc12345']) {
  const html=clubInvitationHtml({club:'Example club',email:'member@example.invalid',first_name:'Member'},password,false);
  assert.ok(!/staging|development PC/i.test(html));
  assert.match(html,/Accept invitation/); assert.match(html,/stays inactive/);
  assert.equal(html.includes('Initial password:'),password!==null);
 }
});
for(const [label,url,mailbox,to,status] of [
 ['staging blocks live recipient',STAGING_URL,'bowls-staging@totalleisure.com','member@example.invalid',403],
 ['staging allows exact two digit test alias',STAGING_URL,'bowls-staging@totalleisure.com','wayne.s.sayers+member01@gmail.com',200],
 ['staging allows exact three digit test alias',STAGING_URL,'bowls-staging@totalleisure.com','wayne.s.sayers+member004@gmail.com',200],
 ['staging blocks four digit alias',STAGING_URL,'bowls-staging@totalleisure.com','wayne.s.sayers+member0004@gmail.com',403],
 ['production uses its own mailbox',PRODUCTION_URL,'bowls@totalleisure.com','member@example.invalid',200],
 ['production rejects staging mailbox',PRODUCTION_URL,'bowls-staging@totalleisure.com','member@example.invalid',403],
 ['staging rejects production mailbox',STAGING_URL,'bowls@totalleisure.com','wayne@totalleisure.com',403],
]) test(label,async()=>{
 let calls=0;
 const env=n=>({SUPABASE_URL:url,SUPABASE_SERVICE_ROLE_KEY:'test-secret',MS_MAILBOX:mailbox,MS_TENANT_ID:'test-tenant',MS_CLIENT_ID:'test-client',MS_CLIENT_SECRET:'test-client-secret'}[n]);
 const response=await handleRequest(new Request('https://example.invalid',{method:'POST',headers:{Authorization:'Bearer test-secret'},body:JSON.stringify({to,subject:'Mock only',html:'Mock only'})}),env,async(u)=>{
  calls++; if(u.includes('reserve_outbound_mail_slot'))return Response.json({allowed:true});
  if(u.includes('oauth2'))return Response.json({access_token:'mock-token'});
  assert.match(u,new RegExp(encodeURIComponent(mailbox).replace(/[.*+?^${}()|[\]\\]/g,'\\$&')));
  return new Response(null,{status:202});
 });
 assert.equal(response.status,status);
 assert.equal(calls,status===200?3:0);
});
