import QtQuick
import Quickshell
import Quickshell.Io
import "../components"

// Pending reminders, ported from omarchy's Reminder indicator (CREDITS.md) —
// same glyph, same tooltip (the CLI's own wording in both states), same click
// rule (with reminders pending, click notifies the list; with none, it opens
// the capture flow) and the same `reminder show --json` contract.
//
// Their indicator is refreshed by the CLI poking the shell over IPC after
// every add and every fire. Ours watches the store the CLI writes instead:
// the file changing is the event, so the count is live without the CLI
// needing to know the shell exists — and the container needs no refresh
// broadcast. Nothing polls: a reminder's countdown does not move the count,
// and the entry disappears when its timer fires and rewrites the store.
BarIndicator {
    id: rootItem

    required property var shell

    property int count: 0
    property string tooltip: ""

    readonly property string binPath: Quickshell.env("HOME") + "/.dotfiles/bin/reminder"

    active: count > 0
    activeGlyph: "󰢌" // md-reminder
    inactiveGlyph: "󰢌"
    // The CLI writes both states' wording ("1 reminder" / "Set Reminder").
    activeTooltip: tooltip
    inactiveTooltip: tooltip

    function refresh() {
        if (!jsonProc.running)
            jsonProc.running = true;
    }

    function update(raw) {
        let data = ({});
        try {
            data = JSON.parse(String(raw || "{}"));
        } catch (e) {
            data = ({});
        }
        count = Number(data.count || 0);
        tooltip = String(data.tooltip || "");
    }

    // Upstream's click rule, plus a right-click that opens the flow even when
    // reminders are already pending (theirs can only be reached from the menu
    // once the indicator is showing).
    onTapped: button => {
        if (button === Qt.RightButton)
            rootItem.shell.toggleReminders();
        else if (rootItem.count > 0)
            Quickshell.execDetached([rootItem.binPath, "show"]);
        else
            rootItem.shell.toggleReminders();
    }

    Component.onCompleted: refresh()

    // The store is the event source. It is rewritten on add, on cancel, on
    // clear, and by the timer's own fire — every transition that changes the
    // count.
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/qshell/reminders.json"
        watchChanges: true
        printErrors: false
        onLoaded: rootItem.refresh()
        onFileChanged: reload()
        onLoadFailed: {
            rootItem.count = 0;
            rootItem.tooltip = "";
        }
    }

    // Reading the store directly would do, but the tooltip wording and the
    // reconciliation against live systemd timers both live in the CLI — one
    // source of truth, as upstream has it.
    Process {
        id: jsonProc
        command: [rootItem.binPath, "show", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: rootItem.update(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                rootItem.count = 0;
                rootItem.tooltip = "";
            }
        }
    }
}
