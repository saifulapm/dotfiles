// The YouTube App's side of bin/dots-youtube-get: the download index it reads for the marks and the retries, and the rows a download takes on stdin.
import { oneLine } from './picker.mjs';

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const KINDS = ['audio', 'video'];

// downloads.json as dots-youtube-get writes it, {files, failed}; a file mid-write or broken reads as empty, and the next write's change reads it again.
export function index(text) {
  let i;
  try {
    i = JSON.parse(text);
  } catch (e) {
    i = null;
  }
  const pick = (o) => {
    const out = {};
    for (const [k, v] of Object.entries(isObject(o) ? o : {})) if (isObject(v)) out[k] = v;
    return out;
  };
  return { files: pick(i && i.files), failed: pick(i && i.failed) };
}

export const downloaded = (i, id) => Object.prototype.hasOwnProperty.call(i.files, id) && KINDS.some((k) => typeof i.files[id][k] === 'string');

// The reason comes from yt-dlp's error, so it draws as one line.
export function failedOf(i, id) {
  const f = Object.prototype.hasOwnProperty.call(i.failed, id) ? i.failed[id] : null;
  return f && KINDS.includes(f.kind) ? { kind: f.kind, reason: oneLine(f.reason) } : null;
}

// A row per line as dots-youtube-get reads its stdin; a title may hold any character, which JSON carries whole.
export const stdinLines = (rows) =>
  rows
    .filter((r) => r.kind === 'video' && !r.unavailable)
    .map((r) => JSON.stringify({ id: r.id, title: r.title }) + '\n')
    .join('');

// dots-youtube-get where's answer as the Queue plays it, {id: path}: a song's audio before its video; only an absolute path plays.
export function playFiles(answer) {
  const out = {};
  const files = answer && isObject(answer.files) ? answer.files : {};
  for (const [id, f] of Object.entries(files)) {
    const path = isObject(f) ? [f.audio, f.video].find((p) => typeof p === 'string' && p.startsWith('/')) : undefined;
    if (path) out[id] = path;
  }
  return out;
}
