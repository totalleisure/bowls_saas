import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareCompetitionRoundReadyMessage} from '../supabase/functions/_shared/competition_round_ready_email.mjs';
import {dispatchCompetitionPublication} from '../supabase/functions/_shared/competition_publication_dispatch.mjs';
const recipient='wayne@totalleisure.com';
const delivery={id:'d',recipient,member_profile_id:'me',status:'claimed'};
const snapshot={matchId:'m',clubName:'Lewisham',competitions:[{id:'c',name:'Mens Pairs',settings:{rules:'No dead ends',dress:'Whites',woods_per_player:2}}],
 entries:[{id:'a',competition_id:'c',name:'Wayne / Partner'},{id:'b',competition_id:'c',name:'Other pair'}],
 entryMembers:[{entry_id:'a',member_profile_id:'me'},{entry_id:'a',member_profile_id:'partner'},{entry_id:'b',member_profile_id:'op1'},{entry_id:'b',member_profile_id:'op2'}],
 rounds:[{id:'r',competition_id:'c',name:'Last 16',round_number:2,play_by:'2027-01-22',rule_overrides:{dress:'Greys'}}],
 matches:[{id:'m',competition_id:'c',round_id:'r',match_number:1,status:'to_be_arranged',side_a_entry_id:'a',side_b_entry_id:'b'}],
 profiles:[{id:'me',first_name:'Wayne',email_address:recipient,phone:'111'},{id:'partner',first_name:'Partner',phone:'222'},{id:'op1',first_name:'Opponent One',email_address:'opponent@example.org',phone:'333'},{id:'op2',first_name:'Opponent Two',phone:'444'}]};
test('Next-round email is match-specific with both pairs, contacts, deadline and effective rules',()=>{
 const m=prepareCompetitionRoundReadyMessage(snapshot,delivery);
 assert.equal(m.subject,'Mens Pairs — Last 16 1 ready to arrange');
 assert.equal(m.content.entries.length,1);assert.equal(m.content.entries[0].stageName,'Last 16 1');
 assert.equal(m.content.teamContacts.length,2);assert.equal(m.content.contacts.length,2);
 for(const text of ['22nd Jan 2027','Your team contact details','Opponent contact details','222','333','444','Dress: Greys','Woods per player: 2','Both entries are confirmed'])assert.ok(m.html.includes(text),text);
 assert.ok(!m.html.includes('draw published'));assert.ok(!m.html.includes('Dress: Whites'));
});
test('Reject unfinished, wrong match and mismatched recipient snapshots',()=>{
 for(const status of ['bye','result_pending','completed'])assert.throws(()=>prepareCompetitionRoundReadyMessage({...snapshot,matches:[{...snapshot.matches[0],status}]},delivery));
 assert.throws(()=>prepareCompetitionRoundReadyMessage({...snapshot,matches:[{...snapshot.matches[0],side_b_entry_id:null}]},delivery));
 assert.throws(()=>prepareCompetitionRoundReadyMessage({...snapshot,matchId:'other'},delivery));
 assert.throws(()=>prepareCompetitionRoundReadyMessage(snapshot,{...delivery,recipient:'wayne.sayers@me.com'}));
 assert.throws(()=>prepareCompetitionRoundReadyMessage(snapshot,{...delivery,recipient:'ordinary@example.org'}));
});
test('Ready dispatcher sends only approved frozen recipient once claimed; ambiguous sends become uncertain',async()=>{
 const steps=[];
 const args={projectRef:'egxdkaotepgfjmszxlyn',snapshot,deliveries:[delivery],prepareMessage:prepareCompetitionRoundReadyMessage,
 saveMessage:async()=>steps.push('saved'),send:async(to,m)=>{assert.equal(to,recipient);assert.match(m.subject,/Last 16 1/);steps.push('sent');},finish:async(d,status)=>steps.push(status)};
 await dispatchCompetitionPublication(args);assert.deepEqual(steps,['saved','sent','sent']);
 await assert.rejects(()=>dispatchCompetitionPublication({...args,projectRef:'unknown-project'}));
 await assert.rejects(()=>dispatchCompetitionPublication({...args,deliveries:[{...delivery,status:'sent'}]}));
 const failed=await dispatchCompetitionPublication({...args,send:async()=>{throw Error('Timeout');}});assert.equal(failed[0].status,'uncertain');
});
