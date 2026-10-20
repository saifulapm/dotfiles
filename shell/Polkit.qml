import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import QtQuick
import "." as Root

// The polkit agent; it registers right after the paper's first frame and shows its prompt in the Surfaces window.
Scope {
    id: polkit

    // The shell's loader of the Surfaces window (active, item).
    required property var surfaces
    readonly property var prompt: surfaces.item?.polkit ?? null

    PolkitAgent {
        id: agent
        // Quickshell 0.3.2 drops the shown request when another starts instead of queueing it, so a newcomer is refused and its caller gets an answer.
        onAuthenticationRequestStarted: {
            const shown = polkit.prompt?.flow;
            if (shown && !shown.isCompleted) {
                flow.cancelAuthenticationRequest();
                return;
            }
            polkit.surfaces.active = true;
            polkit.surfaces.item.openPolkit(flow);
        }
    }

    Root.Ipc {
        target: "polkit"

        function state(): string {
            const shown = polkit.prompt ? JSON.parse(polkit.prompt.state()) : { open: false };
            return JSON.stringify(Object.assign(shown, { registered: agent.isRegistered, active: agent.isActive }));
        }
    }
}
