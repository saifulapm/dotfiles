// The subset of TOML that theme files use: tables, strings, numbers, bools and string arrays.
export function parseToml(text) {
  const doc = {};
  let table = doc;
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = stripComment(lines[i]).trim();
    if (!line) continue;
    const head = line.match(/^\[([A-Za-z0-9_-]+)\]$/);
    if (head) {
      table = doc[head[1]] = doc[head[1]] ?? {};
      continue;
    }
    const kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(.*)$/);
    if (!kv) throw new Error(`toml line ${i + 1}: cannot read "${line}"`);
    let raw = kv[2];
    const start = i;
    if (raw.startsWith('[')) {
      while (!raw.includes(']') && i + 1 < lines.length) raw += ' ' + stripComment(lines[++i]).trim();
    }
    table[kv[1]] = value(raw, start + 1);
  }
  return doc;
}

function stripComment(line) {
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    if (line[i] === '"') quoted = !quoted;
    else if (line[i] === '#' && !quoted) return line.slice(0, i);
  }
  return line;
}

function value(raw, lineNo) {
  if (/^"[^"]*"$/.test(raw)) return raw.slice(1, -1);
  if (raw === 'true' || raw === 'false') return raw === 'true';
  if (/^-?\d+(\.\d+)?$/.test(raw)) return Number(raw);
  const arr = raw.match(/^\[(.*)\]$/);
  if (arr) {
    return arr[1].split(',').map((s) => s.trim()).filter(Boolean).map((s) => value(s, lineNo));
  }
  throw new Error(`toml line ${lineNo}: cannot read value ${raw}`);
}
