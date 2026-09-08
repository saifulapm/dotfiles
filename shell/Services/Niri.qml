import QtQuick
import Quickshell
import Quickshell.Io

// niri IPC over $NIRI_SOCKET. Event stream only — state arrives as pushed
// deltas, never by polling. Socket + SplitParser pattern per DMS.
// Wire format verified against ~/ref/niri/niri-ipc/src/lib.rs.
QtObject {
    id: root

    // Workspace objects as niri sends them: id, idx, name, output,
    // is_active, is_focused, is_urgent, active_window_id.
    property var workspaces: []
    // window id -> { title, appId, workspaceId, floating, column, tile,
    // tileWidth }. Mutated IN PLACE on per-window events — cloning the whole
    // map per title change was steady GC pressure (S3) — so the property's
    // own change signal only fires for the full WindowsChanged snapshot.
    // windowsRevision is the change signal for mutations: anything DERIVING
    // from the map must reference it (the two bindings below do, and so does
    // the minimap widget); imperative readers at event time (Notifs'
    // click-to-focus) just read the live map.
    property var windows: ({})
    property int windowsRevision: 0
    property var focusedWindowId: null
    readonly property string focusedTitle: {
        windowsRevision;
        const w = focusedWindowId !== null ? windows[focusedWindowId] : undefined;
        return w && w.title ? w.title : "";
    }
    readonly property string focusedAppId: {
        windowsRevision;
        const w = focusedWindowId !== null ? windows[focusedWindowId] : undefined;
        return w && w.appId ? w.appId : "";
    }

    // XKB layout names + active index, pushed by KeyboardLayoutsChanged /
    // KeyboardLayoutSwitched. Empty until the first event after connect.
    property var keyboardLayouts: []
    property int keyboardLayoutIdx: 0
    readonly property string keyboardLayoutName: keyboardLayouts[keyboardLayoutIdx] || ""

    function switchKeyboardLayout() {
        request({
            Action: {
                SwitchLayout: {
                    layout: "Next"
                }
            }
        });
    }

    function closeFocusedWindow() {
        request({
            Action: {
                CloseWindow: {
                    id: null
                }
            }
        });
    }

    // Wire shape verified against ~/ref/niri/niri-ipc/src/lib.rs
    // (Action::FocusWindow { id: u64 }).
    function focusWindow(id) {
        request({
            Action: {
                FocusWindow: {
                    id: id
                }
            }
        });
    }

    function focusWorkspace(id) {
        request({
            Action: {
                FocusWorkspace: {
                    reference: {
                        Id: id
                    }
                }
            }
        });
    }

    // Requests staged while the socket is down. Writing straight after
    // `connected = true` would race the async dial — quickshell's Socket
    // silently discards write() until the connection is up — so disconnected
    // requests queue here and drain from onConnectionStateChanged.
    property var pendingRequests: []

    function request(obj) {
        const line = JSON.stringify(obj) + "\n";
        if (requestSocket.connected) {
            requestSocket.write(line);
            requestSocket.flush();
            return;
        }
        if (pendingRequests.length < 16)
            pendingRequests.push(line);
        requestSocket.connected = true;
    }

    // One window as the map holds it. Everything past `appId` is what the
    // minimap draws: which workspace the window is on, and where it sits in
    // that workspace's scrolling layout. niri's pos_in_scrolling_layout is
    // [column, tile-within-column], both 1-based, and null for a floating
    // window — which is also how `column: 0` reads downstream: not in the
    // scrolling layout, so not a pill.
    function windowEntry(w) {
        const entry = {
            title: w.title || "",
            appId: w.app_id || "",
            workspaceId: w.workspace_id !== undefined && w.workspace_id !== null ? w.workspace_id : -1,
            floating: w.is_floating === true,
            column: 0,
            tile: 0,
            tileWidth: 0
        };
        applyLayout(entry, w.layout);
        return entry;
    }

    // The layout half on its own: WindowLayoutsChanged pushes (id, layout)
    // pairs rather than whole windows, so a column resize or a move does not
    // re-send the title.
    function applyLayout(entry, layout) {
        const pos = layout ? layout.pos_in_scrolling_layout : null;
        entry.column = pos ? pos[0] : 0;
        entry.tile = pos ? pos[1] : 0;
        entry.tileWidth = layout && layout.tile_size ? layout.tile_size[0] : 0;
    }

    function handleEvent(ev) {
        const kind = Object.keys(ev)[0];
        const p = ev[kind];
        switch (kind) {
        case "WorkspacesChanged":
            workspaces = p.workspaces.slice().sort((a, b) => a.output === b.output ? a.idx - b.idx : (a.output < b.output ? -1 : 1));
            break;
        case "WorkspaceActivated":
            {
                const target = workspaces.find(w => w.id === p.id);
                if (!target)
                    break;
                workspaces = workspaces.map(w => {
                    const copy = Object.assign({}, w);
                    if (w.output === target.output)
                        copy.is_active = (w.id === p.id);
                    if (p.focused)
                        copy.is_focused = (w.id === p.id);
                    return copy;
                });
                break;
            }
        case "WorkspaceActiveWindowChanged":
            workspaces = workspaces.map(w => w.id === p.workspace_id ? Object.assign({}, w, {
                    active_window_id: p.active_window_id !== undefined ? p.active_window_id : null
                }) : w);
            break;
        case "WorkspaceUrgencyChanged":
            workspaces = workspaces.map(w => w.id === p.id ? Object.assign({}, w, {
                    is_urgent: p.urgent
                }) : w);
            break;
        case "WindowsChanged":
            {
                const next = {};
                let focused = null;
                for (const w of p.windows) {
                    next[w.id] = windowEntry(w);
                    if (w.is_focused)
                        focused = w.id;
                }
                windows = next;
                windowsRevision++;
                focusedWindowId = focused;
                break;
            }
        case "WindowOpenedOrChanged":
            {
                const w = p.window;
                windows[w.id] = windowEntry(w);
                windowsRevision++;
                if (w.is_focused)
                    focusedWindowId = w.id;
                break;
            }
        case "WindowLayoutsChanged":
            {
                // [[id, layout], …] — every window whose tile moved or
                // resized, which niri sends for the whole workspace when one
                // column changes.
                for (const change of p.changes) {
                    const entry = windows[change[0]];
                    if (entry)
                        applyLayout(entry, change[1]);
                }
                windowsRevision++;
                break;
            }
        case "WindowClosed":
            {
                delete windows[p.id];
                windowsRevision++;
                if (focusedWindowId === p.id)
                    focusedWindowId = null;
                break;
            }
        case "WindowFocusChanged":
            focusedWindowId = p.id !== undefined && p.id !== null ? p.id : null;
            break;
        case "KeyboardLayoutsChanged":
            keyboardLayouts = p.keyboard_layouts.names || [];
            keyboardLayoutIdx = p.keyboard_layouts.current_idx || 0;
            break;
        case "KeyboardLayoutSwitched":
            keyboardLayoutIdx = p.idx || 0;
            break;
        }
    }

    // quickshell's Socket never re-dials on its own (`connected: true` is a
    // constant binding), and niri drops event-stream clients that read too
    // slowly — without this timer one drop freezes workspace/window state
    // for the rest of the session.
    property Timer eventReconnect: Timer {
        interval: 1000
        onTriggered: root.eventSocket.connected = true
    }

    property Socket eventSocket: Socket {
        path: Quickshell.env("NIRI_SOCKET")
        connected: true
        onConnectionStateChanged: {
            if (connected) {
                // niri replays full WorkspacesChanged/WindowsChanged/
                // KeyboardLayoutsChanged state on every new subscription, so
                // a reconnect self-corrects anything missed while down.
                write("\"EventStream\"\n");
                flush();
            } else {
                root.eventReconnect.restart();
            }
        }
        parser: SplitParser {
            onRead: line => {
                try {
                    const ev = JSON.parse(line);
                    // The first reply is {"Ok":"Handled"} — not an event.
                    if (ev.Ok === undefined && ev.Err === undefined)
                        root.handleEvent(ev);
                } catch (e) {
                    console.warn("Niri: unparseable event:", line);
                }
            }
        }
    }

    property Socket requestSocket: Socket {
        path: Quickshell.env("NIRI_SOCKET")
        connected: true
        onConnectionStateChanged: {
            if (!connected)
                return;
            const queued = root.pendingRequests;
            root.pendingRequests = [];
            for (const line of queued)
                write(line);
            if (queued.length > 0)
                flush();
        }
        parser: SplitParser {
            onRead: line => {
                try {
                    const reply = JSON.parse(line);
                    if (reply.Err !== undefined)
                        console.warn("Niri request failed:", JSON.stringify(reply.Err));
                } catch (e) {}
            }
        }
    }
}
