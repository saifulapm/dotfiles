// Starting after the playing event: mpv's window can take up to a minute to map, so the card stays up with a step saying so until it does.

export function steps(st) {
  return st.playing ? st.steps.concat([{ text: 'mpv is opening', state: 'current' }]) : st.steps;
}

// True once `niri msg -j windows` lists a window with mpv's app id.
export function mpvMapped(text) {
  let windows;
  try {
    windows = JSON.parse(String(text));
  } catch (e) {
    return false;
  }
  return Array.isArray(windows) && windows.some((w) => w && w.app_id === 'mpv');
}
