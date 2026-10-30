// Pure pieces of the notification history, kept here so node can test them.

export const LIMIT = 200;

// How long an entry holds the island in ms, 0 until dismissed: its app's rule, then its expireTimeout, where -1 asks for the default, 5 s or until dismissed for a critical.
export const holdMs = (entry, rule) => (rule?.stays >= 0 ? rule.stays : entry.timeout >= 0 ? entry.timeout : entry.critical ? 0 : 5000);

// The undismissed criticals waiting to take the island back, newest first: the one leaving joins them when it stays until dismissed, and the one arriving leaves them.
export function setAside(waiting, leaving, arriving, rules = {}) {
  const kept = waiting.filter((e) => e.key !== arriving);
  if (leaving && leaving.key !== arriving && leaving.critical && holdMs(leaving, ruleOf(rules, leaving.app)) === 0) kept.push(leaving);
  return kept.sort((a, b) => b.time - a.time);
}

// A hold paused under the pointer or Mod+I gets back what it had left, but never less than 1.5 s to read it once let go; one paused as its Tick was due has 0 or less left. 0 is until dismissed.
export const resumeMs = (entry, left, rule) => (holdMs(entry, rule) > 0 ? Math.max(left, 1500) : 0);

// Whether an entry takes the island, given its app's rule: a muted app's never do, criticals included; under Do Not Disturb only criticals and apps let through do.
export const shows = (entry, rule, dnd) => !rule?.muted && (!dnd || entry.critical || rule?.dnd === true);

// Rules key on the exact app name, which a sender may make __proto__ or constructor, so a name is only ever an own key.
export const ruleOf = (rules, app) => (Object.prototype.hasOwnProperty.call(rules, app) ? rules[app] : undefined);

const put = (o, key, value) => Object.defineProperty(o, key, { value, enumerable: true, writable: true, configurable: true });

// A rule left with nothing on is dropped.
function withRule(rules, app, rule) {
  const kept = {};
  for (const a of Object.keys(rules)) if (a !== app) put(kept, a, rules[a]);
  if (Object.keys(rule).length > 0) put(kept, app, rule);
  return kept;
}

export function toggle(rules, app, field) {
  const rule = Object.assign({}, ruleOf(rules, app));
  if (rule[field]) delete rule[field];
  else rule[field] = true;
  return withRule(rules, app, rule);
}

// How long an app stays, in the order s cycles it; 0 is until dismissed, and past the last the app's own time comes back.
const STAYS = [3000, 10000, 0];

export function cycleStay(rules, app) {
  const rule = Object.assign({}, ruleOf(rules, app));
  const next = STAYS[STAYS.indexOf(rule.stays) + 1];
  if (next === undefined) delete rule.stays;
  else rule.stays = next;
  return withRule(rules, app, rule);
}

const stayText = (ms) => (ms === 0 ? 'until dismissed' : ms / 1000 + ' s');

export const ruleText = (rule) => (rule?.muted ? ' · muted' : '') + (rule?.dnd ? ' · through DND' : '') + (rule?.stays >= 0 ? ' · stays ' + stayText(rule.stays) : '');

// The actions drawn as chips under a notification, keyed 1 to 3: default is Enter and a click on the card, and Chromium's per-site settings action is dropped.
export const chipsOf = (actions) =>
  (actions || [])
    .filter((a) => a.identifier !== 'default' && a.identifier !== 'settings')
    .slice(0, 3)
    .map((a, i) => ({ key: String(i + 1), identifier: a.identifier, text: a.text }));

// The window an action raises: the app's most recently focused one, whose app id is the desktop entry or the app name, ignoring case; null when it has none.
export function raiseTarget(windows, entry) {
  const names = [entry.desktopEntry, entry.app].filter((n) => n).map((n) => n.toLowerCase().replace(/\.desktop$/, ''));
  const at = (w) => (w.focus_timestamp ? w.focus_timestamp.secs * 1e9 + w.focus_timestamp.nanos : -1);
  const mine = windows.filter((w) => names.includes((w.app_id || '').toLowerCase()));
  return mine.length ? mine.reduce((a, b) => (at(b) > at(a) ? b : a)).id : null;
}

export const addEntry =(history, entry) => [entry].concat(history).slice(0, LIMIT);

const isEntry = (e) =>
  e !== null && typeof e === 'object' && typeof e.key === 'string' && typeof e.app === 'string' && typeof e.summary === 'string' && typeof e.body === 'string' && typeof e.time === 'number';

// The store is written by the shell alone, but a hand edit or a cut-off write must not stop it loading.
export function parseStore(text) {
  let data = null;
  try {
    data = JSON.parse(text);
  } catch (e) {
    data = null;
  }
  if (data === null || typeof data !== 'object' || !Array.isArray(data.history)) return { dnd: false, rules: {}, history: [] };
  const seen = {};
  const unique = data.history
    .filter(isEntry)
    .filter((e) => (seen[e.key] ? false : (seen[e.key] = true)))
    .map((e) => {
      if (!('files' in e) || validFiles(e.files)) return e;
      const kept = Object.assign({}, e);
      delete kept.files;
      return kept;
    });
  return { dnd: data.dnd === true, rules: validRules(data.rules), history: unique.slice(0, LIMIT) };
}

// A store from before per-app rules has none; a rule keeps only what m, i and s can set.
function validRules(rules) {
  let kept = {};
  if (rules === null || typeof rules !== 'object' || Array.isArray(rules)) return kept;
  for (const app of Object.keys(rules)) {
    const r = rules[app] !== null && typeof rules[app] === 'object' ? rules[app] : {};
    const rule = {};
    if (r.muted === true) rule.muted = true;
    if (r.dnd === true) rule.dnd = true;
    if (STAYS.includes(r.stays)) rule.stays = r.stays;
    kept = withRule(kept, app, rule);
  }
  return kept;
}

export const storeText = (store) => JSON.stringify({ dnd: store.dnd, rules: store.rules, history: store.history });

// The entries a search shows: its text in the app, summary or body, ignoring case.
export function visible(history, query) {
  const q = query.toLowerCase();
  return history.filter((e) => (e.app + '\n' + e.summary + '\n' + e.body).toLowerCase().includes(q));
}

// One group per app, the app with the newest entry first, each group newest first.
export function group(entries) {
  const groups = [];
  const byApp = new Map();
  for (const e of entries.slice().sort((a, b) => b.time - a.time)) {
    if (!byApp.has(e.app)) {
      byApp.set(e.app, { app: e.app, entries: [] });
      groups.push(byApp.get(e.app));
    }
    byApp.get(e.app).entries.push(e);
  }
  return groups;
}

export const clampSelected = (selected, length) => Math.max(0, Math.min(length - 1, selected));

// A notification is about files when our own senders list them, or niri's screenshot names one in image-path.
const isPath = (p) => typeof p === 'string' && p.startsWith('/');
const validFiles = (f) => Array.isArray(f) && f.every(isPath);

// Temp files and icon theme images are never the file a notification is about; ".." could walk out of a folder checked by prefix.
function userFile(path, home) {
  if (!isPath(path) || path.split('/').includes('..') || path.startsWith('/tmp/')) return false;
  return !['/usr/share/icons/', '/usr/share/pixmaps/', home + '/.local/share/icons/', home + '/.icons/'].some((d) => path.startsWith(d));
}

function hintPath(value) {
  if (typeof value !== 'string') return '';
  if (!value.startsWith('file://')) return value;
  try {
    return decodeURIComponent(value.slice(7));
  } catch (e) {
    return '';
  }
}

export function filesOf(hints, home) {
  const listed = typeof hints['x-dots-files'] === 'string' ? hints['x-dots-files'].split('\n').filter((l) => userFile(l, home)) : [];
  if (listed.length > 0) return listed;
  const image = hintPath(hints['image-path'] || hints['image_path']);
  return userFile(image, home) ? [image] : [];
}

export const fileUri = (path) => 'file://' + path.split('/').map(encodeURIComponent).join('/');

// RFC 2483: each URI ends with CRLF.
export const uriList = (files) => files.map((f) => fileUri(f) + '\r\n').join('');

export function chipLabel(files) {
  if (files.length !== 1) return files.length + ' FILES';
  const name = files[0].slice(files[0].lastIndexOf('/') + 1);
  const dot = name.lastIndexOf('.');
  return dot > 0 && dot < name.length - 1 ? name.slice(dot + 1).toUpperCase() : 'FILE';
}

export const dragPayload = (entry) =>
  entry.files && entry.files.length > 0 ? { mime: 'text/uri-list', data: uriList(entry.files) } : { mime: 'text/plain', data: entry.body };
