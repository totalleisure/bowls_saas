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
test('Handicap emails show each player, combined totals and recipient-oriented starting scores',()=>{
 const s=structuredClone(snapshot);
 Object.assign(s.competitions[0].settings,{handicap_mode:'team_difference',players_per_entry:2});
 s.entryMembers.forEach((p,i)=>p.individual_handicap=[12,12,5,5][i]);
 let m=prepareCompetitionRoundReadyMessage(s,delivery);
 for(const text of ['Wayne (Hcp 12)','Partner (Hcp 12)','Opponent One (Hcp 5)','Opponent Two (Hcp 5)','Combined handicap: 24','Combined handicap: 10','Starting score: 0','Starting score: 14'])assert.ok(m.html.includes(text),text);
 assert.match(m.content.entries[0].handicapSummary,/Your team\nWayne.*\nPartner.*\nCombined handicap: 24\nStarting score: 0/);
 s.profiles.find(p=>p.id==='op1').email_address='ordinary@example.org';
 m=prepareCompetitionRoundReadyMessage(s,{...delivery,member_profile_id:'op1',recipient:'ordinary@example.org'},{projectRef:'xfjelvvfoguzukgvxchh'});
 assert.match(m.content.entries[0].handicapSummary,/Your team\nOpponent One.*\nOpponent Two.*\nCombined handicap: 10\nStarting score: 14/);
 assert.throws(()=>prepareCompetitionRoundReadyMessage(s,{...delivery,member_profile_id:'op1',recipient:'ordinary@example.org'}));
});
test('Equal, signed and missing handicaps are distinguished; text is escaped',()=>{
 const s=structuredClone(snapshot);
 Object.assign(s.competitions[0].settings,{handicap_mode:'team_difference',players_per_entry:2});
 s.entryMembers.forEach((p,i)=>p.individual_handicap=[-2,2,0,0][i]);
 let m=prepareCompetitionRoundReadyMessage(s,delivery);
 assert.ok(m.html.includes('Wayne (Hcp -2)'));
 assert.equal((m.content.entries[0].handicapSummary.match(/Starting score: 0/g)||[]).length,2);
 s.entryMembers[0].individual_handicap=null;
 s.profiles[1].first_name='<script>alert(1)</script>';
 m=prepareCompetitionRoundReadyMessage(s,delivery);
 assert.ok(m.html.includes('Wayne (Hcp not recorded)'));
 assert.ok(m.html.includes('Starting score: awaiting complete handicaps'));
 assert.ok(!m.html.includes('<script>'));
 assert.ok(m.html.includes('&lt;script&gt;'));
});
test('Next-round email is match-specific with both pairs, contacts, deadline and effective rules',()=>{
 const m=prepareCompetitionRoundReadyMessage(snapshot,delivery);
 assert.equal(m.subject,'Mens Pairs — Last 16 1 ready to arrange');
 assert.equal(m.content.entries.length,1);assert.equal(m.content.entries[0].stageName,'Last 16 1');
 assert.equal(m.content.teamContacts.length,2);assert.equal(m.content.contacts.length,2);
 for(const text of ['22nd Jan 2027','Your team contact details','Opponent contact details','222','333','444','Dress: Greys','Woods per player: 2','Both entries are confirmed'])assert.ok(m.html.includes(text),text);
 assert.ok(!m.html.includes('draw published'));assert.ok(!m.html.includes('Dress: Whites'));
 assert.ok(!m.html.includes('Handicaps and starting scores'));
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
