import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/idle.mjs" as Lib

// Idle steps: dim, then lock, then monitors off, each held back by any idle inhibitor.
Scope {
    id: idle

    required property var lock
    // The shell's loader of the Surfaces window (active, item).
    required property var surfaces
    property var times: Lib.TIMES
    // How often a step asked niri to turn the monitors off, so a check can see the request.
    property int monitorsOff: 0

    readonly property bool dimmed: monitors.item?.dimmed ?? false
    // The local hub rings a question here only while neither of v1's qshell flags it reads (workflow's hub/src/presence.rs) has stood 5 minutes; an agent's lease counts as locked, since no one is at the screen.
    readonly property string flags: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/qshell"
    readonly property bool away: lock.secure || lock.leased

    // One writer at a time, so a dim lifted at once cannot have its rm land before its create; a flag keeps its first time, which the hub reads as how long it has stood. The command is built here, since a change handler runs before a binding on the same change would update.
    function writeFlags() {
        if (flagWriter.running) {
            flagWriter.dirty = true;
            return;
        }
        flagWriter.command = ["sh", "-c", flagWriter.script, "sh", flags, dimmed ? "1" : "0", away ? "1" : "0"];
        flagWriter.running = true;
    }

    onDimmedChanged: writeFlags()
    onAwayChanged: writeFlags()
    Component.onCompleted: writeFlags()

    Process {
        id: flagWriter
        property bool dirty: false
        // v1's stay-awake flag would hold the hub at watching through any idle; v2's stay awake removes the steps instead, so the idle flag already reads right.
        readonly property string script: 'mkdir -p "$1" && rm -f "$1/stay-awake" || exit 1; set_flag() { if [ "$2" = 1 ]; then [ -e "$1" ] || : >"$1"; else rm -f "$1"; fi; }; set_flag "$1/idle" "$2"; set_flag "$1/locked" "$3"'
        onExited: {
            if (!dirty)
                return;
            dirty = false;
            // running still reads true inside its own exited handler.
            Qt.callLater(idle.writeFlags);
        }
    }

    // An IdleMonitor keeps the timeout it was made with, so new times make new monitors. Stay awake removes them, which lifts a dim at once, and its end makes fresh ones.
    Loader {
        id: monitors
        active: Root.State.awakeUntil === 0
        sourceComponent: steps
    }

    // Runs only while stay awake holds; its end brings the steps back.
    Root.Tick {
        interval: 1000
        repeat: true
        running: Root.State.awakeUntil > 0
        onTriggered: {
            if (Date.now() >= Root.State.awakeUntil)
                Root.State.awakeUntil = 0;
        }
    }

    onTimesChanged: {
        monitors.sourceComponent = null;
        monitors.sourceComponent = steps;
    }

    Component {
        id: steps

        Item {
            readonly property bool dimmed: dim.isIdle

            IdleMonitor {
                id: dim
                timeout: idle.times[0]
                respectInhibitors: true
            }

            IdleMonitor {
                timeout: idle.times[1]
                respectInhibitors: true
                // An agent's lease keeps the session unlocked through idle; its own end locks.
                onIsIdleChanged: {
                    if (isIdle && !idle.lock.leased)
                        idle.lock.lockNow();
                }
            }

            IdleMonitor {
                timeout: idle.times[2]
                respectInhibitors: true
                onIsIdleChanged: {
                    if (!isIdle)
                        return;
                    idle.monitorsOff += 1;
                    Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"]);
                }
            }
        }
    }

    // A 50 % overlay on every output, so an external screen's own brightness is never touched; its windows exist only while dimmed.
    LazyLoader {
        active: idle.dimmed

        Variants {
            model: Quickshell.screens

            PanelWindow {
                required property var modelData
                screen: modelData
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "dots-dim"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: Qt.rgba(0, 0, 0, 0.5)
                mask: Region {}
            }
        }
    }

    Root.Ipc {
        target: "idle"

        // A test hook: shorter steps, in seconds; anything but three rising whole numbers is ignored.
        function times(dimS: int, lockS: int, offS: int): void {
            const t = [dimS, lockS, offS];
            if (Lib.validTimes(t))
                idle.times = t;
        }

        // `dots awake <minutes>`: hold the steps off that long; off, 0 or anything not whole minutes up to a day ends the hold.
        function awake(minutes: string): string {
            Root.State.awakeUntil = Lib.awakeEnd(Date.now(), Lib.awakeMinutes(minutes));
            return state();
        }

        function state(): string {
            return JSON.stringify({ dimmed: idle.dimmed, times: idle.times, monitorsOff: idle.monitorsOff, awakeUntil: Root.State.awakeUntil });
        }
    }
}
