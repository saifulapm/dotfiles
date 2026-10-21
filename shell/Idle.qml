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

    // An IdleMonitor keeps the timeout it was made with, so new times make new monitors.
    Loader {
        id: monitors
        sourceComponent: steps
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

        function state(): string {
            return JSON.stringify({ dimmed: idle.dimmed, times: idle.times, monitorsOff: idle.monitorsOff });
        }
    }
}
