import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initial, reduce, focusedOutput, shares, outputWorkspaces, edgeToEdge, covered, configNotifies, reconnected } from './niri.mjs';

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

const shownIdx = (s) => outputWorkspaces(s, 'winit').find((w) => w.active).idx;

test('an empty workspace and going back to workspace 1 move the shown workspace', () => {
  assert.equal(shownIdx(run([...LINES, ...WS2])), 2);
  assert.equal(shownIdx(run([...LINES, ...WS2, ...WS1])), 1);
});

test('closing the second window leaves the first', () => {
  assert.deepEqual(run([...LINES, ...SECOND_FOOT, ...CLOSE_SECOND]).windows.map((w) => w.id), [2]);
});

test('a title change arrives as WindowOpenedOrChanged and replaces the title', () => {
  assert.equal(run([...LINES, RETITLE]).windows.find((w) => w.id === 2).title, '~/Codes/dotfiles');
});

test('the reply to the EventStream request leaves the state as it was', () => {
  const s = run(LINES);
  assert.equal(reduce(s, JSON.parse('{"Ok":"Handled"}')), s);
});

test('the focused output is the output of the focused workspace', () => {
  assert.equal(focusedOutput(run(LINES)), 'winit');
});

test('before any event there is no focused output', () => {
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

test('a window share names its app, and a cleared or paused one says so', () => {
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

// niri 26.04's urgency events, as server.rs sends them: a workspace is urgent while any window on it is.
const ws = (id, idx, output, urgent = false, active = false) => ({ id, idx, name: null, output, is_urgent: urgent, is_active: active, is_focused: active, active_window_id: null });
const workspaces = (...list) => JSON.stringify({ WorkspacesChanged: { workspaces: list } });
const wsUrgency = (id, urgent) => JSON.stringify({ WorkspaceUrgencyChanged: { id, urgent } });

test('a window keeps the urgency niri last reported for it', () => {
  const s = run([...LINES, '{"WindowUrgencyChanged":{"id":2,"urgent":true}}']);
  assert.equal(s.windows.find((w) => w.id === 2).is_urgent, true);
  assert.equal(run(['{"WindowUrgencyChanged":{"id":2,"urgent":false}}'], s).windows.find((w) => w.id === 2).is_urgent, false);
});

test("an output's workspaces list in number order, each saying whether it is shown and urgent", () => {
  const s = run([workspaces(ws(3, 3, 'eDP-1'), ws(1, 1, 'eDP-1'), ws(5, 1, 'HDMI-A-1', false, true), ws(2, 2, 'eDP-1', false, true)), wsUrgency(3, true)]);
  assert.deepEqual(outputWorkspaces(s, 'eDP-1'), [
    { idx: 1, active: false, urgent: false },
    { idx: 2, active: true, urgent: false },
    { idx: 3, active: false, urgent: true },
  ]);
  assert.deepEqual(outputWorkspaces(initial, 'eDP-1'), []);
});

// niri 26.04 numbers each tiled window's column from 1 in pos_in_scrolling_layout and gives a floating window none.
const win = (id, col, workspace = 1) => ({ id, title: 'foot', app_id: 'foot', workspace_id: workspace, is_focused: false, is_floating: col === null, is_urgent: false, layout: { pos_in_scrolling_layout: col === null ? null : [col, 1], tile_pos_in_workspace_view: null } });
const windows = (...list) => JSON.stringify({ WindowsChanged: { windows: list } });
const activeWindow = (id) => JSON.stringify({ WorkspaceActiveWindowChanged: { workspace_id: 1, active_window_id: id } });
const shown = workspaces(ws(1, 1, 'eDP-1', false, true), ws(2, 2, 'eDP-1'));

// eDP-1 is 2048 px wide at scale 1.25: Mod+F leaves a 1984 px tile inside the struts, and Mod+M or fullscreen a 2048 px one.
const sized = (id, w) => ({ ...win(id, 1), layout: { ...win(id, 1).layout, tile_size: [w, 1196.0] } });

test('only a shown window as wide as its output is edge to edge', () => {
  assert.equal(edgeToEdge(run([shown, windows(sized(1, 2048.0)), activeWindow(1)]), 'eDP-1', 2048), true);
  assert.equal(edgeToEdge(run([shown, windows(sized(1, 1984.0)), activeWindow(1)]), 'eDP-1', 2048), false);
  assert.equal(edgeToEdge(run([shown, windows(sized(1, 2048.0), sized(2, 1984.0)), activeWindow(2)]), 'eDP-1', 2048), false);
  assert.equal(edgeToEdge(run([shown, windows(sized(1, 2048.0)), activeWindow(1)]), 'HDMI-A-1', 2048), false);
  assert.equal(edgeToEdge(initial, 'eDP-1', 2048), false);
});

// Each line a ConfigLoaded, as niri sends it on every load and once in the first burst; counts the notifications along the way.
const loads = (failures, state = initial) =>
  failures.reduce(
    ({ s, n }, failed) => {
      const next = reduce(s, { ConfigLoaded: { failed } });
      return { s: next, n: n + (configNotifies(s, next) ? 1 : 0) };
    },
    { s: state, n: 0 },
  );

test('the first rejected config since the shell started notifies', () => {
  assert.equal(loads([true]).n, 1);
  assert.equal(loads([false, true]).n, 1);
});

test('further rejections notify nothing until a good config loads', () => {
  assert.equal(loads([true, true, true]).n, 1);
  assert.equal(loads([true, false, true]).n, 2);
  assert.equal(loads([true, true, false, false, true, true]).n, 2);
});

test('good loads alone never notify', () => {
  assert.equal(loads([false, false]).n, 0);
  assert.equal(loads([]).s.configFailed, false);
});

test("a reconnect's replayed rejection does not notify a streak twice", () => {
  const { s } = loads([true]);
  const again = reconnected(s);
  assert.deepEqual(again.workspaces, []);
  assert.equal(loads([true, true], again).n, 0);
  assert.equal(loads([false, true], again).n, 1);
});

test('a reconnect after a good load notifies the next rejection', () => {
  assert.equal(loads([true], reconnected(loads([true, false]).s)).n, 1);
});

test('a window focused long enough takes its new focus timestamp', () => {
  const state = reduce(initial, { WindowsChanged: { windows: [{ id: 1, pid: 300, focus_timestamp: { secs: 1, nanos: 0 } }, { id: 2, pid: 300, focus_timestamp: null }] } });
  const after = reduce(state, { WindowFocusTimestampChanged: { id: 2, focus_timestamp: { secs: 9, nanos: 5 } } });
  assert.deepEqual(after.windows.map((w) => w.focus_timestamp), [{ secs: 1, nanos: 0 }, { secs: 9, nanos: 5 }]);
});

test("an output is covered while its shown workspace holds a window, tiled or floating, and bare once it holds none", () => {
  const ws = (id, output, active) => ({ id, idx: id, output, is_active: active, is_focused: false, is_urgent: false, active_window_id: null });
  const win = (id, workspace_id) => ({ id, workspace_id, app_id: 'foot', title: '', layout: { pos_in_scrolling_layout: null, tile_size: [800, 600] } });
  const state = { workspaces: [ws(1, 'DP-1', true), ws(2, 'DP-1', false), ws(3, 'HDMI-A-1', true)], windows: [win(10, 2)], overview: false, casts: [], configFailed: false };
  assert.equal(covered(state, 'DP-1'), false, 'the window sits on a workspace not shown');
  assert.equal(covered(Object.assign({}, state, { windows: [win(10, 1)] }), 'DP-1'), true);
  assert.equal(covered(Object.assign({}, state, { windows: [win(10, 1)] }), 'HDMI-A-1'), false);
  assert.equal(covered(initial, 'DP-1'), false, 'before niri has said anything');
});
