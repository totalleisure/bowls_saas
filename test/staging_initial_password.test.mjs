import test from 'node:test';
import assert from 'node:assert/strict';
import {initialPassword,prepareClubInvitation} from '../supabase/functions/send-graph-email/club_invitation.mjs';
test('initial passwords use exactly capital letter, two lower-case letters and five digits',()=>{
 const values=Array.from({length:1000},()=>initialPassword());
 for(const value of values)assert.match(value,/^[A-Z][a-z]{2}[0-9]{5}$/);
 assert.ok(new Set(values).size>990);
});
test('explicit test reissue records a fresh decision without changing membership',async()=>{
 let updated=false,recorded=false;
 const context={email:'wayne.s.sayers+member004@gmail.com',club:'Coney Hall',first_name:'Wayne',user_id:'test-user',new_user:true,reissue_initial:true};
 await prepareClubInvitation({queueId:'queue',to:context.email,url:'https://example.invalid',key:'test-only',html:'old',fetcher:async(url,options={})=>{
  if(url.includes('delivery_context'))return Response.json(context);
  if(url.includes('record_staging')){recorded=true;return Response.json(null);}
  if(options.method==='PUT'){updated=true;assert.deepEqual(Object.keys(JSON.parse(options.body)),['password']);return Response.json({});}
  return Response.json({email:context.email,last_sign_in_at:'2026-11-22'});
 }});
 assert.ok(updated&&recorded);
});
