import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareCompetitionAmendmentMessage} from '../supabase/functions/_shared/competition_amendment_email.mjs';
const snapshot={amendment:true,matchId:'p7',challengerEntryId:'a',targetReference:'Quarter-final 4',clubName:'Lewisham',
 competitions:[{id:'c',name:'Ladies Pairs',settings:{rules:'No dead ends'}}],
 entries:[{id:'a',competition_id:'c',name:'Steph / Helen'},{id:'b',competition_id:'c',name:'Anne / Sandy'},{id:'c1',competition_id:'c',name:'Carol / Sue'}],
 entryMembers:[{entry_id:'a',member_profile_id:'a'},{entry_id:'b',member_profile_id:'b'},{entry_id:'c1',member_profile_id:'c1'}],
 profiles:[{id:'a',first_name:'Steph',email_address:'wayne@totalleisure.com'},{id:'b',first_name:'Anne',email_address:'wayne.sayers@me.com'},{id:'c1',first_name:'Carol',email_address:'wayne.sayers@icloud.com'}],
 rounds:[{id:'p',name:'Preliminary',round_number:1,play_by:'2026-12-13'},{id:'q',name:'Quarter-final',round_number:2,play_by:'2027-01-24'}],
 matches:[{id:'p7',competition_id:'c',round_id:'p',status:'to_be_arranged',side_a_entry_id:'a',side_b_entry_id:'b'},
 {id:'q4',competition_id:'c',round_id:'q',status:'to_be_arranged',side_a_source_id:'p7',side_a_entry_id:null,side_b_entry_id:'c1'}]};
test('Amendment reaches both preliminary entries and the waiting QF pair with the correct details',()=>{
 for(const profile of snapshot.profiles){
 const result=prepareCompetitionAmendmentMessage(snapshot,{member_profile_id:profile.id,recipient:profile.email_address});
 assert.match(result.subject,/draw amended/);assert.match(result.html,/challengers/);
 assert.match(result.html,/Quarter-final 4/);assert.equal(result.content.entries.length,1);
 assert.equal(result.content.entries[0].state,profile.id==='c1'?'awaiting_opponent':'ready');
 }
 assert.throws(()=>prepareCompetitionAmendmentMessage(snapshot,{member_profile_id:'a',recipient:'ordinary@example.org'}));
});
