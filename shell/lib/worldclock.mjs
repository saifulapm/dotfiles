// The calendar card's city rows and the launcher's "17:00 nyc" conversion. Pure: zones is what bin/dots-zones prints ({home, zones: [{id, city, offset}]}, offsets in seconds east of UTC), nowMs the Clock service's time.
const DAY = 86400000;
const pad = (n) => String(n).padStart(2, '0');
const ALIAS = { nyc: 'America/New_York', london: 'Europe/London', utc: 'UTC' };

// Wall-clock milliseconds of a zone: read with the UTC getters.
const wall = (ms, z) => ms + z.offset * 1000;
const hhmm = (w) => `${pad(Math.floor(w / 3600000) % 24)}:${pad(Math.floor(w / 60000) % 60)}`;
const dayOf = (w) => Math.floor(w / DAY);
const word = (d) => (d > 0 ? 'tomorrow' : d < 0 ? 'yesterday' : '');

// "−6h", "+10h", "−5:30h"; the board writes a true minus.
function offsetText(secs) {
  if (secs === 0) return '0h';
  const m = Math.abs(secs) / 60;
  const mins = m % 60;
  return `${secs < 0 ? '−' : '+'}${Math.floor(m / 60)}${mins ? ':' + pad(mins) : ''}h`;
}

const homeOf = (zones) => zones.zones.find((z) => z.id === zones.home);

export function cityRows(nowMs, zones) {
  const home = homeOf(zones);
  const homeDay = dayOf(wall(nowMs, home));
  return zones.zones.map((z) => {
    const w = wall(nowMs, z);
    const isHome = z === home;
    return {
      city: z.city,
      time: hhmm(w),
      offset: isHome ? '' : offsetText(z.offset - home.offset),
      day: isHome ? '' : word(dayOf(w) - homeDay),
      home: isHome,
    };
  });
}

// "17:00 nyc" is 17:00 on the named city's own calendar day today. It uses the offsets in force now, which hold until the next change the shell reruns dots-zones for.
export function convert(text, nowMs, zones) {
  const m = /^\s*(\d{1,2}):(\d{2})\s+([a-z][a-z ]*?)\s*$/i.exec(text);
  if (!m) return null;
  const [h, min] = [Number(m[1]), Number(m[2])];
  if (h > 23 || min > 59) return null;
  const name = m[3].toLowerCase().replace(/\s+/g, ' ');
  const src = zones.zones.find((z) => z.id === ALIAS[name] || z.city.toLowerCase() === name);
  if (!src) return null;
  const home = homeOf(zones);
  const srcWall = dayOf(wall(nowMs, src)) * DAY + (h * 60 + min) * 60000;
  const homeWall = srcWall - src.offset * 1000 + home.offset * 1000;
  const from = `${pad(h)}:${pad(min)} ${src.city}`;
  const to = `${hhmm(homeWall)} ${home.city}`;
  const day = word(dayOf(homeWall) - dayOf(srcWall));
  const utc = [src, home].map((z) => (z.id === 'UTC' ? 'UTC' : `${z.city} UTC${offsetText(z.offset).slice(0, -1)}`)).join(' · ');
  return { from, to, day, text: `${from} = ${to}${day ? ' · ' + day : ''}`, time: hhmm(homeWall), utc };
}
