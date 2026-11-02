import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareCompetitionDeadlineMessage} from '../supabase/functions/_shared/competition_deadline_email.mjs';
const delivery={recipient:'wayne@totalleisure.com',member_profile_id:'me'};
const snapshot={matchId:'m',oldDeadline:'2026-12-13',newDeadline:'2026-12-20',clubName:'Club',competitions:[{id:'c',name:'Pairs',settings:{rules:'No dead ends'}}],
 entries:[{id:'a',competition_id:'c',name:'My Pair'},{id:'b',competition_id:'c',name:'Other Pair'}],entryMembers:[{entry_id:'a',member_profile_id:'me'},{entry_id:'b',member_profile_id:'other'}],
 rounds:[{id:'r',competition_id:'c',round_number:2,name:'Last 16',play_by:'2026-12-20'}],matches:[{id:'m',competition_id:'c',round_id:'r',match_number:1,status:'to_be_arranged',side_a_entry_id:'a',side_b_entry_id:'b'}],profiles:[{id:'me',first_name:'Wayne',email_address:delivery.recipient},{id:'other',first_name:'Other',phone:'123'}]};
test('Deadline notice shows old and new ordinal dates and warns booking unchanged',()=>{
 const m=prepareCompetitionDeadlineMessage(snapshot,delivery);
 assert.equal(m.subject,'Pairs — Last 16 play-by date changed');
 for(const text of ['13th Dec 2026','20th Dec 2026','Last 16 1','No dead ends','does not change any fixture booking'])assert.ok(m.html.includes(text),text);
 assert.equal(m.content.entries[0].state,'ready');
});
test('Awaiting opponents still receive deadline changes; clearing dates is explicit',()=>{
 const m=prepareCompetitionDeadlineMessage({...snapshot,newDeadline:null,rounds:[{...snapshot.rounds[0],play_by:null}],matches:[{...snapshot.matches[0],side_b_entry_id:null}]},delivery);
 assert.equal(m.content.entries[0].state,'awaiting_opponent');assert.ok(m.html.includes('New play-by date: Not yet set'));assert.equal(m.content.contacts.length,0);
});
test('No notifications for unchanged, completed or mismatched snapshots',()=>{
 assert.throws(()=>prepareCompetitionDeadlineMessage({...snapshot,newDeadline:snapshot.oldDeadline},delivery));
 assert.throws(()=>prepareCompetitionDeadlineMessage({...snapshot,matches:[{...snapshot.matches[0],status:'completed'}]},delivery));
 assert.throws(()=>prepareCompetitionDeadlineMessage(snapshot,{...delivery,recipient:'other@example.org'}));
});
