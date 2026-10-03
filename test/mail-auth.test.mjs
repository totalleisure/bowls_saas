import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleRequest as team } from '../supabase/functions/send-team-sheet-emails/handler.ts';
import { handleRequest as graph } from '../supabase/functions/send-graph-email/handler.ts';
const fixtureId = '11111111-1111-4111-8111-111111111111';
const env = n => ({SUPABASE_URL:'https://test.invalid',SUPABASE_SERVICE_ROLE_KEY:'server-secret',MS_TENANT_ID:'tenant',MS_CLIENT_ID:'client',MS_CLIENT_SECRET:'secret',MS_MAILBOX:'mailbox'}[n]);
const body = {fixture_id:fixtureId,club_name:'Club',opponent:'Opponent',start_at:'2026-09-24',recipients:[{email:'test@example.invalid',type:'player'}]};
const request = (token='user-token', data=body) => new Request('https://test.invalid',{method:'POST',headers:token?{Authorization:`Bearer ${token}`}:{},body:JSON.stringify(data)});
function mock({role='member',active=true,captain=false,vice=false,superuser=false,missing=false,invalid=false,anonymous=false,fail=false}={}) {
  const writes=[];
  const fetch=async (url,options={})=>{
    const u=new URL(url);
    if(u.pathname==='/auth/v1/user') return Response.json({id:'user-id',is_anonymous:anonymous},{status:invalid?401:200});
    if((options.method??'GET')!=='GET') {writes.push([u,options]);return Response.json({ok:true});}
    assert.equal(new Headers(options.headers).get('Authorization'),'Bearer server-secret');
    if(fail) return Response.json({},{status:500});
    if(u.pathname.endsWith('/fixtures')) {assert.equal(u.searchParams.get('id'),`eq.${fixtureId}`);return Response.json(missing?[]:[{id:fixtureId,club_id:'club-id',captain_member_profile_id:captain?'profile-id':null,vice_captain_member_profile_id:vice?'profile-id':null}]);}
    if(u.pathname.endsWith('/app_superusers')) {assert.equal(u.searchParams.get('user_id'),'eq.user-id');return Response.json(superuser?[{user_id:'user-id'}]:[]);}
    if(u.pathname.endsWith('/member_profiles')) {assert.equal(u.searchParams.get('user_id'),'eq.user-id');return Response.json([{id:'profile-id'}]);}
    if(u.pathname.endsWith('/club_memberships')) {assert.equal(u.searchParams.get('club_id'),'eq.club-id');assert.equal(u.searchParams.get('member_profile_id'),'eq.profile-id');assert.equal(u.searchParams.get('is_active'),'eq.true');return Response.json(active?[{role,is_active:true}]:[]);}
    throw new Error(`Unexpected request ${url}`);
  };
  return {fetch,writes};
}
for(const [name,options,status] of [
  ['ordinary member',{},403],['inactive admin',{role:'admin',active:false},403],
  ['other club or absent membership',{active:false},403],['inactive captain',{captain:true,active:false},403],
  ['guest captain',{captain:true,role:'guest'},403],['unknown fixture',{missing:true},403],
  ['invalid session',{invalid:true},401],['anonymous account',{anonymous:true},401],['lookup failure',{fail:true},500],
  ['admin',{role:'admin'},200],['selector',{role:'selector'},200],['captain',{captain:true},200],
  ['vice captain',{vice:true},200],['superuser',{superuser:true,active:false},200],
]) test(name,async()=>{const m=mock(options);const r=await team(request(),env,m.fetch);assert.equal(r.status,status);assert.equal(m.writes.length,status===200?3:0);if(status===200){assert.equal(m.writes[2][0].searchParams.get('club_id'),'eq.club-id');}});
test('missing token blocks before all network calls',async()=>{assert.equal((await team(request(null),env,()=>{throw Error('Network forbidden');})).status,401);});
test('invalid fixture cannot inject filters',async()=>{const m=mock();assert.equal((await team(request('user-token',{...body,fixture_id:fixtureId+'&id=neq.x'}),env,m.fetch)).status,400);assert.equal(m.writes.length,0);});
for(const token of [null,'user-token','forged-service-token']) test(`Graph denies ${token}`,async()=>{assert.equal((await graph(request(token),env,()=>{throw Error('Network forbidden');})).status,401);});
test('Graph accepts server credential with mocked Microsoft delivery',async()=>{let calls=0;const response=await graph(request('server-secret',{to:'test@example.invalid',subject:'test',html:'test'}),env,async()=>{calls++;return calls===1?Response.json({access_token:'mock'}):new Response(null,{status:202});});assert.equal(response.status,200);assert.equal(calls,2);});
