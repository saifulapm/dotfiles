// Clipboard rows from `dots-clip list`, which prints the pinned clips as "pin:name\tpreview" and then `cliphist list`'s "id\tpreview", newest first.
const IMAGE = /^\[\[ binary data (\S+ \S+) \S+ \d+x\d+ \]\]$/;
// Terminals paste on Ctrl+Shift+V, by app_id as niri reports it; every other window pastes on Ctrl+V.
export const TERMINALS = ['foot', 'footclient', 'kitty', 'Alacritty', 'com.mitchellh.ghostty', 'org.wezfurlong.wezterm'];
// The clip is decoded inside sh, so its content never becomes shell text; it is pasted, not typed, so a newline never presses Return and a terminal's paste mode guards its shell.
const PASTE =
  'cliphist -db-path "$1" decode "$2" | wl-copy; sleep 0.1; ' +
  'case " $3 " in *" $(niri msg -j focused-window | jq -r \'.app_id // ""\') "*) wtype -M ctrl -M shift -k v -m shift -m ctrl ;; *) wtype -M ctrl -k v -m ctrl ;; esac';

// Shift+Enter puts the clip on the clipboard and presses nothing.
const COPY = 'cliphist -db-path "$1" decode "$2" | wl-copy';
// A pinned clip is its own file beside the db, in clip-pins, so it is copied from there, and the terminals are its second argument.
const PASTE_PIN = PASTE.replace('cliphist -db-path "$1" decode "$2" | wl-copy', 'wl-copy <"$1"').replace('" $3 "', '" $2 "');
const PIN = /^pin:(\d+)$/;
const pinFile = (db, name) => db.replace(/[^/]*$/, 'clip-pins/') + name;

// How long ago a clip was copied, as its card reads it.
function ageText(s) {
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)} min`;
  if (s < 86400) return `${Math.floor(s / 3600)} h`;
  return `${Math.floor(s / 86400)} d`;
}

// bin/dots-clip-store logs "id epoch" per copy; a clip copied again logs a newer line, which wins.
function stamps(times) {
  const at = new Map();
  for (const line of (times || '').split('\n')) {
    const [id, t] = line.split(' ');
    if (id && t && Number.isFinite(Number(t))) at.set(id, Number(t));
  }
  return at;
}

const HEX = /^#[0-9a-f]{6}$/i;

// times is the clip-times log and now the epoch in seconds; a clip with no stamp has no age.
export function clipRows(text, q, db, times = '', now = 0) {
  const needle = q.trim().toLowerCase();
  const at = stamps(times);
  return text
    .split('\n')
    .filter((line) => line.includes('\t'))
    .map((line) => {
      const id = line.slice(0, line.indexOf('\t'));
      const preview = line.slice(id.length + 1);
      const image = preview.match(IMAGE);
      const pin = id.match(PIN);
      const from = pin ? ['sh', pinFile(db, pin[1])] : ['sh', db, id];
      return {
        title: image ? (pin ? 'image' : 'image · ' + image[1]) : preview,
        detail: '',
        glyph: image ? '◫' : '¶',
        age: at.has(id) ? ageText(now - at.get(id)) : '',
        image: !!image,
        swatch: HEX.test(preview) ? preview : '',
        id,
        pinned: !!pin,
        file: pin ? pinFile(db, pin[1]) : '',
        exec: ['sh', '-c', pin ? PASTE_PIN : PASTE, ...from, TERMINALS.join(' ')],
        copyExec: pin ? ['sh', '-c', 'wl-copy <"$1"', ...from] : ['sh', '-c', COPY, ...from],
      };
    })
    .filter((r) => r.title.toLowerCase().includes(needle));
}
