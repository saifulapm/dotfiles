import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Theme switcher: centered overlay listing themes/ with color swatches.
// Arrow keys LIVE-PREVIEW the highlighted theme across the whole shell
// (Theme.preview swaps the full token map — colors, radius, motion);
// Enter applies it for real via bin/theme-set, Escape/scrim reverts.
// LazyLoader-gated — nothing here exists until first summoned via IPC.
Scope {
    id: switcherRoot

    required property var theme

    property bool open: false
    property int selectedIndex: 0
    property var themes: []
    property string appliedName: ""

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin"

    function show() {
        listProc.running = true;
        open = true;
    }

    function hide() {
        theme.endPreview();
        open = false;
    }

    function toggle() {
        if (open)
            hide();
        else
            show();
    }

    function select(index) {
        if (index < 0 || index >= themes.length)
            return;
        selectedIndex = index;
        theme.preview(themes[index].tokens);
        list.positionViewAtIndex(index, ListView.Contain);
    }

    function moveSelection(delta) {
        const n = themes.length;
        if (n === 0)
            return;
        select(Math.min(n - 1, Math.max(0, selectedIndex + delta)));
    }

    function apply(index) {
        const t = themes[index];
        if (!t)
            return;
        // Keep the preview up while theme-set runs — load() clears it the
        // moment the real theme lands, and niri's screen transition hides
        // the handover. Reverting here first would flash the old theme.
        Quickshell.execDetached([binDir + "/theme-set", t.name]);
        appliedName = t.name;
        open = false;
    }

    Process {
        id: listProc
        command: [switcherRoot.binDir + "/theme-list", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    switcherRoot.themes = JSON.parse(text);
                } catch (e) {
                    console.warn("ThemeSwitcher: theme-list parse failed:", e);
                    switcherRoot.themes = [];
                }
                let current = 0;
                for (let i = 0; i < switcherRoot.themes.length; i++) {
                    if (switcherRoot.themes[i].current)
                        current = i;
                }
                switcherRoot.selectedIndex = current;
                list.positionViewAtIndex(current, ListView.Center);
            }
        }
    }

    PanelWindow {
        visible: switcherRoot.open
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qshell-themes"
        WlrLayershell.keyboardFocus: switcherRoot.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: switcherRoot.theme.alpha(switcherRoot.theme.surface0, 0.5)

            MouseArea {
                anchors.fill: parent
                onClicked: switcherRoot.hide()
            }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: 420
            height: 520
            radius: switcherRoot.theme.radius(1.5)
            color: switcherRoot.theme.surface1
            border.width: switcherRoot.theme.borderWidth
            border.color: switcherRoot.theme.surface3

            opacity: switcherRoot.open ? 1 : 0
            scale: switcherRoot.open ? 1 : 0.96
            Behavior on opacity {
                NumberAnimation {
                    duration: switcherRoot.theme.time(0.8)
                    easing.type: switcherRoot.theme.easing
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: switcherRoot.theme.time(0.8)
                    easing.type: switcherRoot.theme.easing
                }
            }

            MouseArea {
                // Swallow clicks so they don't fall through to the scrim.
                anchors.fill: parent
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Down:
                    case Qt.Key_J:
                        switcherRoot.moveSelection(1);
                        break;
                    case Qt.Key_Up:
                    case Qt.Key_K:
                        switcherRoot.moveSelection(-1);
                        break;
                    case Qt.Key_Home:
                        switcherRoot.select(0);
                        break;
                    case Qt.Key_End:
                        switcherRoot.select(switcherRoot.themes.length - 1);
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        switcherRoot.apply(switcherRoot.selectedIndex);
                        break;
                    case Qt.Key_Escape:
                        switcherRoot.hide();
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: switcherRoot.theme.space(4)
                    spacing: switcherRoot.theme.space(3)

                    Text {
                        text: "Theme"
                        color: switcherRoot.theme.textPrimary
                        font.family: switcherRoot.theme.fontUi
                        font.pixelSize: switcherRoot.theme.fontPx(1.167)
                        font.weight: Font.DemiBold
                    }

                    ListView {
                        id: list
                        width: parent.width
                        height: parent.height - y
                        clip: true
                        model: switcherRoot.themes
                        currentIndex: switcherRoot.selectedIndex

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            readonly property var tk: modelData.tokens

                            width: list.width
                            height: switcherRoot.theme.space(11)
                            radius: switcherRoot.theme.radius(0.75)
                            color: index === switcherRoot.selectedIndex ? switcherRoot.theme.alpha(switcherRoot.theme.accent, 0.18) : (rowHover.hovered ? switcherRoot.theme.alpha(switcherRoot.theme.textPrimary, 0.06) : "transparent")

                            HoverHandler {
                                id: rowHover
                            }

                            TapHandler {
                                onTapped: {
                                    switcherRoot.select(index);
                                    switcherRoot.apply(index);
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: switcherRoot.theme.space(2)
                                anchors.rightMargin: switcherRoot.theme.space(3)
                                spacing: switcherRoot.theme.space(3)

                                // Swatch: the theme's own surface holding its
                                // accent ramp — a theme in miniature.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: switcherRoot.theme.space(19)
                                    height: switcherRoot.theme.space(7)
                                    radius: switcherRoot.theme.radius(0.5)
                                    color: tk["surface.1"] || "#000000"
                                    border.width: 1
                                    border.color: tk["surface.3"] || "#444444"

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: switcherRoot.theme.space(1.5)

                                        Repeater {
                                            model: [tk["accent.accent"], tk["accent.error"], tk["accent.warn"], tk["accent.ok"], tk["text.primary"]]

                                            Rectangle {
                                                required property var modelData
                                                width: switcherRoot.theme.space(2.5)
                                                height: width
                                                radius: width / 2
                                                color: modelData || "transparent"
                                            }
                                        }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.title
                                    color: switcherRoot.theme.textPrimary
                                    font.family: switcherRoot.theme.fontUi
                                    font.pixelSize: switcherRoot.theme.fontPx(1.0)
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: switcherRoot.theme.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: switcherRoot.theme.space(2)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.mode
                                    color: switcherRoot.theme.textMuted
                                    font.family: switcherRoot.theme.fontUi
                                    font.pixelSize: switcherRoot.theme.fontPx(0.833)
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.current || modelData.name === switcherRoot.appliedName
                                    width: switcherRoot.theme.space(1.5)
                                    height: width
                                    radius: width / 2
                                    color: switcherRoot.theme.accent
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
