// Conversations kept as one JSON file each, named by start time; the list and the files are plain data so the shell only reads and writes them.
export const KEEP = 50;

// ':' and '.' are swapped so the name is a safe filename, and the ISO form sorts by time as a string.
export function fileName(startMs) {
  return new Date(startMs).toISOString().replace(/[:.]/g, '-') + '.json';
}

// An attachment is kept by name and size only: its bytes and text stay out of the file.
function keep(m) {
  const out = { role: m.role, content: m.content };
  if (m.role === 'user' && m.attachments) out.attachments = m.attachments.map((a) => ({ name: a.name, size: a.size, kind: a.kind }));
  if (m.tools) out.tools = m.tools.map((t) => ({ name: t.name, arg: t.arg }));
  return out;
}

export function serialize(conv) {
  return JSON.stringify({ start: conv.start, title: conv.title, alias: conv.alias, model: conv.model, messages: conv.messages.map(keep) });
}

// A broken file is skipped, so the list still draws.
export function parse(text) {
  try {
    const conv = JSON.parse(text);
    if (conv && typeof conv.start === 'number' && Array.isArray(conv.messages)) return conv;
  } catch (e) {
    // not JSON
  }
  return null;
}

// Names sort by time, so the oldest come first; anything that is not a .json file is not ours to delete.
export function prune(names) {
  const files = names.filter((n) => n.endsWith('.json')).sort();
  return files.slice(0, Math.max(0, files.length - KEEP));
}

function firstLine(conv) {
  const m = (conv.messages || []).find((x) => x.role === 'user');
  return m ? String(m.content).trim().split('\n')[0].trim() : '';
}

function cutTo(s, n) {
  return s.length > n ? s.slice(0, n) + '…' : s;
}

export function title(conv) {
  return cutTo(firstLine(conv), 60) || 'New chat';
}

function ageText(s) {
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)} min`;
  if (s < 86400) return `${Math.floor(s / 3600)} h`;
  return `${Math.floor(s / 86400)} d`;
}

export function rows(convs, nowMs) {
  return [...convs]
    .sort((a, b) => b.start - a.start)
    .map((c) => ({ file: c.file, start: c.start, title: c.title, question: cutTo(firstLine(c), 80), age: ageText((nowMs - c.start) / 1000) }));
}
