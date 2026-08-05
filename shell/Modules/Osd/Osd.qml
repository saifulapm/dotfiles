import QtQuick
import Quickshell
import Quickshell.Io

// On-screen display for volume / mic / brightness. Logic is eager (it must
// observe changes while no window exists); the window itself loads on first
// show and is visible only while the OSD is up.
//
// Volume/mic react to PipeWire state — any changer (keybind wpctl, mixer
// apps) triggers the OSD. Brightness has no watchable API, so keybinds call
// `qs ipc call osd brightnessUp|Down` and the new value is parsed from
// brightnessctl's machine-readable output. No polling anywhere.
Scope {
    id: osdRoot

    required property var theme
    required property var audio

    property bool showing: false
    property bool everShown: false
    property string kind: "volume"   // volume | mic | brightness
    property real level: 0
    property bool muted: false

    // PipeWire pushes initial state shortly after startup; arm the observers
    // only after that settles so login doesn't flash an OSD.
    property bool armed: false
    property Timer armTimer: Timer {
        interval: 2000
        running: true
        onTriggered: osdRoot.armed = true
    }

    function trigger(newKind, newLevel, newMuted) {
        kind = newKind;
        level = newLevel;
        muted = newMuted;
        everShown = true;
        showing = true;
        hideTimer.restart();
    }

    property Timer hideTimer: Timer {
        interval: 1500
        onTriggered: osdRoot.showing = false
    }

    property Connections audioWatch: Connections {
        target: osdRoot.audio

        function onVolumeChanged() {
            if (osdRoot.armed)
                osdRoot.trigger("volume", osdRoot.audio.volume, osdRoot.audio.muted);
        }

        function onMutedChanged() {
            if (osdRoot.armed)
                osdRoot.trigger("volume", osdRoot.audio.volume, osdRoot.audio.muted);
        }

        function onMicMutedChanged() {
            if (osdRoot.armed)
                osdRoot.trigger("mic", osdRoot.audio.micMuted ? 0 : 1, osdRoot.audio.micMuted);
        }
    }

    function brightnessAdjust(direction) {
        brightnessProc.command = ["brightnessctl", "--class=backlight", "-m", "set", direction > 0 ? "+10%" : "10%-"];
        brightnessProc.running = true;
    }

    property Process brightnessProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                // machine-readable: device,class,current,percent%,max
                const parts = text.trim().split(",");
                if (parts.length >= 4) {
                    const pct = parseInt(parts[3], 10);
                    if (isFinite(pct))
                        osdRoot.trigger("brightness", pct / 100, false);
                }
            }
        }
    }

    Loader {
        active: osdRoot.everShown

        sourceComponent: PanelWindow {
            visible: osdRoot.showing
            anchors.bottom: true
            margins.bottom: osdRoot.theme.space(12)
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: 280
            implicitHeight: osdRoot.theme.space(12)

            Rectangle {
                anchors.fill: parent
                radius: osdRoot.theme.radius(1)
                color: osdRoot.theme.surface2
                border.width: osdRoot.theme.borderWidth
                border.color: osdRoot.theme.surface3

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: osdRoot.theme.space(4)
                    anchors.rightMargin: osdRoot.theme.space(4)
                    spacing: osdRoot.theme.space(3)

                    Text {
                        id: osdIcon
                        anchors.verticalCenter: parent.verticalCenter
                        color: osdRoot.muted ? osdRoot.theme.textMuted : osdRoot.theme.accent
                        font.family: osdRoot.theme.fontMono
                        font.pixelSize: osdRoot.theme.fontPx(0.917)
                        font.weight: Font.DemiBold
                        text: {
                            if (osdRoot.kind === "brightness")
                                return "scr";
                            if (osdRoot.kind === "mic")
                                return "mic";
                            return "vol";
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - osdIcon.width - osdText.width - osdRoot.theme.space(6)
                        height: osdRoot.theme.space(1.5)
                        radius: height / 2
                        color: osdRoot.theme.alpha(osdRoot.theme.textPrimary, 0.15)

                        Rectangle {
                            width: parent.width * Math.min(1, osdRoot.level)
                            height: parent.height
                            radius: parent.radius
                            color: osdRoot.muted ? osdRoot.theme.textMuted : osdRoot.theme.accent

                            Behavior on width {
                                NumberAnimation {
                                    duration: osdRoot.theme.time(0.6)
                                    easing.type: osdRoot.theme.easing
                                }
                            }
                        }
                    }

                    Text {
                        id: osdText
                        anchors.verticalCenter: parent.verticalCenter
                        color: osdRoot.theme.textPrimary
                        font.family: osdRoot.theme.fontMono
                        font.pixelSize: osdRoot.theme.fontPx(0.917)
                        text: osdRoot.muted && osdRoot.kind !== "brightness" ? "muted" : Math.round(osdRoot.level * 100) + "%"
                    }
                }
            }
        }
    }
}
