// The launcher's calculator: a recursive descent parser, so no string is ever evaluated.

const NUMBER = /^(\d+\.?\d*|\.\d+)/;

function tokens(text) {
  const out = [];
  let s = text.trim();
  while (s) {
    const m = NUMBER.exec(s);
    if (m) {
      out.push(Number(m[0]));
      s = s.slice(m[0].length).trimStart();
    } else if ('+-*/%^()'.includes(s[0])) {
      out.push(s[0]);
      s = s.slice(1).trimStart();
    } else return null;
  }
  return out;
}

// Returns a finite number, or null for anything incomplete, invalid or infinite.
export function calc(text) {
  const t = tokens(text);
  if (!t || !t.length) return null;
  let i = 0;
  const fail = () => {
    throw new Error('bad');
  };
  const take = (...ops) => (ops.includes(t[i]) ? t[i++] : null);

  function atom() {
    if (typeof t[i] === 'number') return t[i++];
    if (take('(') === null) fail();
    const v = expr();
    if (take(')') === null) fail();
    return v;
  }
  function unary() {
    if (take('-')) return -unary();
    const base = atom();
    return take('^') ? Math.pow(base, unary()) : base;
  }
  function term() {
    let v = unary();
    for (let op; (op = take('*', '/', '%')); ) {
      const r = unary();
      v = op === '*' ? v * r : op === '/' ? v / r : v % r;
    }
    return v;
  }
  function expr() {
    let v = term();
    for (let op; (op = take('+', '-')); ) v = op === '+' ? v + term() : v - term();
    return v;
  }

  try {
    const v = expr();
    return i === t.length && Number.isFinite(v) ? v : null;
  } catch (e) {
    return null;
  }
}

// Ten significant digits, so 0.1 + 0.2 reads 0.3.
export function format(n) {
  return String(Number(n.toPrecision(10)));
}
