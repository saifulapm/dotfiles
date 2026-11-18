// A stand-in for iCloud's CalDAV, shaped as caldav.icloud.com answered on 2026-11-19: the principal on the front host, the calendar home on a partition host, and every element in the DAV: default namespace.
import { createServer } from 'node:http';

const xml = (responses) => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<multistatus xmlns="DAV:">\n${responses.join('\n')}\n</multistatus>\n`;
const response = (href, props) =>
  `    <response xmlns="DAV:">\n        <href>${href}</href>\n        <propstat>\n            <prop>\n                ${props}\n            </prop>\n            <status>HTTP/1.1 200 OK</status>\n        </propstat>\n    </response>`;
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const listen = (handler) =>
  new Promise((resolve) => {
    const s = createServer(handler);
    s.listen(0, '127.0.0.1', () => resolve(s));
  });

// names: the display names of the calendars in the home. Returns the front URL, the request log, and handles to change its answers.
export async function icloud(names = ['Home', 'Dots reminders']) {
  const home = '/1234567/calendars/';
  const calendars = names.map((name, i) => ({ name, path: `${home}CAL-${i}/`, events: new Map() }));
  const fake = { log: [], status: 0, delay: 0, calendars };
  let part;
  const handle = (host) => (req, res) => {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', async () => {
      fake.log.push({ host, method: req.method, path: req.url, auth: req.headers.authorization, depth: req.headers.depth });
      if (fake.delay) await new Promise((r) => setTimeout(r, fake.delay));
      const send = (code, text = '', type = 'application/xml; charset=UTF-8') => {
        res.writeHead(code, text ? { 'Content-Type': type } : {});
        res.end(text);
      };
      if (fake.status) return send(fake.status, fake.status === 401 ? 'Unauthorized' : '', 'text/plain');
      if (req.headers.authorization !== 'Basic ' + Buffer.from('me@x.test:app-pass-1').toString('base64')) return send(401, 'Unauthorized', 'text/plain');
      const cal = calendars.find((c) => req.url.startsWith(c.path) && req.url !== c.path);
      if (host === 'front' && req.method === 'PROPFIND' && req.url === '/')
        return send(207, xml([response('/', '<current-user-principal xmlns="DAV:"><href xmlns="DAV:">/1234567/principal/</href></current-user-principal>')]));
      if (host === 'front' && req.method === 'PROPFIND' && req.url === '/1234567/principal/')
        return send(207, xml([response('/1234567/principal/', `<calendar-home-set xmlns="urn:ietf:params:xml:ns:caldav"><href xmlns="DAV:">${part}${home}</href></calendar-home-set>`)]));
      if (host === 'part' && req.method === 'PROPFIND' && req.url === home)
        return send(
          207,
          xml(
            [response(home, '<displayname xmlns="DAV:">Me</displayname><resourcetype xmlns="DAV:"><collection/></resourcetype>')].concat(
              calendars.map((c) => response(c.path, `<displayname xmlns="DAV:">${esc(c.name)}</displayname><resourcetype xmlns="DAV:"><collection/><calendar xmlns="urn:ietf:params:xml:ns:caldav"/></resourcetype>`)),
              [response(home + 'inbox/', '<displayname xmlns="DAV:">\n      \n  </displayname><resourcetype xmlns="DAV:"><collection/></resourcetype>')],
            ),
          ),
        );
      if (host === 'part' && cal && req.method === 'PUT') {
        const had = cal.events.has(req.url);
        cal.events.set(req.url, body);
        return send(had ? 204 : 201);
      }
      if (host === 'part' && cal && req.method === 'DELETE') return send(cal.events.delete(req.url) ? 204 : 404);
      const whole = calendars.find((c) => req.url === c.path);
      if (host === 'part' && whole && req.method === 'REPORT')
        return send(207, xml([...whole.events].map(([href, ics]) => response(href, `<calendar-data xmlns="urn:ietf:params:xml:ns:caldav">${esc(ics)}</calendar-data>`))));
      send(405);
    });
  };
  const front = await listen(handle('front'));
  const partServer = await listen(handle('part'));
  part = `http://127.0.0.1:${partServer.address().port}`;
  fake.url = `http://127.0.0.1:${front.address().port}/`;
  fake.part = part;
  fake.count = (method) => fake.log.filter((r) => r.method === method).length;
  fake.close = () => Promise.all([front, partServer].map((s) => new Promise((r) => s.close(r))));
  return fake;
}

// The events a calendar-query REPORT on the named calendar returns, each {href, uid, summary, ics}.
export async function report(fake, name) {
  const cal = fake.calendars.find((c) => c.name === name);
  const auth = 'Basic ' + Buffer.from('me@x.test:app-pass-1').toString('base64');
  const r = await fetch(fake.part + cal.path, {
    method: 'REPORT',
    headers: { Authorization: auth, Depth: '1', 'Content-Type': 'application/xml; charset=utf-8' },
    body: '<?xml version="1.0"?><c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-data/></d:prop><c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"/></c:comp-filter></c:filter></c:calendar-query>',
  });
  const text = await r.text();
  const unxml = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  return [...text.matchAll(/<href>([^<]*)<\/href>[\s\S]*?<calendar-data[^>]*>([\s\S]*?)<\/calendar-data>/g)].map(([, href, data]) => {
    const ics = unxml(data);
    const unfolded = ics.replace(/\r\n[ \t]/g, '');
    const get = (k) => (new RegExp(`^${k}:(.*)$`, 'm').exec(unfolded) || [])[1]?.replace(/\r$/, '');
    return { href, uid: get('UID'), summary: get('SUMMARY'), trigger: get('TRIGGER'), ics };
  });
}
