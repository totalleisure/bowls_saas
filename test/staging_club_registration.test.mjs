import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,matchesClubQuery} from '../supabase/functions/staging-club-registration/handler.mjs';
test('failed club-name search does not offer unrelated nearby clubs',()=>{
 assert.equal(matchesClubQuery('Coney Hall','West Wickham Bowling Club'),false);
 assert.equal(matchesClubQuery('Coney Hall','Halls Bowls Club'),false);
 assert.equal(matchesClubQuery('South Hill Woods','South Hill Wood Bowling Club'),true);
 assert.equal(matchesClubQuery('New Beckenham Bromley','New Beckenham Bowls Club'),true);
});
const id='12345678-1234-1234-1234-123456789abc';
const place={placeId:'GooglePlace123',name:'Example Bowls Club',addressLine1:'Club Road',postcode:'BR1 1AA'};
function setup(overrides={}) {
 const calls=[],mail=[],logins=[];
 const handler=createHandler({project:'https://egxdkaotepgfjmszxlyn.supabase.co',hash:async x=>'hash:'+x,randomCode:()=> '123456',
  search:async()=>[place],details:async()=>place,
  service:async(action,data)=>{calls.push([action,data]);return action==='search'?{request_id:id}:action==='budget'?{}:{email:'wayne.s.sayers+member001@gmail.com'};},
  sendCode:async(...args)=>mail.push(args),login:async(email)=>{logins.push(email);return {hash:'one-use-sign-in-hash',type:'magiclink'};},...overrides});
 return {calls,mail,logins,call:async(body)=>{const r=await handler(new Request('https://example.invalid',{method:'POST',headers:{'x-forwarded-for':'test-network'},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};}};
}
const send={action:'send',request_id:id,place_id:place.placeId,email:'wayne.s.sayers+member001@gmail.com',first_name:'Test',last_name:'Secretary',phone:'07700123456',authority:true};
test('blocks deployment in another project',async()=>{assert.equal((await setup({project:'https://production.invalid'}).call({action:'search',query:'Bowls Club'})).status,403);});
test('global/server limit prevents Google and mail',async()=>{const s=setup({service:async()=>({limited:true}),search:()=>assert.fail('must not call Google')});assert.equal((await s.call({action:'search',query:'Bowls Club'})).status,429);});
test('search returns request ID with Google results',async()=>{const s=setup();assert.deepEqual((await s.call({action:'search',query:'Example Bowls Club'})).body,{request_id:id,places:[place]});assert.equal(s.mail.length,0);});
test('missing address offers contact without sending',async()=>{const s=setup({details:async()=>({...place,postcode:null})});assert.equal((await s.call(send)).body.contact,true);assert.equal(s.mail.length,0);});
test('blocked staging address never reaches email or Auth',async()=>{const s=setup({service:async a=>a==='budget'?{}:{error:'Not an approved staging address'}});assert.equal((await s.call(send)).status,400);assert.equal(s.mail.length,0);assert.equal(s.logins.length,0);});
test('duplicate club offers help without sending code',async()=>{const s=setup({service:async a=>a==='budget'?{}:{duplicates:['Already Here Bowls Club']}});assert.deepEqual((await s.call(send)).body.duplicates,['Already Here Bowls Club']);assert.equal(s.mail.length,0);});
test('only hashed code stored and no code/token disclosed before verification',async()=>{const s=setup();const r=await s.call(send);assert.equal(r.body.sent,true);assert.equal(JSON.stringify(r.body).includes('123456'),false);assert.equal(s.calls.find(c=>c[0]==='send')[1].code_hash,'hash:'+id+':123456');assert.equal(s.mail.length,1);assert.equal(s.logins.length,0);});
test('wrong code never issues a sign-in token',async()=>{const s=setup({service:async a=>a==='budget'?{}:{error:'Wrong code'}});assert.equal((await s.call({action:'verify',request_id:id,code:'654321'})).status,400);assert.equal(s.logins.length,0);});
test('successful one-use challenge releases standard sign-in token',async()=>{const s=setup();assert.deepEqual((await s.call({action:'verify',request_id:id,code:'123456'})).body,{verified:true,token_hash:'one-use-sign-in-hash',token_type:'magiclink'});assert.equal(s.logins.length,1);});
test('club website follows the same server duplicate checks without sending email',async()=>{
 const s=setup({website:async()=>({...place,source:'website',websiteUrl:'https://club.org/'})});
 const r=await s.call({action:'website',query:'Example Bowls Club',website_url:'https://club.org/'});
 assert.equal(r.body.places[0].source,'website');assert.equal(s.calls[1][0],'search');assert.equal(s.mail.length,0);
});
test('invented candidate cannot reach details lookup or code delivery',async()=>{
 const s=setup({service:async a=>a==='candidate'?{error:'Choose your saved club'}:{},details:()=>assert.fail('Untrusted candidate fetched')});
 assert.equal((await s.call(send)).status,400);assert.equal(s.mail.length,0);
});
