import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleEnableLogin} from './handler.mjs';
const club='11111111-1111-4111-8111-111111111111', target='22222222-2222-4222-8222-222222222222';
const request=(token=true)=>new Request('https://example.invalid',{method:'POST',headers:token?{Authorization:'Bearer example'}:{},body:JSON.stringify({club_id:club,member_profile_id:target,email:' Member@example.invalid '})});
function fixture({role='admin',active=true,linked=false,createError=false,linkError=false,foreign=false}={}) {
 const calls=[];
 const rows={app_superusers:[],member_profiles:[{id:'actor-profile',user_id:'actor'},{id:target,user_id:linked?'existing':null,is_captain_managed:!linked,display_name:'Member'}],club_memberships:[{id:'a',club_id:club,member_profile_id:'actor-profile',role,is_active:active},...foreign?[]:[{id:'t',club_id:club,member_profile_id:target,is_active:true}]]};
 const admin={from(table){const filters=[];const q={select(){return q},eq(k,v){filters.push([k,v]);return q},async maybeSingle(){return {data:rows[table].find(r=>filters.every(([k,v])=>r[k]===v))??null}}};return q},auth:{getUser:async()=>({data:{user:{id:'actor'}}}),admin:{createUser:async v=>{calls.push(['create',v]);if(!createError&&!linkError){rows.member_profiles[1].user_id='created';rows.member_profiles[1].is_captain_managed=false;}return {data:{user:createError?null:{id:'created'}},error:createError}},getUserById:async()=>({data:{user:{email:'member@example.invalid',app_metadata:{}}}})},resetPasswordForEmail:async v=>{calls.push(['email',v]);return {error:false}}}};
 return {admin,calls};
}
test('conversion uses trusted target metadata and does not send a premature recovery code',async()=>{const f=fixture();const r=await handleEnableLogin(request(),f.admin);assert.equal(r.status,200);assert.deepEqual(await r.json(),{enabled:true,email:'member@example.invalid',setup_sent:false});assert.equal(f.calls[0][1].app_metadata.captain_managed_profile_id,target);assert.equal(f.calls[0][1].email_confirm,false);assert.equal(f.calls.some(c=>c[0]==='email'),false);});
for(const [name,options,status] of [['non-admin',{role:'member'},403],['inactive',{active:false},403],['foreign member',{foreign:true},403],['existing account',{linked:true},409],['duplicate email',{createError:true},409]]) test(`reject ${name}`,async()=>{const f=fixture(options);const r=await handleEnableLogin(request(),f.admin);assert.equal(r.status,status);assert.equal(f.calls.some(c=>c[0]==='email'),false);});
test('missing token never mutates',async()=>{const f=fixture();assert.equal((await handleEnableLogin(request(false),f.admin)).status,401);assert.equal(f.calls.length,0)});
test('does not claim success when Auth created an unlinked profile',async()=>{const f=fixture({linkError:true});const r=await handleEnableLogin(request(),f.admin);assert.equal(r.status,409);assert.equal(f.calls.some(c=>c[0]==='email'),false)});
