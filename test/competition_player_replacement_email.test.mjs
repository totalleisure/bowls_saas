import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareCompetitionAmendmentMessage} from '../supabase/functions/_shared/competition_amendment_email.mjs';
const snapshot={amendment:true,matchId:'m',clubName:'Lewisham',playerReplacement:{entryId:'a',outgoingId:'old',incomingId:'new',oldName:'Wrong Member',newName:'Right Member',entryName:'Right Member / Partner'},
 competitions:[{id:'c',name:'Mixed Pairs',settings:{handicap_mode:'team_difference',players_per_entry:2,rules:'18 ends'}}],
 entries:[{id:'a',competition_id:'c',name:'Right Member / Partner'},{id:'b',competition_id:'c',name:'Opponent / Other'}],
 entryMembers:[{entry_id:'a',member_profile_id:'new',individual_handicap:2},{entry_id:'a',member_profile_id:'partner',individual_handicap:5},{entry_id:'b',member_profile_id:'op',individual_handicap:10},{entry_id:'b',member_profile_id:'other',individual_handicap:10}],
 matches:[{id:'m',competition_id:'c',round_id:'r',match_number:1,status:'to_be_arranged',side_a_entry_id:'a',side_b_entry_id:'b'}],
 rounds:[{id:'r',competition_id:'c',round_number:1,name:'Quarter-final',play_by:'2026-12-13'}],
 profiles:[{id:'old',first_name:'Wrong',last_name:'Member',email_address:'wayne@totalleisure.com'},{id:'new',first_name:'Right',last_name:'Member',email_address:'wayne.s.sayers@gmail.com',phone:'123'},{id:'partner',first_name:'Partner',email_address:'wayne.sayers@me.com'},{id:'op',first_name:'Opponent',email_address:'wayne.sayers@icloud.com'},{id:'other',first_name:'Other',email_address:'ordinary@example.org'}]};
test('Replacement notice reaches corrected pair and opponents with updated contacts and handicaps',()=>{
 for(const id of ['new','partner','op']) {
  const p=snapshot.profiles.find(p=>p.id===id);
  const mail=prepareCompetitionAmendmentMessage(snapshot,{recipient:p.email_address,member_profile_id:id});
  assert.match(mail.subject,/player corrected/);assert.ok(mail.html.includes('Wrong Member has been replaced by Right Member'));
  assert.ok(mail.html.includes('Starting score: 13'));assert.ok(mail.html.includes('Starting score: 0'));assert.ok(mail.html.includes('Right Member (Hcp 2)'));
  assert.ok(!mail.content.contacts.some(p=>p.name==='Wrong Member'));
 }
});
test('Removed player gets a removal notice without opponents contact details',()=>{
 const mail=prepareCompetitionAmendmentMessage(snapshot,{recipient:'wayne@totalleisure.com',member_profile_id:'old'});
 assert.ok(mail.html.includes('You are no longer listed'));assert.equal(mail.content.entries.length,0);assert.equal(mail.content.contacts.length,0);
 assert.ok(!mail.html.includes('wayne.sayers@icloud.com'));
});
test('An existing booking is described as arranged rather than asking players to book again',()=>{
 const s=structuredClone(snapshot);s.matches[0].fixture_id='booked';
 const mail=prepareCompetitionAmendmentMessage(s,{recipient:'wayne.s.sayers@gmail.com',member_profile_id:'new'});
 assert.equal(mail.content.entries[0].state,'arranged');
 assert.ok(mail.html.includes('Your fixture is already arranged'));
 assert.ok(!mail.html.includes('Please arrange this match in the App.'));
});
test('Replacement messages retain staging restrictions, production eligibility and frozen recipient checks',()=>{
 const delivery={recipient:'ordinary@example.org',member_profile_id:'other'};
 assert.throws(()=>prepareCompetitionAmendmentMessage(snapshot,delivery));
 assert.match(prepareCompetitionAmendmentMessage(snapshot,delivery,{projectRef:'xfjelvvfoguzukgvxchh'}).subject,/player corrected/);
 assert.throws(()=>prepareCompetitionAmendmentMessage(snapshot,{...delivery,recipient:'wayne@totalleisure.com'}));
});
