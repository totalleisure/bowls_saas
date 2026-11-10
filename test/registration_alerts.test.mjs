import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
function setup({route='new',already=false,fail=false,mailbox='staging@example.invalid',override}={}) {
 let handler,profileReads=0;const calls=[],deletions=[];
 const client={rpc:async(name,params)=>{calls.push({name,params});return {data:fail?null:'membership',error:fail?{message:'queue failed'}:null};},
 auth:{admin:{createUser:async()=>({data:{user:{id:'new-auth'}},error:null}),deleteUser:async(id)=>{deletions.push(id);},listUsers:async()=>({data:{users:route==='rebuild'?[{id:'existing-auth',email:'member@example.invalid'}]:[]},error:null})}},
 from(table){let operation='select';const query={select(){return this;},eq(){return this;},neq(){return this;},insert(){operation='insert';return this;},update(){operation='update';return this;},delete(){operation='delete';return this;},single(){return this.result();},maybeSingle(){return this.result();},result(){let data=null;if(table==='clubs')data={id:'club',name:'Test Club'};if(table==='member_profiles'){if(operation==='update'||operation==='insert')data={id:'profile',display_name:'Test Member'};else{profileReads++;data=profileReads>1?{id:'profile'}:route==='existing'?{id:'profile',user_id:'existing-auth',display_name:'Test Member'}:route==='orphan'?{id:'profile',user_id:null}:null;}}if(table==='club_memberships')data=already?{id:'membership',role:'guest'}:null;return Promise.resolve({data,error:null});},then(resolve,reject){return this.result().then(resolve,reject);}};return query;}};
 const source=stripTypeScriptTypes(fs.readFileSync(new URL('../supabase/functions/register_member/index.ts',import.meta.url),'utf8').replace(/^import\s[^;]+;\s*/gm,''));
 vm.runInNewContext(source,{Request,Response,console,DEFAULT_REGISTRATION_ALERT_MAILBOX:null,Deno:{env:{get(k){return {SUPABASE_URL:'https://example.invalid',SUPABASE_SERVICE_ROLE_KEY:'server',MS_MAILBOX:mailbox,REGISTRATION_ALERT_EMAIL:override}[k];}}},createClient:()=>client,serve(fn){handler=fn;}});
 return {calls,deletions,run:(extra={})=>handler(new Request('https://example.invalid',{method:'POST',body:JSON.stringify({club_id:'club',email:'member@example.invalid',first_name:'Test',surname:'Member',password:'never-in-alert',...extra})}))};
}
for(const route of ['new','existing','orphan','rebuild'])test(`registration ${route} completes membership and alerts atomically`,async()=>{const s=setup({route});const r=await s.run({alert_email:'attacker@example.invalid'});assert.equal(r.status,200);assert.equal(s.calls.length,1);assert.equal(s.calls[0].name,'complete_app_guest_registration');assert.equal(s.calls[0].params.p_alert_email,'staging@example.invalid');assert.equal(s.calls[0].params.p_allow_existing,route==='orphan');assert.ok(!JSON.stringify(s.calls).includes('never-in-alert'));});
test('existing registration is not notified again',async()=>{const s=setup({route:'existing',already:true});const r=await s.run();assert.equal(r.status,400);assert.equal(s.calls.length,0);});
test('notification queue failure prevents registration success and removes newly-created auth',async()=>{const s=setup({fail:true});const r=await s.run();assert.equal(r.status,400);assert.deepEqual(s.deletions,['new-auth']);});
test('deployment-owned alert override wins; request cannot set recipient',async()=>{const s=setup({override:'bowls@totalleisure.com'});await s.run({alert_email:'attacker@example.invalid'});assert.equal(s.calls[0].params.p_alert_email,'bowls@totalleisure.com');});
test('missing fields never queue registration alerts',async()=>{const s=setup();const r=await s.run({password:''});assert.equal(r.status,400);assert.equal(s.calls.length,0);});
