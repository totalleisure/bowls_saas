import test from 'node:test';
import assert from 'node:assert/strict';
import {provisionContact} from '../supabase/functions/staging-onboarding-invitations/provision.mjs';
function mock(existing=null,deny=false) {
 const calls=[];
 const admin={calls,rpc:async(name,args)=>{
  calls.push([name,args]);
  if(name==='staging_invitation_contact_context')return {data:deny?null:{club_id:'club',user_id:existing,email:'new@example.invalid',first_name:'New',last_name:'Member'},error:deny?{}:null};
  return {data:{queued:1},error:null};
 },auth:{admin:{createUser:async(attributes)=>{calls.push(['createUser',attributes]);return {data:{user:{id:'new-user'}},error:null};}}}};
 return admin;
}
test('recognised member reuses Auth identity without password or account changes',async()=>{
 const admin=mock('existing-user');
 await provisionContact(admin,'contact','caller','club');
 assert.equal(admin.calls.some(c=>c[0]==='createUser'),false);
 assert.equal(admin.calls.at(-1)[1].p_user,'existing-user');
});
test('new account is created only by explicit invitation provisioning, with no password or automatic email',async()=>{
 const admin=mock();
 await provisionContact(admin,'contact','caller','club');
 assert.deepEqual(admin.calls.map(c=>c[0]),['staging_invitation_contact_context','createUser','finish_staging_invitation_contact']);
 const attributes=admin.calls[1][1];
 assert.equal(attributes.app_metadata.staging_onboarding_contact_id,'contact');
 assert.equal('password' in attributes,false);
 assert.equal(admin.calls.at(-1)[1].p_user,'new-user');
});
test('blocked recipient or wrong club never creates an account',async()=>{
 for(const admin of [mock(null,true),mock()]){
  await assert.rejects(provisionContact(admin,'contact','caller',admin.calls.length?'club':'wrong-club'));
  assert.equal(admin.calls.some(c=>c[0]==='createUser'),false);
 }
});
