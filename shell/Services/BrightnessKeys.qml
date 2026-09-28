import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "BrightnessModel.js" as BrightnessModel

// The display brightness keys (XF86MonBrightnessUp/Down → `qs-call
// brightness raise|lower`). On the internal panel they step the backlight
// here: one brightnessctl write and the OSD in process, instead of
// bin/brightness-display resolving the focused output with niri msg + jq,
// reading, writing and reading back through brightnessctl, then an IPC
// client for the OSD. They step, clamp and read back the way that script
// does, so either path lands on the same level and OSD. An external
// (DDC) output, or no known focus, goes through the script.
// Port of omarchy d3fb0284 (services/BrightnessKeys.qml); adaptations: the
// focused output comes from the Niri service instead of Hyprland, the
// device from brightnessctl's own pick instead of omarchy-hw-display, and
// the keys arrive over IPC — niri has no global shortcuts.
QtObject {
    id: root

    property var niri: null
    // The Osd module; null until its surface resolves.
    property var osd: null
    // The backlight brightnessctl --class=backlight picks, which is the one
    // bin/brightness-display drives (this MacBook has two: apple-panel-bl
    // and a 228600000.dsi.0 that is not the panel). Devices do not come and
    // go at runtime, but each press refreshes it for the next.
    property string device: ""
    readonly property string devicePath: device ? "/sys/class/backlight/" + device : ""

    // Returns false when the focused display is not one to handle here, so
    // the caller falls back to the script.
    function handle(action) {
        var name = "";
        var workspaces = niri ? niri.workspaces : [];
        for (var i = 0; i < workspaces.length; i++) {
            if (workspaces[i].is_focused)
                name = String(workspaces[i].output || "");
        }
        if (!/^(eDP|LVDS|DSI)-/.test(name) || !device)
            return false;

        // The script drops a press that overlaps one still being applied
        // (its flock), so key repeat cannot race the writes.
        if (setProc.running)
            return true;

        var max = readNumber(maxFile);
        if (!(max > 0))
            return false;
        var current = Math.round(100 * readNumber(brightnessFile) / max);

        setProc.command = ["brightnessctl", "-q", "-d", device, "set", BrightnessModel.brightnessKeyTarget(action, current) + "%"];
        setProc.running = true;
        return true;
    }

    // reload() reads in the background, so wait for it: text() would
    // otherwise still hold the previous reading, and a level changed
    // elsewhere (the monitor panel, a script) would step from the wrong place.
    function readNumber(file) {
        file.reload();
        file.waitForJob();
        return Number(String(file.text() || "").trim());
    }

    // The payload bin/brightness-display's show_osd builds, from the level
    // read back after the write.
    function showOsd() {
        var max = readNumber(maxFile);
        if (!osd || !(max > 0))
            return;
        var percent = Math.round(100 * readNumber(brightnessFile) / max);
        osd.open(JSON.stringify({
            icon: "brightness",
            value: percent,
            progressText: percent + "%"
        }));
    }

    property FileView brightnessFile: FileView {
        path: root.devicePath ? root.devicePath + "/brightness" : ""
        blockLoading: true
        printErrors: false
    }

    property FileView maxFile: FileView {
        path: root.devicePath ? root.devicePath + "/max_brightness" : ""
        blockLoading: true
        printErrors: false
    }

    property Process setProc: Process {
        onExited: {
            root.showOsd();
            if (!root.deviceProc.running)
                root.deviceProc.running = true;
        }
    }

    // machine-readable: device,class,current,percent%,max
    property Process deviceProc: Process {
        command: ["brightnessctl", "--class=backlight", "-m"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.device = String(text || "").trim().split(",")[0]
        }
    }

    property IpcHandler ipc: ShellIpc {
        target: "brightness"

        function raise(): string {
            if (!root.handle("raise"))
                Quickshell.execDetached(["brightness-display", "+5%"]);
            return "ok";
        }

        function lower(): string {
            if (!root.handle("lower"))
                Quickshell.execDetached(["brightness-display", "5%-"]);
            return "ok";
        }
    }
}
