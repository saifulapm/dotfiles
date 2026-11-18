// The mem tools the model may call. Each runs as an argv with no shell, and only the read commands search, show and wiki can ever sit in command position.
export const RESULT_MAX = 8192;
export const CALLS_MAX = 10;
const ARG_MAX = 200;

const tool = (name, description, params) => {
  const properties = {};
  for (const [p, d] of params) properties[p] = { type: 'string', description: d };
  return { type: 'function', function: { name, description, parameters: { type: 'object', properties, required: params.map(([p]) => p) } } };
};

export const TOOLS = [
  tool('mem_search', 'Search the project memory (decisions, findings, wiki, tasks) for a phrase.', [['query', 'Words to search for']]),
  tool('mem_show', 'Show one memory entry in full by its id.', [['id', 'The entry id, as search lists it']]),
  tool('mem_wiki', 'Read one wiki page of a project.', [
    ['project', 'The project name'],
    ['slug', 'The wiki page slug'],
  ]),
];

const ARGV = {
  mem_search: (a) => ['search', '--scope', 'all', a.query],
  mem_show: (a) => ['show', a.id],
  mem_wiki: (a) => ['--project', a.project, 'wiki', a.slug],
};

function parseArgs(argsJson) {
  try {
    const a = JSON.parse(argsJson);
    return a && typeof a === 'object' && !Array.isArray(a) ? a : null;
  } catch (e) {
    return null;
  }
}

// A leading "-" would be read as a flag (--stdin turns wiki into a write, and these argvs have no "--" separator), and a newline or NUL has no place in one argument.
function refusal(name, value) {
  if (typeof value !== 'string') return `${name} must be a string`;
  if (value === '') return `${name} is empty`;
  if (value.startsWith('-')) return `${name} must not start with "-"`;
  if (value.includes('\n') || value.includes('\r') || value.includes('\0')) return `${name} must be one line`;
  if (value.length > ARG_MAX) return `${name} is over ${ARG_MAX} characters`;
  return '';
}

export function argvFor(name, argsJson) {
  if (!Object.prototype.hasOwnProperty.call(ARGV, name)) return { error: `${name} is not a tool here` };
  const args = parseArgs(argsJson);
  if (!args) return { error: 'the arguments are not a JSON object' };
  const params = TOOLS.find((t) => t.function.name === name).function.parameters.required;
  for (const p of params) {
    const why = refusal(p, args[p]);
    if (why) return { error: why };
  }
  return { argv: ARGV[name](args) };
}

// What the chat draws for a call: the tool name and its argument, muted.
export function chipFor(name, argsJson) {
  const a = parseArgs(argsJson) || {};
  const arg = name === 'mem_wiki' ? [a.project, a.slug] : [name === 'mem_show' ? a.id : a.query];
  return { name, arg: arg.every((s) => typeof s === 'string') ? arg.join(' · ') : '' };
}

// Qt's JS engine has no TextEncoder, so the UTF-8 length is counted from code points.
function utf8(cp) {
  return cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
}

const MARK = '\n…(cut)';

function size(s) {
  let n = 0;
  for (const ch of s) n += utf8(ch.codePointAt(0));
  return n;
}

// A result over 8 KiB of UTF-8 is cut on a character boundary, marker included in the budget.
export function cut(text) {
  const s = String(text ?? '');
  if (size(s) <= RESULT_MAX) return s;
  let left = RESULT_MAX - size(MARK);
  let out = '';
  for (const ch of s) {
    left -= utf8(ch.codePointAt(0));
    if (left < 0) break;
    out += ch;
  }
  return out + MARK;
}

export function take(calls, spent) {
  const room = Math.max(0, CALLS_MAX - spent);
  return { run: calls.slice(0, room), skipped: calls.slice(room) };
}
