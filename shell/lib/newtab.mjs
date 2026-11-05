// The words of Chromium's new-tab page; dots colorscheme copies this file into the page's extension, so it imports nothing.

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

// Page titles are whatever a site's author wrote, so controls become spaces and bidi marks go.
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/g;
const BIDI = /[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]/g;
const clean = (s) => String(s || '').replace(CONTROL, ' ').replace(BIDI, '').replace(/\s+/g, ' ').trim();

export const dateLines = (d) => ({ day: DAYS[d.getDay()], date: `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}` });

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

// The Web Store Chromium puts in the top sites of a profile with no history.
const PREPOPULATED = /^https:\/\/(chrome\.google\.com\/webstore|chromewebstore\.google\.com\/)/i;

export function siteRows(sites) {
  return sites
    .filter((s) => /^https?:\/\//i.test(s.url) && !PREPOPULATED.test(s.url))
    .slice(0, 6)
    .map((s, i) => {
      const where = address(s.url);
      const title = (s.title === s.url ? '' : clean(s.title)) || where;
      const tile = firstMark(title) || firstMark(where) || '•';
      return { n: String(i + 1), url: s.url, tile, title, address: where };
    });
}

// The index of the row a digit opens, or -1: a digit typed into a query is part of it.
export function digitSite(key, field, count) {
  const n = /^[1-6]$/.test(key) ? Number(key) : 0;
  return !field && n > 0 && n <= count ? n - 1 : -1;
}

export const WORDS = {
  placeholder: 'Search the web or type a URL',
  head: 'Most visited',
  empty: 'Nothing visited yet',
  go: '↵ go',
  keys: [['type', 'search'], ['↓ / tab', 'most visited'], ['1–6', 'open'], ['↵', 'go']],
};
