const text = (value) => String(value ?? '').replace(/\\/g, '\\\\')
  .replace(/\r\n|\r|\n/g, '\\n').replace(/;/g, '\\;').replace(/,/g, '\\,');

// RFC 5545 limits content lines to 75 octets; never split a UTF-8 character.
function fold(line) {
  const lines = []; let current = ''; let size = 0;
  for (const character of line) {
    const length = new TextEncoder().encode(character).length;
    if (size + length > 75) { lines.push(current); current = ' '; size = 1; }
    current += character; size += length;
  }
  lines.push(current); return lines.join('\r\n');
}

const utc = (date) => date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');

export function buildFixtureCalendar(fixture, projectId, now = new Date(), scheduling = null) {
  if (fixture.cancelled_at && !scheduling?.cancelled) return null;
  const identity = scheduling?.rootId ?? fixture.id;
  if (!/^[a-z0-9-]+$/i.test(projectId) || !/^[0-9a-f-]{36}$/i.test(fixture.id)) {
    throw new Error('Invalid calendar event identity');
  }
  const start = new Date(fixture.start_at); const end = new Date(fixture.end_at);
  if (!fixture.start_at || !fixture.end_at || !Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end <= start) {
    throw new Error('Fixture calendar dates are invalid');
  }
  const club = fixture.club?.name || 'Bowls';
  const summary = [club, fixture.competition_type?.name || fixture.fixture_type || 'Fixture',
    fixture.opponent_name ? `v ${fixture.opponent_name}` : ''].filter(Boolean).join(' - ');
  const venue = fixture.is_home ? fixture.venue : fixture.opponent_venue;
  const location = venue ? [venue.name, venue.address_line1, venue.address_line2,
    venue.town_city, venue.postcode].filter(Boolean).join(', ') : '';
  const method = scheduling?.cancelled ? 'CANCEL' : 'REQUEST';
  if (scheduling && (!/^[0-9a-f-]{36}$/i.test(identity) ||
      !Number.isInteger(scheduling.revision) || scheduling.revision < 0 ||
      !/^[^\s<>:,;"\\]+@[^\s<>:,;"\\]+$/.test(scheduling.organizer) ||
      !/^[^\s<>:,;"\\]+@[^\s<>:,;"\\]+$/.test(scheduling.recipient))) {
    throw new Error('Invalid calendar scheduling identity');
  }
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Bowls App//Fixture Calendar//EN',
    'CALSCALE:GREGORIAN', ...(scheduling ? [`METHOD:${method}`] : []),
    'BEGIN:VEVENT', `UID:${identity}@${projectId}.bowls-app`,
    ...(scheduling ? [`SEQUENCE:${scheduling.revision}`,
      `ORGANIZER:mailto:${scheduling.organizer}`,
      `ATTENDEE;RSVP=FALSE:mailto:${scheduling.recipient}`,
      `STATUS:${scheduling.cancelled ? 'CANCELLED' : 'CONFIRMED'}`] : []),
    `DTSTAMP:${utc(now)}`, `DTSTART:${utc(start)}`, `DTEND:${utc(end)}`,
    `SUMMARY:${text(summary)}`, `LOCATION:${text(location)}`,
    `DESCRIPTION:${text(scheduling?.cancelled ? 'This fixture has been cancelled. Remove the saved event if your calendar does not process the cancellation automatically.' : 'Add this event only after accepting the fixture. Adding it to your calendar does not send your acceptance. Check the Bowls App for the latest fixture details.')}`,
    'END:VEVENT', 'END:VCALENDAR'];
  const bytes = new TextEncoder().encode(lines.map(fold).join('\r\n') + '\r\n');
  return { name: scheduling?.cancelled ? 'bowls-fixture-cancelled.ics' : 'bowls-fixture.ics',
    contentType: scheduling ? `text/calendar; charset=utf-8; method=${method}` : 'text/calendar',
    contentBytes: btoa(Array.from(bytes, b => String.fromCharCode(b)).join('')) };
}

export async function loadFixtureCalendar(client, email, projectId, organizer) {
  const actions = email.payload?.action_block?.actions ?? [];
  const lifecycle = ['fixture_calendar_updated', 'fixture_calendar_cancelled'].includes(email.event_type);
  if (!lifecycle && (!email.fixture_id || !actions.some(a => a.command === 'ACCEPT') ||
      !actions.some(a => a.command === 'DECLINE'))) return null;
  const {data, error} = await client.rpc('fixture_calendar_email_state', {p_email_queue_id: email.id});
  if (error || !data?.fixture) throw new Error('Fixture calendar details unavailable');
  if (lifecycle && data.stale) return {skip: true};
  // Existing recipients receive one dedicated update, rather than another ICS
  // in their separate rescheduling/acceptance message.
  if (email.event_type === 'fixture_rescheduled_selected' && data.has_prior_calendar) return null;
  const cancelled = lifecycle && !!data.fixture.cancelled_at;
  const attachment = buildFixtureCalendar(data.fixture, projectId, new Date(), {
    rootId: data.root_id, revision: data.revision, organizer,
    recipient: email.recipient_email, cancelled,
  });
  return attachment ? {...attachment, calendarKind: cancelled ? 'cancelled' : lifecycle ? 'updated' : 'initial'} : null;
}

export function fixtureCalendarHtml(attachment) {
  if (attachment.calendarKind === 'initial') return calendarHtml;
  if (attachment.calendarKind === 'cancelled') return '<p><strong>Calendar cancellation</strong><br>' +
    'Open <strong>bowls-fixture-cancelled.ics</strong> and confirm the cancellation if your calendar asks. ' +
    'If you never added this fixture, there is nothing to remove. If the old event remains, delete it manually.</p>';
  return '<p><strong>Update your calendar</strong><br>Open <strong>bowls-fixture.ics</strong> and apply the update to the calendar where you saved the original event. ' +
    'If you never added it, you can add the new event now. Your calendar may ask for confirmation. ' +
    'Older imported events may need manual replacement. Calendar responses do not confirm your fixture acceptance in the Bowls App.</p>';
}

export const calendarHtml = '<div style="margin-top:20px;padding:14px;border:1px solid #cccccc;border-radius:6px">' +
  '<strong>Add to Calendar</strong><br>After accepting the fixture:' +
  '<ol><li>Tap the attached <strong>bowls-fixture.ics</strong> file itself to open the event preview. On iPhone, use the file name or calendar icon rather than the download menu.</li>' +
  '<li>Tap <strong>Add To Calendar</strong> (or Add / Save in your calendar app).</li>' +
  '<li>If asked, choose the calendar you want and confirm once.</li></ol>' +
  '<br>Adding the calendar event does not accept the fixture. Please send your Accept response separately.</div>';
