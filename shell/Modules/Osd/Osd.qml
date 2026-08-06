import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "OsdModel.js" as OsdModel

// On-screen display: one pill at the bottom of the screen carrying a glyph
// and either a progress bar with its readout or a message. Full port of
// omarchy's osd plugin (CREDITS.md) — their card geometry, their icon table,
// their show/replace/timeout choreography and their `osd` IPC surface — in
// our theme tokens.
//
// Our mechanics are kept: the logic is eager (it must observe changes while
// no window exists) and only the window is lazy; volume and mic react to
// PipeWire state, so any changer (wpctl keybinds, mixer apps, our own audio
// panel) raises the OSD without anything having to call us; brightness has no
// watchable API, so its keybinds call `qs ipc call osd brightnessUp|Down` and
// the new value is parsed out of brightnessctl's machine-readable output. No
// polling anywhere.
Scope {
    id: osdRoot

    required property var theme
    required property var audio

    // ---------------------------------------------------------- OSD state
    // Upstream's, one for one: `iconKey` is the name as asked for (the media
    // test reads it), `icon` the glyph it resolved to.
    property bool opened: false
    property string icon: ""
    property string message: ""
    property string iconKey: ""
    property int value: 0
    property int maxValue: 100
    property bool hasProgress: true
    property int duration: 1200

    readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0

    // Ours: the window is built on the first show and stays, so a login with
    // nothing to say costs no surface at all.
    property bool everShown: false

    // PipeWire pushes initial state shortly after startup; arm the observers
    // only after that settles so login doesn't flash an OSD. An explicit IPC
    // show is never gated — it was asked for.
    property bool armed: false
    property Timer armTimer: Timer {
        interval: 2000
        running: true
        onTriggered: osdRoot.armed = true
    }

    // The card is built out of measured columns instead of fixed widths, so it
    // keeps exactly `pad` between border and content on every side whatever
    // glyph or message it carries. Messages grow with their text up to
    // `maxMessageWidth` and elide beyond it.
    readonly property int pad: theme.space(4)
    readonly property int gap: theme.space(4)
    // A glyph next to a message reads airier than it measures: the icon outline
    // and the letterforms both fall away from their ink extremes, so the space
    // between them opens up well past the nominal gap. Text takes two thirds of
    // it; the progress bar's hard edge keeps the full gap.
    readonly property int messageGap: Math.round(osdRoot.gap * 2 / 3)
    readonly property int barWidth: theme.space(35.5)
    readonly property int maxMessageWidth: osdRoot.mediaOsd ? theme.space(81.25) : theme.space(47.5)
    readonly property int cardBorder: Math.max(theme.borderWidth, theme.space(0.5))

    // Nerd Font glyphs come from the symbols font directly — our UI and mono
    // families have no coverage, same rule as the bar's OpticalGlyph.
    readonly property string glyphFamily: "Symbols Nerd Font"
    readonly property int iconSize: theme.fontPx(2.333)
    readonly property int textSize: theme.fontPx(1.167)

    // Nerd Font glyphs draw well outside their monospace cell, so the icon
    // column is measured by ink rather than by advance width. Progress OSDs pin
    // it to the widest glyph the model can return, so the bar doesn't shift when
    // volume crosses an icon threshold.
    readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
    readonly property int iconWidth: osdRoot.hasProgress ? Math.max(osdRoot.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width)) : osdRoot.iconInkWidth
    // Same idea for the readout: it is as wide as the longest percentage so the
    // digits don't jitter between 9% and 100%.
    readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, messageMetrics.advanceWidth))
    readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), osdRoot.maxMessageWidth)
    readonly property int contentWidth: osdRoot.hasProgress ? osdRoot.iconWidth + osdRoot.gap + osdRoot.barWidth + osdRoot.gap + osdRoot.valueWidth : (osdRoot.message === "" ? osdRoot.iconWidth : osdRoot.iconWidth + osdRoot.messageGap + osdRoot.messageWidth)

    function iconFor(name, percent) {
        return OsdModel.iconFor(name, percent);
    }

    function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
        const next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration);
        // Update before opening so a fresh OSD starts at its new value; only
        // subsequent updates while it remains open animate the progress bar.
        iconKey = next.iconKey;
        maxValue = next.maxValue;
        hasProgress = next.hasProgress;
        value = next.value;
        message = next.message;
        icon = next.icon;
        duration = next.duration;
        everShown = true;
        opened = true;
        if (duration > 0)
            hideTimer.restart();
        else
            hideTimer.stop();
    }

    function open(payloadJson) {
        try {
            const p = JSON.parse(payloadJson || "{}");
            show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration));
        } catch (e) {}
    }

    function close() {
        opened = false;
    }

    property Timer hideTimer: Timer {
        interval: osdRoot.duration
        onTriggered: osdRoot.opened = false
    }

    // ------------------------------------------------------ reactive shows
    // The name their audio panel picks per level (their keybind script only
    // ever sends muted-or-high; the ladder is the same one our bar draws).
    function volumeIconName(level, muted) {
        if (muted || level <= 0)
            return "volume-muted";
        if (level >= 0.67)
            return "volume-high";
        if (level >= 0.34)
            return "volume-medium";
        return "volume-low";
    }

    // Percent is passed unclamped as the readout while the bar's own value
    // clamps at `max`: PipeWire allows volumes above 100%, and this is the
    // treatment that falls out of their model — a full bar over a truthful
    // number, rather than a number that stops at 100.
    function showVolume() {
        const level = audio.volume;
        const percent = Math.round(level * 100);
        show(volumeIconName(level, audio.muted), "", String(percent), "100", percent + "%", "");
    }

    // Their `omarchy-audio-input-mute` OSD, wording included: a glyph and a
    // message, no bar.
    function showMic() {
        show(audio.micMuted ? "microphone-muted" : "microphone", audio.micMuted ? "Microphone muted" : "Microphone on", "", "100", "", "");
    }

    property Connections audioWatch: Connections {
        target: osdRoot.audio

        function onVolumeChanged() {
            if (osdRoot.armed)
                osdRoot.showVolume();
        }

        function onMutedChanged() {
            if (osdRoot.armed)
                osdRoot.showVolume();
        }

        function onMicMutedChanged() {
            if (osdRoot.armed)
                osdRoot.showMic();
        }
    }

    // Setting running=true on an already-running Process queues at most one
    // re-run, so N rapid keypresses would apply fewer than N steps. The
    // delta accumulates here instead, and each process exit flushes whatever
    // is still owed as one combined step.
    property int pendingBrightnessSteps: 0

    function brightnessAdjust(direction) {
        pendingBrightnessSteps += direction > 0 ? 1 : -1;
        flushBrightness();
    }

    function flushBrightness() {
        if (brightnessProc.running || pendingBrightnessSteps === 0)
            return;
        const steps = pendingBrightnessSteps;
        pendingBrightnessSteps = 0;
        const magnitude = Math.abs(steps) * 10 + "%";
        brightnessProc.command = ["brightnessctl", "--class=backlight", "-m", "set", steps > 0 ? "+" + magnitude : magnitude + "-"];
        brightnessProc.running = true;
    }

    property Process brightnessProc: Process {
        onExited: osdRoot.flushBrightness()
        stdout: StdioCollector {
            onStreamFinished: {
                // machine-readable: device,class,current,percent%,max
                const parts = text.trim().split(",");
                if (parts.length >= 4) {
                    const pct = parseInt(parts[3], 10);
                    if (isFinite(pct))
                        osdRoot.show("brightness", "", String(pct), "100", pct + "%", "");
                }
            }
        }
    }

    // ----------------------------------------------------------- measuring
    property TextMetrics messageMetrics: TextMetrics {
        font.family: osdRoot.theme.fontMono
        font.bold: true
        font.pixelSize: osdRoot.textSize
        text: osdRoot.message
    }

    property TextMetrics valueMetrics: TextMetrics {
        font: osdRoot.messageMetrics.font
        text: "100%"
    }

    property TextMetrics iconMetrics: TextMetrics {
        font.family: osdRoot.glyphFamily
        font.pixelSize: osdRoot.iconSize
        text: osdRoot.icon
    }

    property TextMetrics widestIconMetrics: TextMetrics {
        font: osdRoot.iconMetrics.font
        text: OsdModel.widestIcon
    }

    // ----------------------------------------------------------------- IPC
    // `show` takes their whole payload, so anything that can spawn a process
    // can raise any OSD kind: `qs ipc call osd show '{"icon":"brightness",
    // "value":40}'`. brightnessUp/brightnessDown/status are ours and stay —
    // the niri brightness binds and the status probe call them.
    property IpcHandler ipc: IpcHandler {
        target: "osd"

        function show(payloadJson: string): string {
            osdRoot.open(payloadJson);
            return "ok";
        }

        function close(): string {
            osdRoot.close();
            return "ok";
        }

        function state(): string {
            return osdRoot.opened ? "open" : "closed";
        }

        function ping(): string {
            return "ok";
        }

        function brightnessUp(): string {
            osdRoot.brightnessAdjust(1);
            return "ok";
        }

        function brightnessDown(): string {
            osdRoot.brightnessAdjust(-1);
            return "ok";
        }

        function status(): string {
            return JSON.stringify({
                armed: osdRoot.armed,
                showing: osdRoot.opened,
                everShown: osdRoot.everShown,
                kind: osdRoot.iconKey,
                level: osdRoot.hasProgress ? osdRoot.value / osdRoot.maxValue : 0,
                icon: osdRoot.icon,
                message: osdRoot.message,
                value: osdRoot.value,
                maxValue: osdRoot.maxValue,
                hasProgress: osdRoot.hasProgress,
                duration: osdRoot.duration,
                audioReady: osdRoot.audio.ready,
                sinkNull: osdRoot.audio.sink === null,
                volume: osdRoot.audio.volume,
                muted: osdRoot.audio.muted,
                sourceNull: osdRoot.audio.source === null,
                sourceAudioNull: osdRoot.audio.source !== null && osdRoot.audio.source.audio === null,
                micMuted: osdRoot.audio.micMuted
            });
        }
    }

    // -------------------------------------------------------------- window
    Loader {
        active: osdRoot.everShown

        sourceComponent: PanelWindow {
            // Held through the fade-out: the surface is input-transparent
            // (empty mask below), so keeping it mapped costs nothing.
            visible: osdRoot.opened || card.opacity > 0
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            WlrLayershell.namespace: "qshell-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            // Visual-only surface: keep the layer-shell input region empty so
            // the OSD never blocks clicks to the desktop below it.
            mask: Region {}

            // Pill-shaped compositor blur behind the glass fill while the
            // Blur service is on (see BarPanel.qml).
            BackgroundEffect.blurRegion: osdRoot.theme.blurActive && osdRoot.opened ? pillBlurRegion : null

            Region {
                id: pillBlurRegion
                item: card
                radius: card.radius
            }

            Rectangle {
                id: card

                width: osdRoot.cardBorder + osdRoot.pad + osdRoot.contentWidth + osdRoot.pad + osdRoot.cardBorder
                height: osdRoot.cardBorder + osdRoot.pad + osdRoot.iconSize + osdRoot.pad + osdRoot.cardBorder
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: osdRoot.theme.space(16.75)
                color: osdRoot.theme.glass(osdRoot.theme.alpha(osdRoot.theme.surface1, 0.97))
                border.width: osdRoot.cardBorder
                border.color: osdRoot.theme.accent
                radius: osdRoot.theme.radius(1)

                // Fade + a small rise into place; the pill used to pop.
                opacity: osdRoot.opened ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: osdRoot.theme.time(0.8)
                        easing.type: osdRoot.theme.easing
                    }
                }
                transform: Translate {
                    y: osdRoot.opened ? 0 : osdRoot.theme.space(1.5)
                    Behavior on y {
                        NumberAnimation {
                            duration: osdRoot.theme.time(0.8)
                            easing.type: osdRoot.theme.easing
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: osdRoot.cardBorder + osdRoot.pad
                    spacing: osdRoot.hasProgress ? osdRoot.gap : osdRoot.messageGap

                    Item {
                        width: osdRoot.iconWidth
                        height: parent.height

                        Text {
                            // Sit the glyph's ink flush in the column, centered
                            // when the column is wider than this particular
                            // glyph.
                            x: Math.round((osdRoot.iconWidth - osdRoot.iconInkWidth) / 2 - osdRoot.iconMetrics.tightBoundingRect.x)
                            anchors.verticalCenter: parent.verticalCenter
                            text: osdRoot.icon
                            font: osdRoot.iconMetrics.font
                            color: osdRoot.theme.textPrimary
                        }
                    }

                    Rectangle {
                        visible: osdRoot.hasProgress
                        width: osdRoot.barWidth
                        height: osdRoot.theme.space(1.5)
                        anchors.verticalCenter: parent.verticalCenter
                        // Ours, not theirs: their rounding token is 0, so their
                        // bar is square by construction. A theme that rounds
                        // its corners rounds this one's too.
                        radius: osdRoot.theme.radiusBase > 0 ? height / 2 : 0
                        color: osdRoot.theme.alpha(osdRoot.theme.textPrimary, 0.45)

                        Rectangle {
                            height: parent.height
                            width: parent.width * (osdRoot.hasProgress ? osdRoot.value / osdRoot.maxValue : 0)
                            radius: parent.radius
                            color: osdRoot.theme.accent

                            Behavior on width {
                                enabled: osdRoot.opened
                                NumberAnimation {
                                    duration: osdRoot.theme.time(1)
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    Text {
                        visible: osdRoot.message !== ""
                        width: osdRoot.hasProgress ? osdRoot.valueWidth : osdRoot.messageWidth
                        // The readout hugs the card edge so a short percentage
                        // doesn't leave a hole in the padding; the slack lands
                        // in the gap after the bar.
                        horizontalAlignment: osdRoot.hasProgress ? Text.AlignRight : Text.AlignLeft
                        anchors.verticalCenter: parent.verticalCenter
                        text: osdRoot.message
                        font: osdRoot.messageMetrics.font
                        color: osdRoot.theme.textPrimary
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
        }
    }
}
