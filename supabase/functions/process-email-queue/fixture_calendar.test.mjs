import {test} from 'node:test';
import assert from 'node:assert/strict';
const scheduling = {rootId:'12345678-1234-1234-1234-123456789abc',revision:1,organizer:'club@example.test',recipient:'member@example.test'};
import {buildFixtureCalendar, loadFixtureCalendar, calendarHtml, fixtureCalendarHtml} from './fixture_calendar.mjs';
const fixture = {id:'12345678-1234-1234-1234-123456789abc',
  start_at:'2026-07-12T13:00:00+01:00',end_at:'2026-07-12T15:30:00+01:00',is_home:true,
  club:{name:'Example Club'},competition_type:{name:'100 Up'},opponent_name:'A, B; C\\D\nNew',
  venue:{name:'Home',town_city:'London',postcode:'SE1'},opponent_venue:{name:'Away'}};
const decode = a => Buffer.from(a.contentBytes, 'base64').toString('utf8');
test('Request, replacement and cancellation share identity and increase revision',()=>{
  const original=decode(buildFixtureCalendar(fixture,'test',new Date(),scheduling));
  const changed=decode(buildFixtureCalendar({...fixture,id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},'test',new Date(),{...scheduling,revision:2}));
  const cancelled=decode(buildFixtureCalendar({...fixture,cancelled_at:'2026-01-01'},'test',new Date(),{...scheduling,revision:3,cancelled:true}));
  for(const content of [original,changed,cancelled]) {
    assert.match(content,new RegExp(`UID:${fixture.id}@test.bowls-app`));
    assert.match(content,/ORGANIZER:mailto:club@example.test/);
    assert.match(content,/ATTENDEE;RSVP=FALSE:mailto:member@example.test/);
    assert.equal((content.match(/BEGIN:VEVENT/g)||[]).length,1);
  }
  assert.match(original,/METHOD:REQUEST/);assert.match(original,/SEQUENCE:1/);
  assert.match(changed,/SEQUENCE:2/);assert.match(cancelled,/SEQUENCE:3/);
  assert.match(cancelled,/METHOD:CANCEL/);assert.match(cancelled,/STATUS:CANCELLED/);
  assert.throws(()=>buildFixtureCalendar(fixture,'test',new Date(),{...scheduling,organizer:'bad\r\nINJECTED:x'}));
});
test('Only actionable or lifecycle mail loads state; deleted and stale cancellations work',async()=>{
  let calls=0;let fail=false;
  const state={fixture,root_id:fixture.id,revision:1};
  const client={async rpc(name){assert.equal(name,'fixture_calendar_email_state');calls++;return fail?{error:{}}:{data:state}}};
  const email={id:'email',recipient_email:'member@example.test',fixture_id:fixture.id,payload:{action_block:{actions:[{command:'ACCEPT'},{command:'DECLINE'}]}}};
  assert(await loadFixtureCalendar(client,email,'test',scheduling.organizer));
  assert.equal(await loadFixtureCalendar(client,{...email,payload:{}},'test',scheduling.organizer),null);
  assert.equal(calls,1);
  state.fixture={...fixture,cancelled_at:'2026-01-01'};state.revision=2;
  const cancellation={...email,fixture_id:null,event_type:'fixture_calendar_cancelled'};
  const attachment=await loadFixtureCalendar(client,cancellation,'test',scheduling.organizer);
  assert.match(decode(attachment),/METHOD:CANCEL/);assert.match(fixtureCalendarHtml(attachment),/nothing to remove/);
  state.stale=true;
  assert.deepEqual(await loadFixtureCalendar(client,cancellation,'test',scheduling.organizer),{skip:true});
  state.stale=false;state.fixture=fixture;state.has_prior_calendar=true;
  assert.equal(await loadFixtureCalendar(client,{...email,event_type:'fixture_rescheduled_selected'},'test',scheduling.organizer),null);
  state.has_prior_calendar=false;
  assert(await loadFixtureCalendar(client,{...email,event_type:'fixture_rescheduled_selected'},'test',scheduling.organizer));
  fail=true;await assert.rejects(loadFixtureCalendar(client,email,'test',scheduling.organizer));
  assert.match(calendarHtml,/After accepting/);assert.match(fixtureCalendarHtml({calendarKind:'updated'}),/never added/);
});
test('Calendar contains actual UTC interval, safe text, venue and stable environment-specific identity',()=>{
  const a=buildFixtureCalendar(fixture,'staging',new Date('2026-01-01Z'));
  const content=decode(a);
  assert.equal(a.contentType,'text/calendar');
  assert.match(content,/DTSTART:20260712T120000Z\r\nDTEND:20260712T143000Z/);
  assert.match(content,/LOCATION:Home\\, London\\, SE1/);
  assert.match(content,/A\\, B\\; C\\\\D\\nNew/);
  assert.match(content,/UID:12345678-1234-1234-1234-123456789abc@staging.bowls-app/);
  assert(!content.includes('METHOD:REQUEST'));assert(!content.includes('ATTENDEE:'));
  assert.notEqual(decode(buildFixtureCalendar(fixture,'production')),content);
});
test('Away venue, winter dates, cancellation and invalid dates are handled',()=>{
  assert.match(decode(buildFixtureCalendar({...fixture,is_home:false},'test')),/LOCATION:Away/);
  assert.match(decode(buildFixtureCalendar({...fixture,start_at:'2026-11-12T13:00:00Z',end_at:'2026-11-12T15:30:00Z'},'test')),/DTSTART:20261112T130000Z/);
  assert.equal(buildFixtureCalendar({...fixture,cancelled_at:'2026-01-01'},'test'),null);
  for(const changed of [{start_at:null},{start_at:'bad'},{end_at:fixture.start_at}])
    assert.throws(()=>buildFixtureCalendar({...fixture,...changed},'test'));
});
test('UTF-8 lines are folded at 75 octets and round-trip without corruption',()=>{
  const name='é🎳'.repeat(90);
  const content=decode(buildFixtureCalendar({...fixture,club:{name}},'test'));
  assert(content.split('\r\n').every(line=>Buffer.byteLength(line)<=75));
  assert(content.replace(/\r\n /g,'').includes(name));
});
