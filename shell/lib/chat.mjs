// The chat's reply path: pxy's server-sent events in, cleaned Markdown blocks out.
import { BIDI_SET, C1, DEL, klass } from './clean.mjs';

// ESC and the other C0 and C1 controls but tab and newline, and the bidi marks that reorder what a line reads as, are dropped from model output.
const UNSAFE = klass('\\u0000-\\u0008\\u000b-\\u001f' + DEL + C1 + BIDI_SET, 'g');

export function clean(text) {
  return String(text ?? '').replace(UNSAFE, '');
}

// Reads Qt's whole responseText on each readyState 3 and hands back only what arrived since, as parsed events. Only lines that end in a newline are read, so a chunk that ends mid-line, or mid-character (Qt decodes that as U+FFFD until the rest lands), waits for the next.
export function sse() {
  let pos = 0;
  let data = [];
  return {
    feed(text) {
      const events = [];
      let done = false;
      const end = text.lastIndexOf('\n') + 1;
      if (end <= pos) return { events, done };
      const lines = text.slice(pos, end).split('\n');
      lines.pop();
      pos = end;
      for (const raw of lines) {
        const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
        if (line === '') {
          if (!data.length) continue;
          const payload = data.join('\n');
          data = [];
          if (payload === '[DONE]') {
            done = true;
            continue;
          }
          try {
            events.push(JSON.parse(payload));
          } catch (e) {
            // a malformed event is skipped; the stream reads on
          }
        } else if (line.startsWith('data:')) {
          data.push(line.slice(line[5] === ' ' ? 6 : 5));
        }
      }
      return { events, done };
    },
  };
}

// A line this long, or a block this tall, laid out in one Text stalls the shell, so it draws cut; the block's text keeps all of it to copy.
const LINE_MAX = 4000;
const LINES_MAX = 400;
const DRAWN_MAX = 20000;

function escape(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function cutLines(text) {
  const lines = text.split('\n');
  const shown = lines.slice(0, LINES_MAX).map((l) => (l.length > LINE_MAX ? l.slice(0, LINE_MAX) + '…' : l));
  const out = shown.join('\n') + (lines.length > LINES_MAX ? '\n…' : '');
  return out.length > DRAWN_MAX ? out.slice(0, DRAWN_MAX) + '…' : out;
}

// Inline Markdown as Qt styled text: code spans first, so nothing inside them is read as emphasis.
function inline(text) {
  return cutLines(text)
    .split(/(`[^`\n]+`)/)
    .map((part, i) => {
      if (i % 2) return `<code>${escape(part.slice(1, -1))}</code>`;
      return escape(part)
        .replace(/\*\*([^*\n]+)\*\*/g, '<b>$1</b>')
        .replace(/(^|[^*\w])\*([^*\n]+)\*(?!\w)/g, '$1<i>$2</i>');
    })
    .join('');
}

export function render(block) {
  // A code block draws in a PlainText Text, so its text goes as is.
  if (block.kind === 'code') return cutLines(block.text);
  return inline(block.text).replace(/\n/g, '<br>');
}

const FENCE = /^ {0,3}(```|~~~)\s*([\w+#.-]*)/;

function kindOf(line) {
  if (FENCE.test(line)) return 'code';
  if (/^ {0,3}#{1,6}\s/.test(line)) return 'heading';
  if (/^ {0,3}>/.test(line)) return 'quote';
  if (/^ {0,3}\|/.test(line)) return 'table';
  if (/^ {0,3}([-*+]|\d+[.)])\s/.test(line)) return 'list';
  return 'p';
}

function strip(kind, lines) {
  if (kind === 'quote') return lines.map((l) => l.replace(/^ {0,3}> ?/, '')).join('\n');
  if (kind === 'heading') return lines.join('\n').replace(/^ {0,3}#{1,6}\s+/, '');
  return lines.join('\n');
}

// Cuts a reply into blocks (paragraph, heading, list, quote, table, code fence) as it grows. A closed block is rendered once and frozen; feed() hands back the same frozen objects each time, and only the open block is rendered again.
export function blocks(draw = render) {
  const closed = [];
  // where the open block starts in the reply, and the lines of it read so far
  let start = 0;
  let pos = 0;
  let lines = [];
  let kind = null;
  let fence = null;
  let lang = '';

  function make(blockKind, blockLines, at, isClosed) {
    const block = { kind: blockKind, start: at, closed: isClosed, lang: blockKind === 'code' ? lang : '' };
    block.text = blockKind === 'code' ? blockLines.slice(1).join('\n') : strip(blockKind, blockLines);
    block.html = draw(block);
    return block;
  }

  function close(at) {
    if (lines.length) closed.push(make(kind, lines, start, true));
    lines = [];
    kind = null;
    fence = null;
    start = at;
  }

  function line(l, next) {
    if (fence) {
      lines.push(l);
      if (new RegExp(`^ {0,3}${fence}\\s*$`).test(l) && lines.length > 1) {
        lines.pop();
        close(next);
      }
      return;
    }
    const k = kindOf(l);
    if (l.trim() === '') {
      close(next);
      return;
    }
    // a fence or a heading ends the paragraph or list before it, blank line or not
    if (lines.length && (k === 'code' || k === 'heading' || (kind === 'heading' && k !== 'heading'))) close(start + lines.reduce((n, x) => n + x.length + 1, 0));
    if (!lines.length) {
      kind = k;
      start = next - l.length - 1;
      if (k === 'code') {
        const m = l.match(FENCE);
        fence = m[1];
        lang = m[2];
      }
    }
    lines.push(l);
    if (kind === 'heading') close(next);
  }

  function open(text) {
    const tail = text.slice(pos);
    if (!lines.length && tail.trim() === '') return null;
    if (fence) {
      const body = [...lines, tail].slice(1).join('\n');
      const block = { kind: 'code', start, closed: false, lang, text: body };
      block.html = draw(block);
      return block;
    }
    const all = tail === '' ? lines : [...lines, tail];
    return make(kind ?? kindOf(tail), all, start, false);
  }

  return {
    feed(text) {
      let nl;
      while ((nl = text.indexOf('\n', pos)) >= 0) {
        const l = text.slice(pos, nl);
        pos = nl + 1;
        line(l, pos);
      }
      return { closed, open: open(text) };
    },
    // The reply is whole: its last line closes too.
    end(text) {
      this.feed(text);
      if (pos < text.length) {
        const l = text.slice(pos);
        pos = text.length;
        line(l, pos);
      }
      if (lines.length) close(pos);
      return { closed, open: null };
    },
  };
}
