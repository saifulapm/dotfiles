// The words of Chromium's new-tab page; dots theme copies this file into the page's extension, so it imports nothing.

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const pad2 = (n) => String(n).padStart(2, '0');

// Page titles are whatever a site's author wrote, so controls become spaces and bidi marks go.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const BIDI = /[‎‏؜‪-‮⁦-⁩]/g;
const clean = (s) => String(s || '').replace(CONTROL, ' ').replace(BIDI, '').replace(/\s+/g, ' ').trim();

export function dateLines(voice, d) {
  const day = DAYS[d.getDay()];
  if (voice === 'bracket') return { day: day.toUpperCase(), date: `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}` };
  return { day: voice === 'caps' ? day.toUpperCase() : day, date: `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}` };
}

// A host with a dotted name ending in letters, localhost or an IPv4 address opens; anything else, other schemes too, is searched for.
const WEB = /^https?:\/\/\S+$/i;
const NAMED = /^([a-z0-9-]+\.)+[a-z]{2,}(:\d+)?([/?#]\S*)?$/i;
const LOCAL = /^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?([/?#]\S*)?$/i;

export function readQuery(text) {
  const q = text.trim();
  if (!q) return null;
  if (WEB.test(q)) return { url: q };
  if (LOCAL.test(q)) return { url: `http://${q}` };
  if (NAMED.test(q)) return { url: `https://${q}` };
  return { search: q };
}

const address = (url) => clean(url.replace(/^https?:\/\/(www\.)?/i, '').replace(/\/$/, ''));
const firstMark = (s) => (s.match(/[\p{L}\p{N}]/u) || [''])[0];

export function siteRows(sites, voice) {
  return sites
    .filter((s) => /^https?:\/\//i.test(s.url))
    .slice(0, 6)
    .map((s, i) => {
      const where = address(s.url);
      const title = clean(s.title) || where;
      const tile = firstMark(title) || firstMark(where) || '•';
      return { n: String(i + 1), url: s.url, tile: voice === 'bracket' ? tile.toUpperCase() : tile, title, address: where };
    });
}

// The index of the row a digit opens, or -1: a digit typed into a query is part of it.
export function digitSite(key, field, count) {
  const n = /^[1-6]$/.test(key) ? Number(key) : 0;
  return !field && n > 0 && n <= count ? n - 1 : -1;
}

export function words(voice) {
  const keys = [['type', 'search'], ['↓ / tab', 'most visited'], ['1–6', 'open'], ['↵', 'go']];
  const base = { placeholder: 'Search the web or type a URL', head: 'MOST VISITED', empty: 'NOTHING VISITED YET' };
  if (voice === 'bracket') return Object.assign(base, { go: '[↵] GO', keys: keys.map(([k, w]) => [`[${k.toUpperCase()}]`, w.toUpperCase()]) });
  if (voice === 'plain') return Object.assign(base, { go: '↵ go', head: 'Most visited', empty: 'Nothing visited yet', keys });
  return Object.assign(base, { go: '↵ go', keys });
}
