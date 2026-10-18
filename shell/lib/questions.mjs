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

// Question text and answers are untrusted, so they only ever travel as argv elements.
export const answerArgv = (id, text) => ['mem', 'answer', '--by', 'island', '--', id, text];
