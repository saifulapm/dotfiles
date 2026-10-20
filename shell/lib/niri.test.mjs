import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initial, reduce, outputView, focusedOutput } from './niri.mjs';

// Captured from niri 26.04's event stream: start, open foot, workspace 2, workspace 1, open and close a second foot.
const LINES = [
  '{"WorkspacesChanged":{"workspaces":[{"id":1,"idx":1,"name":null,"output":"winit","is_urgent":false,"is_active":true,"is_focused":true,"active_window_id":null}]}}',
  '{"WindowsChanged":{"windows":[]}}',
  '{"KeyboardLayoutsChanged":{"keyboard_layouts":{"names":["English (US)"],"current_idx":0}}}',
  '{"WorkspacesChanged":{"workspaces":[{"id":1,"idx":1,"name":null,"output":"winit","is_urgent":false,"is_active":true,"is_focused":true,"active_window_id":2},{"id":2,"idx":2,"name":null,"output":"winit","is_urgent":false,"is_active":false,"is_focused":false,"active_window_id":null}]}}',
  '{"WindowOpenedOrChanged":{"window":{"id":2,"title":"foot","app_id":"foot","pid":436321,"workspace_id":1,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[1,1],"tile_size":[1224.0,1475.0],"window_size":[1224,1475],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]},"focus_timestamp":{"secs":16093,"nanos":152239781}}}}',
];
const WS2 = ['{"WorkspaceActivated":{"id":2,"focused":true}}', '{"WindowFocusChanged":{"id":null}}'];
const WS1 = ['{"WorkspaceActivated":{"id":1,"focused":true}}', '{"WindowFocusChanged":{"id":2}}'];
const SECOND_FOOT = [
  '{"WorkspaceActiveWindowChanged":{"workspace_id":1,"active_window_id":3}}',
  '{"WindowOpenedOrChanged":{"window":{"id":3,"title":"foot","app_id":"foot","pid":436451,"workspace_id":1,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[2,1],"tile_size":[1224.0,1475.0],"window_size":[1224,1475],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]},"focus_timestamp":{"secs":16095,"nanos":685680175}}}}',
];
const CLOSE_SECOND = [
  '{"WorkspaceActiveWindowChanged":{"workspace_id":1,"active_window_id":2}}',
  '{"WindowFocusChanged":{"id":2}}',
  '{"WindowClosed":{"id":3}}',
];
const RETITLE =
  '{"WindowOpenedOrChanged":{"window":{"id":2,"title":"~/Codes/dotfiles","app_id":"foot","pid":436321,"workspace_id":1,"is_focused":true,"is_floating":false,"is_urgent":false,"layout":{"pos_in_scrolling_layout":[1,1],"tile_size":[1224.0,1475.0],"window_size":[1224,1475],"tile_pos_in_workspace_view":null,"window_offset_in_tile":[0.0,0.0]},"focus_timestamp":{"secs":16093,"nanos":152239781}}}}';

const run = (lines, state = initial) => lines.reduce((s, l) => reduce(s, JSON.parse(l)), state);

test('foot open on workspace 1 shows in the view of its output', () => {
  assert.deepEqual(outputView(run(LINES), 'winit'), { idx: 1, app: 'foot', title: 'foot' });
});

test('an empty workspace shows its index and no window', () => {
  assert.deepEqual(outputView(run([...LINES, ...WS2]), 'winit'), { idx: 2, app: null, title: null });
});

test('going back to workspace 1 shows foot again', () => {
  assert.deepEqual(outputView(run([...LINES, ...WS2, ...WS1]), 'winit'), { idx: 1, app: 'foot', title: 'foot' });
});

test('closing the second window returns the view to the first', () => {
  const s = run([...LINES, ...SECOND_FOOT, ...CLOSE_SECOND]);
  assert.deepEqual(s.windows.map((w) => w.id), [2]);
  assert.deepEqual(outputView(s, 'winit'), { idx: 1, app: 'foot', title: 'foot' });
});

test('a title change arrives as WindowOpenedOrChanged and replaces the title', () => {
  assert.deepEqual(outputView(run([...LINES, RETITLE]), 'winit'), { idx: 1, app: 'foot', title: '~/Codes/dotfiles' });
});

test('the reply to the EventStream request leaves the state as it was', () => {
  const s = run(LINES);
  assert.equal(reduce(s, JSON.parse('{"Ok":"Handled"}')), s);
});

test('the focused output is the output of the focused workspace', () => {
  assert.equal(focusedOutput(run(LINES)), 'winit');
});

test('before any event there is no view and no focused output', () => {
  assert.equal(outputView(initial, 'winit'), null);
  assert.equal(focusedOutput(initial), null);
});

test('a focus change moves is_focused to that window, or to none', () => {
  const run = (lines) => lines.reduce((s, l) => reduce(s, JSON.parse(l)), initial);
  const focused = (s) => s.windows.filter((w) => w.is_focused).map((w) => w.id);
  const s = run(LINES.concat(SECOND_FOOT));
  assert.deepEqual(focused(s), [3]);
  assert.deepEqual(focused(reduce(s, { WindowFocusChanged: { id: 2 } })), [2]);
  assert.deepEqual(focused(reduce(s, { WindowFocusChanged: { id: null } })), []);
});
