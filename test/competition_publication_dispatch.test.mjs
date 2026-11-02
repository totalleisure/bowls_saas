import test from 'node:test';
import assert from 'node:assert/strict';
import {dispatchCompetitionPublication} from '../supabase/functions/_shared/competition_publication_dispatch.mjs';
import {prepareCompetitionPublicationMessage} from '../supabase/functions/_shared/competition_publication_email.mjs';
const recipient='wayne@totalleisure.com';
const snapshot={clubName:'Club',competitions:[{id:'c',name:'Mens Pairs',settings:{rules:'No dead ends',dress:'Whites'}}],entries:[{id:'a',competition_id:'c',name:'Wayne / Partner'},{id:'b',competition_id:'c',name:'Opponent pair'}],entryMembers:[{entry_id:'a',member_profile_id:'me'},{entry_id:'b',member_profile_id:'opponent'}],rounds:[{id:'r',competition_id:'c',round_number:1,name:'Final',play_by:'2027-04-03',rule_overrides:{dress:'Greys'}}],matches:[{id:'m',competition_id:'c',round_id:'r',status:'to_be_arranged',side_a_entry_id:'a',side_b_entry_id:'b'}],profiles:[{id:'me',first_name:'Wayne',email_address:recipient},{id:'opponent',first_name:'Opponent',email_address:'opponent@example.org'}]};
const delivery={id:'d',member_profile_id:'me',recipient,status:'claimed'};
test('publication is specific to one competition and applies effective round rules',()=>{
 const m=prepareCompetitionPublicationMessage(snapshot,delivery);
 assert.equal(m.content.entries.length,1);assert.equal(m.subject,'Mens Pairs — draw published');
 assert.match(m.html,/Mens Pairs — draw published/);assert.match(m.html,/Dress: Greys/);assert.doesNotMatch(m.html,/Dress: Whites/);
 assert.throws(()=>prepareCompetitionPublicationMessage({...snapshot,competitions:[...snapshot.competitions,{id:'other'}]},delivery));
 assert.throws(()=>prepareCompetitionPublicationMessage(snapshot,{...delivery,recipient:'wayne.sayers@me.com'}));
});
test('dispatch refuses production, non-approved recipients and previously attempted rows before sending',async()=>{
 let sends=0;
 const args={snapshot,deliveries:[delivery],saveMessage:async()=>{},send:async()=>sends++,finish:async()=>{}};
 await assert.rejects(()=>dispatchCompetitionPublication({...args,projectRef:'unknown-project'}));
 await assert.rejects(()=>dispatchCompetitionPublication({...args,projectRef:'egxdkaotepgfjmszxlyn',deliveries:[delivery,{...delivery,recipient:'ordinary@example.org'}]}));
 await assert.rejects(()=>dispatchCompetitionPublication({...args,projectRef:'egxdkaotepgfjmszxlyn',deliveries:[{...delivery,status:'sent'}]}));
 assert.equal(sends,0);
});
test('message is recorded before transport and uncertain deliveries are never retried by dispatch',async()=>{
 const steps=[];
 const result=await dispatchCompetitionPublication({projectRef:'egxdkaotepgfjmszxlyn',snapshot,deliveries:[delivery],saveMessage:async()=>steps.push('save'),send:async(to,message)=>{assert.equal(to,recipient);assert.match(message.html,/Opponent pair/);steps.push('send');throw Error('timeout');},finish:async(d,status)=>steps.push(status)});
 assert.deepEqual(steps,['save','send','uncertain']);assert.equal(result[0].status,'uncertain');
});
test('successful publication sends only to its frozen approved recipient',async()=>{
 const sends=[],states=[];
 const result=await dispatchCompetitionPublication({projectRef:'egxdkaotepgfjmszxlyn',snapshot,deliveries:[delivery],saveMessage:async()=>{},send:async(to,m)=>sends.push(to),finish:async(d,s)=>states.push(s)});
 assert.deepEqual(sends,[recipient]);assert.deepEqual(states,['sent']);assert.equal(result[0].status,'sent');
});
test('eliminated players are not asked to arrange an old match or given opponent contacts',()=>{
 const s={...snapshot,matches:[{...snapshot.matches[0],status:'completed',winner_entry_id:'b'}]};
 const m=prepareCompetitionPublicationMessage(s,delivery);assert.equal(m.content.entries[0].state,'eliminated');assert.equal(m.content.contacts.length,0);
 assert.match(m.html,/eliminated/);assert.doesNotMatch(m.html,/Please arrange this match/);
});

test('Production dispatch accepts a real frozen entrant while staging continues to reject them',async()=>{
 const email='player@example.org';
 const s={...snapshot,profiles:snapshot.profiles.map(p=>p.id==='me'?{...p,email_address:email}:p)};
 const sends=[];
 const args={snapshot:s,deliveries:[{...delivery,recipient:email}],saveMessage:async()=>{},send:async to=>sends.push(to),finish:async()=>{}};
 await assert.rejects(()=>dispatchCompetitionPublication({...args,projectRef:'egxdkaotepgfjmszxlyn'}));
 await dispatchCompetitionPublication({...args,projectRef:'xfjelvvfoguzukgvxchh'});
 assert.deepEqual(sends,[email]);
});
