// A pending reminder as the iCalendar event the iPhone rings: its id as UID, its one-line text as title, 5 minutes from its due with an alert at the start (RFC 5545).
const MIN = 60000;

// 20261119T044000Z; an instant in UTC, so a due set across a DST change keeps the local time it was set for.
const utc = (ms) => new Date(ms).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

// TEXT values escape a backslash, a semicolon, a comma and a newline (3.3.11).
const text = (s) => s.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');

// A line longer than 75 octets continues on lines that start with a space (3.1); a character is never split, so each part is valid UTF-8.
function fold(line) {
  const out = [];
  let cur = '';
  let size = 0;
  for (const ch of line) {
    const n = Buffer.byteLength(ch);
    if (size + n > 75) {
      out.push(cur);
      cur = ' ';
      size = 1;
    }
    cur += ch;
    size += n;
  }
  return out.concat([cur]).join('\r\n');
}

// A pulled record is anyone's: an id that is not a plain token could add lines to the event or break its path, and a due or created time past year 9999 has no DATE-TIME, so neither goes up.
const holds = (ms) => ms >= 0 && ms < Date.UTC(10000, 0, 1);
export const carriable = (r) => /^[A-Za-z0-9._-]{1,128}$/.test(r.id) && holds(r.due) && holds(r.due + 5 * MIN) && holds(r.created);

// r is a pendingList entry, {id, text, due, created}; the same reminder always gives the same bytes, as DTSTAMP comes from its created time.
export function eventIcs(r) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//dots//reminders//EN',
    'BEGIN:VEVENT',
    `UID:${r.id}`,
    `DTSTAMP:${utc(r.created)}`,
    `DTSTART:${utc(r.due)}`,
    `DTEND:${utc(r.due + 5 * MIN)}`,
    `SUMMARY:${text(r.text)}`,
    'BEGIN:VALARM',
    'ACTION:DISPLAY',
    `DESCRIPTION:${text(r.text)}`,
    'TRIGGER:PT0S',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ]
    .map(fold)
    .join('\r\n') + '\r\n';
}
