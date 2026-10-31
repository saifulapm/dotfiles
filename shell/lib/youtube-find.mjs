// How Search finds: a pasted YouTube link to open instead of searching, and a list of rows that pages on as the cursor nears its end. Kept pure so node can test it.
import { rows } from './youtube.mjs';

export const PAGE = 20;
// The cursor on any of the last 5 rows asks for the next page.
export const NEAR = 5;

// Only youtube.com, its subdomains and youtu.be open as links; a query with a space in it is text, even one naming YouTube.
const LINK = /^(https?:\/\/)?([a-z0-9-]+\.)*(youtube\.com|youtu\.be)(\/\S*)?$/i;

export const isLink = (text) => LINK.test(String(text).trim());

// A row already listed is dropped by id, as YouTube reorders between pages and repeats one now and then within a page.
function unique(list, seen) {
  const out = [];
  for (const r of list) {
    if (seen.has(r.id)) continue;
    seen.add(r.id);
    out.push(r);
  }
  return out;
}

// next is the CLI's own offset for the following page; a page shorter than 20 is the last.
export function page(answer) {
  const raw = answer && Array.isArray(answer.rows) ? answer.rows : [];
  return { rows: unique(rows(answer), new Set()), next: answer && Number.isInteger(answer.next) ? answer.next : raw.length, more: raw.length >= PAGE, loading: false };
}

export const wants = (list, cursor) => list.more && !list.loading && list.rows.length > 0 && cursor >= list.rows.length - NEAR;

export const asking = (list) => Object.assign({}, list, { loading: true });

// A failed page keeps the rows and their offset, so the next move asks again.
export function append(list, answer) {
  if (!answer || !Array.isArray(answer.rows)) return Object.assign({}, list, { loading: false });
  const more = page(answer);
  return { rows: list.rows.concat(unique(more.rows, new Set(list.rows.map((r) => r.id)))), next: more.next, more: more.more, loading: false };
}
