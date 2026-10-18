import Quickshell
import Quickshell.Io
import QtQuick
import "lib/control-system.mjs" as Lib

// Control's Display section: the built-in panel by brightnessctl, external screens by ddcutil.
Item {
    id: display

    required property var theme
    property int selected: 0
    property var panels: []
    property var externals: []
    readonly property var rows: panels.map(p => ({
                title: p.device,
                detail: p.percent + "%"
            })).concat(externals.map(e => ({
                title: e.name,
                detail: "external"
            })))

    // Only a step like 5%+ reaches either tool, as argv.
    function key(event) {
        if (event.key !== Qt.Key_H && event.key !== Qt.Key_L)
            return false;
        const up = event.key === Qt.Key_L;
        if (selected < panels.length) {
            if (!setter.running) {
                setter.command = ["brightnessctl", "-m", "-d", panels[selected].device, "set", up ? "5%+" : "5%-"];
                setter.running = true;
            }
        } else if (externals[selected - panels.length]) {
            Quickshell.execDetached(["ddcutil", "-d", String(externals[selected - panels.length].display), "setvcp", "10", up ? "+" : "-", "5"]);
        }
        return true;
    }

    function state() {
        return { panels: panels };
    }

    implicitHeight: hint.implicitHeight

    Process {
        running: true
        command: ["brightnessctl", "-m", "-l", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: display.panels = Lib.backlights(text)
        }
    }

    // ddcutil takes seconds to probe the buses, so it runs once, as the section loads.
    Process {
        running: true
        command: ["ddcutil", "detect", "--terse"]
        stdout: StdioCollector {
            onStreamFinished: display.externals = Lib.ddcDisplays(text)
        }
    }

    // brightnessctl -m prints the device's new line, so its row follows without a re-read.
    Process {
        id: setter
        stdout: StdioCollector {
            onStreamFinished: {
                const set = Lib.backlights(text)[0];
                if (set)
                    display.panels = display.panels.map(p => p.device === set.device ? set : p);
            }
        }
    }

    Text {
        id: hint
        textFormat: Text.PlainText
        leftPadding: 20
        text: "H/L BRIGHTNESS"
        color: display.theme.color.muted
        font.family: display.theme.tokens ? display.theme.tokens.type.ui : ""
        font.pixelSize: 10
        font.letterSpacing: 1.2
    }
}
