// Clipboard rows from `cliphist list`, which prints "id\tpreview" newest first.
const IMAGE = /^\[\[ binary data (\S+ \S+) \S+ \d+x\d+ \]\]$/;
// Terminals paste on Ctrl+Shift+V, by app_id as niri reports it; every other window pastes on Ctrl+V.
export const TERMINALS = ['foot', 'footclient', 'kitty', 'Alacritty', 'com.mitchellh.ghostty', 'org.wezfurlong.wezterm'];
// The clip is decoded inside sh, so its content never becomes shell text; it is pasted, not typed, so a newline never presses Return and a terminal's bracketed paste guards its shell.
const PASTE =
  'cliphist -db-path "$1" decode "$2" | wl-copy; sleep 0.1; ' +
  'case " $3 " in *" $(niri msg -j focused-window | jq -r \'.app_id // ""\') "*) wtype -M ctrl -M shift -k v -m shift -m ctrl ;; *) wtype -M ctrl -k v -m ctrl ;; esac';

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
        exec: ['sh', '-c', PASTE, 'sh', db, id, TERMINALS.join(' ')],
      };
    })
    .filter((r) => r.title.toLowerCase().includes(needle));
}
