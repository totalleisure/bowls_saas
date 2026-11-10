import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { loadFixtureCalendar, fixtureCalendarHtml } from '../supabase/functions/process-email-queue/fixture_calendar.mjs';
import { clubMessageHtml, invitationHtml, invitationContent, APP_EMAIL_FOOTER } from '../supabase/functions/member_invitations/email.ts';

test('mailing messages share the invitation footer without invitation credentials or registration content',()=>{
 const html=clubMessageHtml({club:'Lewisham',subject:'New version',message:'Hello members\n\n## Diary\n- All fixtures\n- Clearer dates',primaryColour:'#0057B8',secondaryColour:'#FFD200'});
 assert.ok(html.includes(APP_EMAIL_FOOTER));assert.ok(invitationHtml(invitationContent('Test','x@example.invalid','Lewisham')).includes(APP_EMAIL_FOOTER));
 assert.ok(html.includes('#0057B8'));assert.ok(html.includes('#FFD200'));assert.ok(html.includes('<li'));assert.ok(html.includes('>Diary</h2>'));
 assert.ok(!html.includes('Your login details'));assert.ok(!html.includes('Initial password'));assert.ok(!html.includes('account has been set up'));
});
test('author text is escaped, only http links become links and injected colours fall back',()=>{
 const html=clubMessageHtml({club:'<img onerror="bad">',subject:'<script>bad</script>',message:'<svg onload="bad">\n\njavascript:bad\n\nhttps://example.com/?a=1&b=2',primaryColour:'red;bad',secondaryColour:'url(bad)'});
 assert.ok(!html.includes('<script>'));assert.ok(!html.includes('<img'));assert.ok(!html.includes('<svg'));assert.ok(!html.includes('href="javascript:'));
 assert.ok(html.includes('https://example.com/?a=1&amp;b=2'));assert.ok(html.includes('#153f32'));
});
function setup({type='mailing_list_message',messageError=false,wrongList=false,identity="club",identityError=false,approved=false,approvedHtml=null}={}){
 let handler;const sent=[],updates=[];
 const attachment={name:'guide.pdf',contentType:'application/pdf',contentBytes:'JVBERi0='};
 const email={id:'queue',recipient_email:'member@example.invalid',subject:'Update',body:'Hello\n\n## Changes\n- Clearer diary',event_type:type,payload:{mailing_list_message_id:'message',mailing_list_id:'list'},attachments:[attachment]};
 email.payload.approved_marketing_layout=approved;
 const client={rpc(name){return Promise.resolve({data:name==='mailing_list_approved_html'?approvedHtml:identity,error:identityError?{message:"Unavailable"}:null});},from(table){let update=null;return {select(){return this;},eq(){return this;},order(){return this;},limit(){return Promise.resolve({data:[email],error:null});},update(value){update=value;updates.push(value);return this;},single(){return Promise.resolve(table==='mailing_list_messages'?{data:{club_id:'club',mailing_list_id:wrongList?'other':'list'},error:messageError?{message:'No access'}:null}:{data:{name:'Lewisham',primary_colour:'#0057B8',secondary_colour:'#FFD200'},error:null});},then(resolve){resolve({data:null,error:null});}};}};
 const source=stripTypeScriptTypes(fs.readFileSync(new URL('../supabase/functions/process-email-queue/index.ts',import.meta.url),'utf8').replace(/^import\s[^;]+;\s*/gm,''));
 const context=vm.createContext({Request,Response,Headers,URL,console,Error,Uint8Array,TextEncoder,crypto,Date,atob,
  loadFixtureCalendar,fixtureCalendarHtml,
  Deno:{env:{get(name){return {SUPABASE_URL:'https://example.invalid',SUPABASE_SERVICE_ROLE_KEY:'server',MS_MAILBOX:'mail@example.invalid'}[name];}}},
  serve(fn){handler=fn;},createClient(){return client;},isVerifiedWorker:async bearer=>bearer==='server',
  clubMessageHtml,buildEmailActionBlock:()=>'',fetch:async (url,init)=>{sent.push(JSON.parse(init.body));return Response.json({ok:true});},
 });
 vm.runInContext(source,context);
 return {sent,updates,attachment,run:()=>handler(new Request('https://example.invalid',{method:'POST',headers:{Authorization:'Bearer server'},body:'{}'}))};
}
test('worker brands mailing-list email and preserves its exact attachment',async()=>{
 const s=setup();const response=await s.run();assert.equal(response.status,200);assert.equal((await response.json()).processed,1);
 assert.equal(s.sent.length,1);assert.ok(s.sent[0].html.includes('Your Club. Your Way.'));assert.deepEqual(s.sent[0].attachments,[s.attachment]);
 assert.equal(s.sent[0].to,'member@example.invalid');assert.equal(s.updates.at(-1).status,'sent');
});
test('ordinary fixture email retains its existing rendering and attachments',async()=>{
 const s=setup({type:'ordinary_fixture_notice'});await s.run();assert.equal(s.sent.length,1);
 assert.ok(!s.sent[0].html.includes('Your Club. Your Way.'));assert.ok(s.sent[0].html.includes('Hello<br>'));assert.deepEqual(s.sent[0].attachments,[s.attachment]);
});
for(const options of [{messageError:true},{wrongList:true}])test('unverified mailing message fails without sending',async()=>{
 const s=setup(options);await s.run();assert.equal(s.sent.length,0);assert.equal(s.updates.at(-1).status,'failed');
});

test('company branding requires verified server identity',async()=>{const s=setup({identity:'total_leisure'});await s.run();assert.equal(s.sent.length,1);assert.ok(s.sent[0].html.includes('For members of'));assert.ok(s.sent[0].html.includes('Total Leisure'));});
test('identity lookup fails closed',async()=>{const s=setup({identityError:true});await s.run();assert.equal(s.sent.length,0);assert.equal(s.updates.at(-1).status,'failed');});

test('Approved layout is used exactly, including personalised greeting and badge',async()=>{const html='<p>Dear Jenny,</p><img src="cid:club-badge">';const s=setup({approved:true,approvedHtml:html});await s.run();assert.equal(s.sent[0].html,html);});
test('Missing approved layout fails closed without sending',async()=>{const s=setup({approved:true});await s.run();assert.equal(s.sent.length,0);assert.equal(s.updates.at(-1).status,'failed');});
