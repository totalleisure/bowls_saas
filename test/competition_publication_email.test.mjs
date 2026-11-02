import test from 'node:test';
import assert from 'node:assert/strict';
import {competitionPublicationHtml,requireCompetitionTestRecipients,COMPETITION_TEST_RECIPIENTS,assembleCompetitionEmail,competitionEmailDate} from '../supabase/functions/_shared/competition_publication_email.mjs';
test('only the seven confirmed addresses can pass staging test policy',()=>{
 assert.equal(requireCompetitionTestRecipients('egxdkaotepgfjmszxlyn',COMPETITION_TEST_RECIPIENTS).length,7);
 assert.throws(()=>requireCompetitionTestRecipients('egxdkaotepgfjmszxlyn',['member@example.org']));
 assert.throws(()=>requireCompetitionTestRecipients('xfjelvvfoguzukgvxchh',COMPETITION_TEST_RECIPIENTS));
 assert.throws(()=>requireCompetitionTestRecipients('egxdkaotepgfjmszxlyn',[COMPETITION_TEST_RECIPIENTS[0],'member@example.org']));
});
test('boxed draw details include stage, rules, dates and contacts below the entries; user text is escaped',()=>{
 const html=competitionPublicationHtml({clubName:'Test Club',recipientName:'Test <Player>',entries:[{competitionName:'Pairs',stageName:'Quarter-final',playBy:'28 Feb 2027',entryName:'A / B',opponentName:'C / D',rules:'18 ends\nNo dead ends'}],contacts:[{name:'C',email:'test@example.org',mobile:'01234 567890'},{name:'D'}]});
 assert.ok(html.includes('Test &lt;Player&gt;'));for(const value of ['Quarter-final','28 Feb 2027','18 ends','No dead ends','test@example.org','01234 567890'])assert.ok(html.includes(value));
 assert.ok(html.indexOf('Opponent contact details')>html.indexOf('Competition rules'));
 assert.ok(html.includes('Competitions Manager'));
});

test('player preview selects own entries, skips byes, and includes only actual opponents contacts',()=>{
 const payload=assembleCompetitionEmail({clubName:'Club',profile:{id:'me',first_name:'Wayne',last_name:'Sayers'},competitions:[{id:'c',name:'Pairs',settings:{scoring:'18 ends',woods_per_player:2}}],entries:[{id:'my',competition_id:'c',name:'My pair'},{id:'op',competition_id:'c',name:'Opponent pair'},{id:'unrelated',competition_id:'c',name:'Others'}],entryMembers:[{entry_id:'my',member_profile_id:'me'},{entry_id:'op',member_profile_id:'other'},{entry_id:'unrelated',member_profile_id:'stranger'}],rounds:[{id:'p',round_number:1,name:'Preliminary'},{id:'r',round_number:2,name:'Last 16',play_by:'2027-01-22',rule_overrides:{rules:'Timed'}}],matches:[{competition_id:'c',round_id:'p',side_a_entry_id:'my',status:'bye'},{competition_id:'c',round_id:'r',side_a_entry_id:'my',side_b_entry_id:'op',status:'to_be_arranged'}],profiles:[{id:'other',first_name:'Opponent',email_address:'other@example.org',phone:'01234'},{id:'stranger',first_name:'Stranger',email_address:'private@example.org'}]});
 assert.equal(payload.entries.length,1);assert.equal(payload.entries[0].stageName,'Last 16');assert.equal(payload.entries[0].opponentName,'Opponent pair');assert.equal(payload.entries[0].playBy,'2027-01-22');assert.equal(payload.contacts.length,1);assert.equal(payload.contacts[0].email,'other@example.org');assert.ok(!JSON.stringify(payload).includes('private@example.org'));
});

test('email dates have ordinal day, short month and full year; unset dates are explicit',()=>{
 assert.equal(competitionEmailDate('2026-11-29'),'29th Nov 2026');
 for(const [day,suffix]of[[1,'st'],[2,'nd'],[3,'rd'],[11,'th'],[12,'th'],[13,'th'],[21,'st'],[22,'nd'],[23,'rd'],[31,'st']])assert.equal(competitionEmailDate(`2027-01-${String(day).padStart(2,'0')}`),`${day}${suffix} Jan 2027`);
 assert.equal(competitionEmailDate(null),'Not yet set');assert.equal(competitionEmailDate('2027-02-31'),'Not yet set');
 const html=competitionPublicationHtml({clubName:'Club',recipientName:'Player',entries:[{competitionName:'Singles',playBy:'2026-11-29'}]});assert.ok(html.includes('Play by: 29th Nov 2026'));
});

test('pairs include recipient and partner contacts separately from opponents, excluding unrelated players',()=>{
 const input={clubName:'Club',profile:{id:'me',first_name:'Wayne'},competitions:[{id:'c',name:'Pairs',settings:{}}],
 entries:[{id:'a',competition_id:'c',name:'Wayne / Partner'},{id:'b',competition_id:'c',name:'Other pair'},{id:'x',competition_id:'c',name:'Unrelated'}],
 entryMembers:[{entry_id:'a',member_profile_id:'me'},{entry_id:'a',member_profile_id:'partner'},{entry_id:'a',member_profile_id:'partner'},{entry_id:'b',member_profile_id:'op1'},{entry_id:'b',member_profile_id:'op2'},{entry_id:'x',member_profile_id:'stranger'}],
 rounds:[{id:'r',round_number:1,name:'Final'}],matches:[{competition_id:'c',round_id:'r',status:'to_be_arranged',side_a_entry_id:'a',side_b_entry_id:'b'}],
 profiles:[{id:'me',first_name:'Wayne',email_address:'wayne@example.org',phone:'111'},{id:'partner',first_name:'Partner',email_address:'partner@example.org',phone:'222'},{id:'op1',first_name:'Opponent One',email_address:'op1@example.org',phone:'333'},{id:'op2',first_name:'Opponent Two',phone:'444'},{id:'stranger',first_name:'Stranger',email_address:'private@example.org'}]};
 const content=assembleCompetitionEmail(input);
 assert.deepEqual(content.teamContacts.map(p=>p.name),['Wayne','Partner']);assert.equal(content.contacts.length,2);
 const html=competitionPublicationHtml(content);for(const text of ['Your team contact details','Opponent contact details','partner@example.org','222','op1@example.org','444'])assert.ok(html.includes(text));
 assert.ok(html.indexOf('Your team contact details')<html.indexOf('Opponent contact details'));assert.ok(!html.includes('private@example.org'));
 const waiting=assembleCompetitionEmail({...input,matches:[{...input.matches[0],side_b_entry_id:null}]});
 assert.equal(waiting.teamContacts.length,2);assert.equal(waiting.contacts.length,0);
});
