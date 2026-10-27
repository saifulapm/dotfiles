import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initial, reduce, outputView, focusedOutput, shares } from './niri.mjs';

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

// Captured from niri 26.04: the first burst says the overview is closed, then Mod+O opens and closes it.
const OVERVIEW_START = '{"OverviewOpenedOrClosed":{"is_open":false}}';
const OVERVIEW_OPEN = '{"OverviewOpenedOrClosed":{"is_open":true}}';

test('the overview reads open after niri opens it and closed after it closes', () => {
  assert.equal(run([...LINES, OVERVIEW_START]).overview, false);
  assert.equal(run([...LINES, OVERVIEW_START, OVERVIEW_OPEN]).overview, true);
  assert.equal(run([...LINES, OVERVIEW_OPEN, OVERVIEW_START]).overview, false);
});

test('a shell that starts while the overview is open reads it open from the first burst', () => {
  assert.equal(run([...LINES, OVERVIEW_OPEN]).overview, true);
});

// Captured from a nested niri 26.04 while wf-recorder started and stopped; the PipeWire casts follow niri-ipc's Cast, since a nested niri cannot start one.
const NO_CASTS = '{"CastsChanged":{"casts":[]}}';
const WF = '{"CastStartedOrChanged":{"cast":{"stream_id":1,"session_id":1,"kind":"WlrScreencopy","target":{"Output":{"name":"winit"}},"is_dynamic_target":false,"is_active":true,"pid":1315790,"pw_node_id":null}}}';
const WF_STOPPED = '{"CastStopped":{"stream_id":1}}';
const pw = (stream, session, target, active = true) => JSON.stringify({ CastStartedOrChanged: { cast: { stream_id: stream, session_id: session, kind: 'PipeWire', target, is_dynamic_target: true, is_active: active, pid: null, pw_node_id: 40 + stream } } });

test('a cast reads as a share until niri says it stopped', () => {
  const live = run([NO_CASTS, WF]);
  assert.deepEqual(shares(live, 0), [{ stream: 1, session: 1, kind: 'WlrScreencopy', target: 'screen', app: null, active: true, pid: 1315790 }]);
  assert.deepEqual(shares(run([WF_STOPPED], live), 0), []);
});

test("the shell's own wf-recorder is no share, and no recording leaves every cast in", () => {
  const live = run([NO_CASTS, WF, pw(2, 2, { Output: { name: 'winit' } })]);
  assert.deepEqual(shares(live, 1315790).map((s) => s.stream), [2]);
  assert.deepEqual(shares(live, 0).map((s) => s.stream), [1, 2]);
});

test('a window share names its app as the margin does, and a cleared or paused one says so', () => {
  const live = run([...LINES, pw(2, 2, { Window: { id: 2 } }), pw(3, 3, 'Nothing'), pw(4, 4, { Window: { id: 99 } }, false)]);
  assert.deepEqual(
    shares(live, 0).map((s) => [s.target, s.app, s.active]),
    [['window', 'foot', true], ['nothing', null, true], ['window', null, false]],
  );
});

test('a change to a cast replaces it in place, and a fresh CastsChanged replaces them all', () => {
  const live = run([NO_CASTS, pw(2, 2, { Output: { name: 'winit' } }), WF, pw(2, 2, 'Nothing')]);
  assert.deepEqual(shares(live, 0).map((s) => [s.stream, s.target]), [[2, 'nothing'], [1, 'screen']]);
  assert.deepEqual(shares(run([NO_CASTS], live), 0), []);
});

test('a share started before the shell arrives in the first burst', () => {
  const first = JSON.stringify({ CastsChanged: { casts: [JSON.parse(WF).CastStartedOrChanged.cast] } });
  assert.deepEqual(shares(run([...LINES, first]), 0).map((s) => s.stream), [1]);
  assert.deepEqual(shares(initial, 0), []);
});
