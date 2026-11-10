import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleEmailChange} from './handler.mjs';
const club='11111111-1111-4111-8111-111111111111',member='22222222-2222-4222-8222-222222222222';
const change='33333333-3333-4333-8333-333333333333',user='44444444-4444-4444-8444-444444444444';
const request=(overrides={},token=true)=>new Request('https://example.invalid',{method:'POST',
  headers:token?{Authorization:'Bearer token'}:{},body:JSON.stringify({club_id:club,member_profile_id:member,
    expected_email:'old@example.invalid',email:'new@example.invalid',...overrides})});
function fixture({authError=false,prepareError=null,verified=true,verifyError=false,updateThrows=false}={}){
 const calls=[];
 const admin={auth:{getUser:async()=>({data:{user:authError?null:{id:'validated-actor'}},error:authError}),
   admin:{updateUserById:async(...args)=>{calls.push(['auth',...args]);if(updateThrows)throw Error('Internal token detail');return {error:null};}}},
   rpc:async(name,args)=>{calls.push([name,args]);return name==='begin_admin_member_email_change'?
     {data:{change_id:change,user_id:user,new_email:'new@example.invalid'},error:prepareError}:
     {data:{changed:verified,email:'new@example.invalid'},error:verifyError?Error('internal detail'):null};}};
 return {calls,admin};
}
test('verified actor is authorized server-side; only email is changed and verified',async()=>{
 const f=fixture();const r=await handleEmailChange(request({actor_user_id:'spoofed'}),f.admin);
 assert.equal(r.status,200);assert.deepEqual(await r.json(),{changed:true,email:'new@example.invalid'});
 assert.equal(f.calls[0][1].p_actor_user_id,'validated-actor');
 assert.deepEqual(f.calls[1],['auth',user,{email:'new@example.invalid',email_confirm:true}]);
 assert.deepEqual(f.calls[2],['finish_admin_member_email_change',{p_change_id:change}]);
});
for(const [code,status] of [['42501',403],['22023',400],['23505',409],['40001',409],['55000',409]]){
 test(`rejects database authorization/validation ${code} before Auth mutation`,async()=>{
  const f=fixture({prepareError:{code,message:'Safe validation message'}});
  assert.equal((await handleEmailChange(request(),f.admin)).status,status);
  assert.equal(f.calls.filter(c=>c[0]==='auth').length,0);
 });
}
test('requires valid session and request',async()=>{
 const f=fixture();assert.equal((await handleEmailChange(request({},false),f.admin)).status,401);
 for(const body of [{email:'bad'},{email:'a b@example.invalid'},{member_profile_id:'invalid'},{expected_email:''}])
  assert.equal((await handleEmailChange(request(body),f.admin)).status,400);
 assert.equal(f.calls.length,0);
 assert.equal((await handleEmailChange(request(),fixture({authError:true}).admin)).status,401);
});
test('a lost Auth response is resolved from persistent account/profile state',async()=>{
 const f=fixture({updateThrows:true});const r=await handleEmailChange(request(),f.admin);
 assert.equal(r.status,200);assert.equal((await r.json()).changed,true);
});
test('unverified update and verification outage never report success',async()=>{
 assert.equal((await handleEmailChange(request(),fixture({verified:false}).admin)).status,400);
 const r=await handleEmailChange(request(),fixture({verifyError:true}).admin);
 assert.equal(r.status,503);assert.ok(!(await r.text()).includes('internal detail'));
});
test('unexpected preparation errors are sanitized and cannot mutate Auth',async()=>{
 const f=fixture({prepareError:{code:'XX000',message:'secret database internals'}});
 const r=await handleEmailChange(request(),f.admin);assert.equal(r.status,500);
 assert.ok(!(await r.text()).includes('secret'));assert.equal(f.calls.length,1);
});
test('normalizes email addresses and supports preflight without authentication',async()=>{
 const f=fixture();await handleEmailChange(request({email:' NEW@EXAMPLE.INVALID ',expected_email:' OLD@EXAMPLE.INVALID '}),f.admin);
 assert.equal(f.calls[0][1].p_new_email,'new@example.invalid');
 assert.equal(f.calls[0][1].p_expected_email,'old@example.invalid');
 assert.equal((await handleEmailChange(new Request('https://example.invalid',{method:'OPTIONS'}),f.admin)).status,200);
});
