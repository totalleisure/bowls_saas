import {test} from 'node:test';
import assert from 'node:assert/strict';
import {viewFixture} from './handler.mjs';
const code='BWL-123456ABCDEF',token='RSP-'+'A'.repeat(48);
const req=()=>new Request('https://example.test/?code='+code+'&token='+token);
function db({status='pending',expires='2036-01-01',member=true,found=true,cancelled=false}={}) {
 const calls=[];
 return {calls,from(table){const q={select(){return q},eq(k,v){calls.push([table,k,v]);return q},async maybeSingle(){return {data:table==='email_action_requests'?(found?{fixture_id:'replacement',team_selection_id:'new-team',target_record_id:'reserve-row',member_profile_id:'member',status,expires_at:expires}:null):table==='team_selection_members'?(member?{id:'reserve-row'}:null):{id:'replacement',team_name:'Replacement <script>bad</script>',start_at:'2030-01-01T12:00:00Z',is_home:true,notes:'Bring bowls',cancelled_at:cancelled?'now':null,venue:{name:'Test club'}}}}};return q}};
}
for(const status of ['pending','responded'])test('read-only replacement view for '+status,async()=>{const d=db({status});const r=await viewFixture(req(),d,0);const html=await r.text();assert.equal(r.status,200);assert(html.includes('Replacement &lt;script&gt;'));assert(!html.includes('<script>'));assert(d.calls.some(x=>x[0]==='fixtures'&&x[1]==='id'&&x[2]==='replacement'));assert(d.calls.some(x=>x[1]==='response_token_hash'&&x[2].length===64));assert.equal(r.headers.get('referrer-policy'),'no-referrer');});
for(const opts of [{status:'cancelled'},{expires:'2000-01-01'},{member:false},{found:false}])test('reject unavailable credential '+JSON.stringify(opts),async()=>assert.equal((await viewFixture(req(),db(opts),Date.now())).status,403));
test('malformed credentials never query database',async()=>{const d=db();assert.equal((await viewFixture(new Request('https://example.test'),d)).status,403);assert.equal(d.calls.length,0)});
test('cancelled fixture never requests response',async()=>{const r=await viewFixture(req(),db({cancelled:true}),0);const h=await r.text();assert(h.includes('Fixture cancelled'));assert(!h.includes('choose Accept'));});
