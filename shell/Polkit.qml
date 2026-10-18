import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import QtQuick

// The polkit agent; it registers as the shell starts and shows its prompt in the Surfaces window.
Scope {
    id: polkit

    // The shell's LazyLoader of the Surfaces window.
    required property var surfaces
    readonly property var prompt: surfaces.item?.polkit ?? null

    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: {
            polkit.surfaces.active = true;
            polkit.surfaces.item.openPolkit(flow);
        }
        onIsActiveChanged: {
            if (!isActive)
                polkit.prompt?.finish();
        }
    }

    IpcHandler {
        target: "polkit"

        function state(): string {
            const shown = polkit.prompt ? JSON.parse(polkit.prompt.state()) : { open: false };
            return JSON.stringify(Object.assign(shown, { registered: agent.isRegistered, active: agent.isActive }));
        }
    }
}
