// Clipboard rows from `cliphist list`, which prints "id\tpreview" newest first.
const IMAGE = /^\[\[ binary data (\S+ \S+) \S+ \d+x\d+ \]\]$/;
// The clip is decoded inside sh, so its content never becomes shell text; the sleep lets niri hand the keyboard back to the window first.
const COPY = 'cliphist -db-path "$1" decode "$2" | wl-copy';
// The watcher stores the copy again under a new id, so the text is decoded before the copy.
const PASTE = 't=$(cliphist -db-path "$1" decode "$2"); ' + COPY + '; sleep 0.1; wtype -- "$t"';

// An image is copied only, since wtype types text.
export function clipRows(text, q, db) {
  const needle = q.trim().toLowerCase();
  return text
    .split('\n')
    .filter((line) => line.includes('\t'))
    .map((line) => {
      const id = line.slice(0, line.indexOf('\t'));
      const preview = line.slice(id.length + 1);
      const image = preview.match(IMAGE);
      return {
        title: image ? 'image · ' + image[1] : preview,
        detail: '',
        id,
        exec: ['sh', '-c', image ? COPY : PASTE, 'sh', db, id],
      };
    })
    .filter((r) => r.title.toLowerCase().includes(needle));
}
