// Pure pieces of the launcher, kept here so node can test them.

// Lower is better: exact name, name prefix, word prefix, substring, then a keyword match.
function tier(entry, q) {
  const name = entry.name.toLowerCase();
  if (name === q) return 0;
  if (name.startsWith(q)) return 1;
  if (name.split(/\s+/).some((w) => w.startsWith(q))) return 2;
  if (name.includes(q)) return 3;
  if (entry.keywords.some((k) => k.toLowerCase().includes(q))) return 4;
  return -1;
}

// Entries are plain {id, name, genericName, keywords}; returns the matches, best first and
// ties by name.
export function rank(entries, query) {
  const q = query.trim().toLowerCase();
  return entries
    .map((e) => ({ e, t: q ? tier(e, q) : 0, key: e.name.toLowerCase() }))
    .filter((x) => x.t >= 0)
    .sort((a, b) => a.t - b.t || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
    .map((x) => x.e);
}
