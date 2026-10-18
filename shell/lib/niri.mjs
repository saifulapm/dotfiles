// niri's event stream folded into the workspaces and windows the shell shows. Pure, so node
// can test it on captured events; services/Niri.qml feeds it one parsed line at a time.

export const initial = { workspaces: [], windows: [] };

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
    case 'WindowOpenedOrChanged':
      return set(state, { windows: [...state.windows.filter((w) => w.id !== e.window.id), e.window] });
    case 'WindowClosed':
      return set(state, { windows: state.windows.filter((w) => w.id !== e.id) });
    default:
      return state;
  }
}

// The active workspace on an output and the window active in it, or null before niri has
// told us about that output.
export function outputView(state, output) {
  const ws = state.workspaces.find((w) => w.output === output && w.is_active);
  if (!ws) return null;
  const win = state.windows.find((w) => w.id === ws.active_window_id);
  return { idx: ws.idx, app: win ? win.app_id : null, title: win ? win.title : null };
}

export function focusedOutput(state) {
  return state.workspaces.find((w) => w.is_focused)?.output ?? null;
}
