import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Wallpaper — full port of omarchy's background plugin (CREDITS.md): the new
// image is drawn behind a slanted parallelogram mask whose edge sweeps out
// from the screen's center (420 ms InOutCubic), the old image underneath
// until the sweep passes, per screen. A theme pushed with the transition is
// held until the reveal's first frame, so the palette and the wallpaper land
// together; a 300 ms fallback timer applies it anyway when a reveal never
// starts (missing image, unreadable path).
//
// Entry points: the watched state file ~/.local/state/qshell/background
// (written by bin/background-next --set — the picker, the cycle, and the
// degradation path when the shell is down) and the IPC surface below
// (bin/theme-set drives themeTransition for the synchronized switch).
//
// Their desktop double-click gestures (wallpaper picker / theme switcher) are
// deliberately NOT ported: this surface is placed within niri's backdrop
// (layer-rule place-within-backdrop), and niri excludes backdrop surfaces
// from every input-target lookup — in the overview too — so a pointer
// handler here could never fire (niri src/niri.rs surface_under()).
Scope {
    id: backgroundRoot

    required property var theme

    // The reveal's version-gated state machine, names theirs. currentBackground
    // is the path of record (what `current` reports and what a same-path
    // transition dedupes against); displayedBackground is the settled image;
    // incoming/old exist only while a reveal is in flight.
    property string currentBackground: ""
    property string displayedBackground: ""
    property string incomingBackground: ""
    property string oldBackground: ""
    property bool finishingTransition: false
    property int backgroundVersion: 0
    property int revealStartedVersion: -1
    property int pendingThemeVersion: -1
    property string pendingThemeRaw: ""
    property real revealProgress: 1

    // Per-segment percent-encoding: a raw '#' or '?' in the path would parse
    // as URL fragment/query and truncate it (same treatment as
    // FilePickerModel.pathToUrl).
    function fileUrl(path) {
        return path ? "file://" + String(path).split("/").map(encodeURIComponent).join("/") : "";
    }

    function setBackground(path, instant) {
        transitionBackground("", path, instant, false);
    }

    // Omarchy's transitionBackground minus its finalPath: their theme switch
    // hardlinks snapshots into a cache so the shown file survives the theme
    // directory being swapped out underneath it, and finalPath is the real
    // path recorded once the snapshot is displayed. Our theme files never
    // move, so the shown path and the recorded path are the same one.
    function transitionBackground(fromPath, path, instant, force) {
        path = String(path || "").trim();
        fromPath = String(fromPath || "").trim();
        if (!path || (!force && path === currentBackground))
            return;
        currentBackground = path;
        backgroundVersion += 1;
        revealStartedVersion = -1;

        revealAnimation.stop();
        finishingTransition = false;

        if (instant || !displayedBackground) {
            oldBackground = "";
            incomingBackground = "";
            displayedBackground = path;
            revealProgress = 1;
            return;
        }

        oldBackground = fromPath || displayedBackground;
        incomingBackground = path;
        revealProgress = 0;
    }

    function clearBackground() {
        revealAnimation.stop();
        currentBackground = "";
        displayedBackground = "";
        incomingBackground = "";
        oldBackground = "";
        finishingTransition = false;
        revealProgress = 1;
        backgroundVersion += 1;
        revealStartedVersion = -1;
        // A clear landing between setPendingTheme and the reveal frame would
        // otherwise leave the palette waiting on the 300 ms fallback timer:
        // no reveal is coming, so apply it now.
        applyPendingTheme();
    }

    // The incoming palette rides with the transition and is applied on the
    // reveal's first frame (startReveal), not when the IPC lands — so the
    // theme flips with the wipe instead of a beat before it. While it is
    // pending, Theme.qml's file watch is latched off: theme-set writes
    // theme.toml right after this call returns, and the watch would apply
    // the same tokens early.
    function setPendingTheme(themeB64) {
        const raw = Qt.atob(String(themeB64 || ""));
        if (!raw)
            return;
        pendingThemeRaw = raw;
        pendingThemeVersion = backgroundVersion;
        theme.deferFileLoads = true;
        pendingThemeFallbackTimer.restart();
    }

    function applyPendingTheme() {
        if (pendingThemeVersion < 0)
            return;
        pendingThemeFallbackTimer.stop();
        theme.load(pendingThemeRaw);
        theme.deferFileLoads = false;
        pendingThemeVersion = -1;
        pendingThemeRaw = "";
    }

    function transitionBackgroundWithTheme(fromPath, path, themeB64) {
        transitionBackground(fromPath, path, false, true);
        setPendingTheme(themeB64);
        // No wallpaper to reveal (a theme with no backgrounds), or nothing on
        // screen yet: apply now rather than waiting on a reveal that will
        // never run.
        if (!incomingBackground || revealProgress >= 1)
            applyPendingTheme();
    }

    function startReveal(panel) {
        if (!incomingBackground)
            return;
        panel.maskReady = true;
        if (revealStartedVersion === backgroundVersion)
            return;
        revealStartedVersion = backgroundVersion;
        applyPendingTheme();
        revealAnimation.restart();
    }

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.local/state/qshell/background"
        watchChanges: true
        printErrors: false
        Component.onCompleted: reload()
        onLoaded: {
            const p = text().trim();
            if (p)
                backgroundRoot.transitionBackground("", p, false, false);
            else
                backgroundRoot.clearBackground();
        }
        onFileChanged: reload()
        onLoadFailed: backgroundRoot.clearBackground()
    }

    IpcHandler {
        target: "background"

        function refresh(): string {
            stateFile.reload();
            return "ok";
        }

        function set(path: string): string {
            backgroundRoot.setBackground(path, false);
            return "ok";
        }

        function setInstant(path: string): string {
            backgroundRoot.setBackground(path, true);
            return "ok";
        }

        function transition(fromPath: string, path: string): string {
            backgroundRoot.transitionBackground(fromPath, path, false, false);
            return "ok";
        }

        function themeTransition(fromPath: string, path: string, themeB64: string): string {
            backgroundRoot.transitionBackgroundWithTheme(fromPath, path, themeB64);
            return "ok";
        }

        function clear(): string {
            backgroundRoot.clearBackground();
            return "ok";
        }

        function current(): string {
            return backgroundRoot.currentBackground;
        }
    }

    // A reveal that never starts (the incoming image failed to load) must not
    // hold the palette hostage: their ~300 ms escape hatch.
    Timer {
        id: pendingThemeFallbackTimer
        interval: 300
        repeat: false
        onTriggered: backgroundRoot.applyPendingTheme()
    }

    NumberAnimation {
        id: revealAnimation
        target: backgroundRoot
        property: "revealProgress"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.InOutCubic
        onFinished: {
            if (backgroundRoot.incomingBackground) {
                backgroundRoot.displayedBackground = backgroundRoot.currentBackground || backgroundRoot.incomingBackground;
                backgroundRoot.finishingTransition = true;
            }
            backgroundRoot.revealProgress = 1;
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: wall

            required property var modelData

            screen: modelData
            visible: backgroundRoot.displayedBackground !== "" || backgroundRoot.incomingBackground !== ""
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: backgroundRoot.theme.surface1
            // Keep render updates enabled: upstream observed the background
            // layer losing its committed buffer while parked with updates
            // disabled, leaving a black desktop until restart. The wallpaper
            // is static, so correctness wins over a render-loop optimization.
            updatesEnabled: true
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "qshell-background"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Each screen readies its own mask and asks to start; the version
            // gate in startReveal makes the first ready screen start the
            // animation and the rest join it (their multi-monitor rule).
            property bool maskReady: false

            // Decode wallpapers at display resolution (logical size × dpr):
            // an unconstrained Image decodes the file at its native size,
            // which for a 4K source is ~33 MiB of RGBA per frame — and three
            // frames are up during a reveal.
            readonly property int decodeWidth: Math.max(1, Math.ceil(width * (screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1)))
            readonly property int decodeHeight: Math.max(1, Math.ceil(height * (screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1)))

            function maybeStartReveal() {
                if (!backgroundRoot.incomingBackground || backgroundRoot.revealProgress !== 0 || maskReady)
                    return;
                if (incomingFrame.status !== Image.Ready)
                    return;
                Qt.callLater(function () {
                    if (!backgroundRoot.incomingBackground || backgroundRoot.revealProgress !== 0 || maskReady)
                        return;
                    if (incomingFrame.status !== Image.Ready)
                        return;
                    backgroundRoot.startReveal(wall);
                });
            }

            // The settled image. Old and incoming stay up until this one has
            // actually decoded, so finishing a reveal never flashes the
            // window color.
            Image {
                id: base
                anchors.fill: parent
                source: backgroundRoot.fileUrl(backgroundRoot.displayedBackground)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: wall.decodeWidth
                sourceSize.height: wall.decodeHeight
                onStatusChanged: {
                    if (status === Image.Ready && backgroundRoot.finishingTransition) {
                        backgroundRoot.incomingBackground = "";
                        backgroundRoot.oldBackground = "";
                        backgroundRoot.finishingTransition = false;
                    }
                }
            }

            Image {
                id: oldFrame
                anchors.fill: parent
                source: backgroundRoot.fileUrl(backgroundRoot.oldBackground)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                sourceSize.width: wall.decodeWidth
                sourceSize.height: wall.decodeHeight
                visible: backgroundRoot.oldBackground !== "" && backgroundRoot.revealProgress < 1
                onStatusChanged: wall.maybeStartReveal()
            }

            Item {
                id: incomingLayer
                anchors.fill: parent
                visible: backgroundRoot.incomingBackground !== "" && incomingFrame.status === Image.Ready && (backgroundRoot.revealProgress >= 1 || wall.maskReady)
                layer.enabled: backgroundRoot.incomingBackground !== "" && backgroundRoot.revealProgress < 1
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: revealMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.02
                }

                Image {
                    id: incomingFrame
                    anchors.fill: parent
                    source: backgroundRoot.fileUrl(backgroundRoot.incomingBackground)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    sourceSize.width: wall.decodeWidth
                    sourceSize.height: wall.decodeHeight
                    onStatusChanged: wall.maybeStartReveal()
                }
            }

            // The wipe: a slanted band growing out from the center until it
            // covers the screen. Their slant and reach, verbatim.
            Item {
                id: revealMask
                anchors.fill: parent
                visible: false
                // The mask FBO is screen-sized; keep it allocated only for
                // the 420 ms the reveal actually samples it (same gate as
                // incomingLayer above).
                layer.enabled: backgroundRoot.incomingBackground !== "" && backgroundRoot.revealProgress < 1

                readonly property real slant: -0.18
                readonly property real centerTop: width / 2 - slant * height / 2
                readonly property real centerBottom: width / 2 + slant * height / 2
                readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
                readonly property real spread: reach * backgroundRoot.revealProgress

                Shape {
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "white"
                        strokeColor: "transparent"
                        startX: revealMask.centerTop - revealMask.spread
                        startY: 0
                        PathLine {
                            x: revealMask.centerTop + revealMask.spread
                            y: 0
                        }
                        PathLine {
                            x: revealMask.centerBottom + revealMask.spread
                            y: revealMask.height
                        }
                        PathLine {
                            x: revealMask.centerBottom - revealMask.spread
                            y: revealMask.height
                        }
                        PathLine {
                            x: revealMask.centerTop - revealMask.spread
                            y: 0
                        }
                    }
                }
            }

            Connections {
                target: backgroundRoot
                function onIncomingBackgroundChanged() {
                    wall.maskReady = false;
                    wall.maybeStartReveal();
                }
            }
        }
    }
}
