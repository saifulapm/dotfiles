// Pure pieces of agent questions from the local hub's $XDG_RUNTIME_DIR/hub-questions.json, kept here so node can test them.

// The hub names machines by MagicDNS host, perhaps with a port; an address stays whole.
const shortMachine = (host) => (/^[0-9.:]+$/.test(host) ? host : host.split('.')[0].split(':')[0]);

const str = (v) => (typeof v === 'string' ? v : '');

export function parseQuestions(text) {
  let data = null;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return [];
  }
  if (data === null || typeof data !== 'object' || !Array.isArray(data.questions)) return [];
  return data.questions
    .filter((q) => q !== null && typeof q === 'object' && typeof q.id === 'string' && q.id !== '')
    .map((q) => ({
      id: q.id,
      project: str(q.project),
      machine: shortMachine(str(q.machine)),
      text: str(q.text),
      options: Array.isArray(q.options) ? q.options.filter((o) => typeof o === 'string') : [],
      recommend: str(q.recommend),
      popup: q.popup === true,
    }));
}

// `away` maps an id to true once it is answered or put away with Esc.
export const shown = (questions, away) => questions.find((q) => q.popup && !away[q.id]) ?? null;

export function optionFor(question, key) {
  // A key with no text (Shift, an arrow, Mod) must pick nothing, though indexOf('') is 0.
  const i = key.length === 1 ? '123456789'.indexOf(key) : -1;
  return i >= 0 && i < question.options.length ? question.options[i] : null;
}

// Question text and answers are untrusted, so they only ever travel as argv elements. Signed popup: the hub passes only a slack, popup or cli answer to the machine that asked.
// Each attachment is a file on this machine; the hub copies it to the machine that asked. Qt's engine has no flatMap.
export const answerArgv = (id, text, files = []) => ['mem', 'answer', '--by', 'popup'].concat(...files.map((f) => ['--screenshot', f]), ['--', id, text]);

export const baseName = (path) => path.split('/').pop();

// The closed card's last line: how many options, and the one the agent recommends.
export function summary(question) {
  const n = question.options.length;
  if (n === 0) return 'No options · r to reply';
  return `${n} ${n === 1 ? 'option' : 'options'}` + (question.recommend ? ` · ★ ${question.recommend}` : '');
}

const escape = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// A web address: http(s)://, or a bare host under a common top-level domain, so file names such as deploy.yml stay text.
// The leading group stands in for a lookbehind: no word character, @, dot, slash, colon or dash just before it.
const WEB = /(^|[^\w@./:-])(https?:\/\/[^\s<>"']+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:com|org|net|io|dev|app|ai|co|gg|xyz|tv|uk|bd|info|site|cloud)(?::\d+)?(?![\w-])(?:\/[^\s<>"']*)?)/gi;

// Question text as Text.StyledText with each web address a link whose href is its index in `urls`, so only an address found here is ever opened.
export function linkify(text) {
  const urls = [];
  let html = '';
  let at = 0;
  WEB.lastIndex = 0;
  for (let m = WEB.exec(text); m; m = WEB.exec(text)) {
    let link = m[2];
    // Sentence punctuation after an address, and a closing bracket it never opened, are not part of it.
    for (;;) {
      const trimmed = link.replace(/[.,;:!?'"]+$/, '');
      const closes = trimmed.endsWith(')') && trimmed.split('(').length < trimmed.split(')').length;
      const next = closes ? trimmed.slice(0, -1) : trimmed;
      if (next === link) break;
      link = next;
    }
    const start = m.index + m[1].length;
    html += escape(text.slice(at, start)) + `<a href="${urls.length}">${escape(link)}</a>`;
    urls.push(/^https?:\/\//i.test(link) ? link : `https://${link}`);
    at = start + link.length;
  }
  html += escape(text.slice(at));
  return { html: html.replace(/\n/g, '<br>'), urls };
}
