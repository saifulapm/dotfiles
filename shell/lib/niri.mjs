// Pure, so node can test it on captured events; services/Niri.qml feeds it one line at a time.

export const initial = { workspaces: [], windows: [], overview: false, casts: [], configFailed: false };

const set = (o, fields) => Object.assign({}, o, fields);

export function reduce(state, event) {
  const [name] = Object.keys(event);
  const e = event[name];
  switch (name) {
    case 'WorkspacesChanged':
      return set(state, { workspaces: e.workspaces });
    case 'WorkspaceActivated': {
      // The event names no output, so the activated workspace's output is looked up.
      const output = state.workspaces.find((w) => w.id === e.id)?.output;
      return set(state, {
        workspaces: state.workspaces.map((w) =>
          set(w, {
            is_active: w.output === output ? w.id === e.id : w.is_active,
            is_focused: e.focused ? w.id === e.id : w.is_focused,
          }),
        ),
      });
    }
    case 'WorkspaceActiveWindowChanged':
      return set(state, {
        workspaces: state.workspaces.map((w) =>
          w.id === e.workspace_id ? set(w, { active_window_id: e.active_window_id }) : w,
        ),
      });
    case 'WindowsChanged':
      return set(state, { windows: e.windows });
    case 'WindowOpenedOrChanged': {
      // A window that opens focused takes the focus from every other, with no WindowFocusChanged sent.
      const others = state.windows.filter((w) => w.id !== e.window.id).map((w) => (e.window.is_focused ? set(w, { is_focused: false }) : w));
      return set(state, { windows: others.concat([e.window]) });
    }
    case 'WindowFocusChanged':
      return set(state, { windows: state.windows.map((w) => set(w, { is_focused: w.id === e.id })) });
    case 'WindowLayoutsChanged': {
      // niri reports a column move or a shift into a closed window's place here, not in WindowOpenedOrChanged.
      const layouts = new Map(e.changes);
      return set(state, { windows: state.windows.map((w) => (layouts.has(w.id) ? set(w, { layout: layouts.get(w.id) }) : w)) });
    }
    case 'WindowClosed':
      return set(state, { windows: state.windows.filter((w) => w.id !== e.id) });
    case 'WorkspaceUrgencyChanged':
      return set(state, { workspaces: state.workspaces.map((w) => (w.id === e.id ? set(w, { is_urgent: e.urgent }) : w)) });
    case 'WindowUrgencyChanged':
      return set(state, { windows: state.windows.map((w) => (w.id === e.id ? set(w, { is_urgent: e.urgent }) : w)) });
    case 'OverviewOpenedOrClosed':
      return set(state, { overview: e.is_open });
    case 'CastsChanged':
      return set(state, { casts: e.casts });
    case 'CastStartedOrChanged': {
      const at = state.casts.findIndex((c) => c.stream_id === e.cast.stream_id);
      return set(state, { casts: at < 0 ? state.casts.concat([e.cast]) : state.casts.map((c, i) => (i === at ? e.cast : c)) });
    }
    case 'CastStopped':
      return set(state, { casts: state.casts.filter((c) => c.stream_id !== e.stream_id) });
    case 'ConfigLoaded':
      return set(state, { configFailed: e.failed });
    default:
      return state;
  }
}

// A rejected config notifies once per failure streak: the first rejection since the shell started, and the first after each good load.
export function configNotifies(before, after) {
  return after.configFailed && !before.configFailed;
}

// A reconnect starts niri's state over but keeps the failure, since the shell has already told this streak and niri's first burst replays the rejection.
export function reconnected(state) {
  return set(initial, { configFailed: state.configFailed });
}

// Null until niri has told us about that output.
export function outputView(state, output) {
  const ws = state.workspaces.find((w) => w.output === output && w.is_active);
  if (!ws) return null;
  const win = state.windows.find((w) => w.id === ws.active_window_id);
  return { idx: ws.idx, app: win ? win.app_id : null, title: win ? win.title : null };
}

// The numbers of the output's workspaces holding an urgent window, in workspace order.
export function urgentWorkspaces(state, output) {
  return state.workspaces
    .filter((w) => w.output === output && w.is_urgent)
    .map((w) => w.idx)
    .sort((a, b) => a - b);
}

// The focused column of the output's shown workspace, of its tiled columns; null while a floating window or none is focused there.
export function columnPosition(state, output) {
  const ws = state.workspaces.find((w) => w.output === output && w.is_active);
  const at = ws && state.windows.find((w) => w.id === ws.active_window_id)?.layout.pos_in_scrolling_layout?.[0];
  if (!at) return null;
  // niri shifts the columns before it reports the closed window, so for one event two windows share a number; the highest is the count.
  const cols = state.windows.filter((w) => w.workspace_id === ws.id && w.layout.pos_in_scrolling_layout).map((w) => w.layout.pos_in_scrolling_layout[0]);
  return { at, of: Math.max(...cols) };
}

// Whether the output's shown window spans its whole logical width, as only maximize-window-to-edges and fullscreen do, since the struts keep every tile 32 px in.
export function edgeToEdge(state, output, width) {
  const ws = state.workspaces.find((w) => w.output === output && w.is_active);
  const win = ws && state.windows.find((w) => w.id === ws.active_window_id);
  return !!win && win.layout.tile_size[0] >= width - 1;
}

export function focusedOutput(state) {
  return state.workspaces.find((w) => w.is_focused)?.output ?? null;
}

// Every cast but the shell's own recording, whose wf-recorder pid is ownPid (0 while it records nothing); a window's app is its app_id, as the margin names it.
export function shares(state, ownPid) {
  return state.casts
    .filter((c) => !(ownPid && c.pid === ownPid))
    .map((c) => {
      const window = c.target.Window ? state.windows.find((w) => w.id === c.target.Window.id) : null;
      return {
        stream: c.stream_id,
        session: c.session_id,
        kind: c.kind,
        target: c.target.Output ? 'screen' : c.target.Window ? 'window' : 'nothing',
        app: window ? window.app_id : null,
        active: c.is_active,
        pid: c.pid,
      };
    });
}
