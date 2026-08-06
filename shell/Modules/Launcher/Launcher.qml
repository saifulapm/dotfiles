import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// App launcher: fullscreen overlay layer with a centered panel. Click on the
// scrim or Escape dismisses; keyboard is grabbed (Exclusive) while open.
// LazyLoader-gated — nothing here exists until first summoned via IPC.
Scope {
    id: launcherRoot

    required property var theme

    property bool open: false
    property string query: ""
    property int selectedIndex: 0

    readonly property var entries: {
        const all = DesktopEntries.applications.values;
        const q = query.toLowerCase().trim();
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const e = all[i];
            if (e.noDisplay)
                continue;
            let score = 0;
            const name = e.name.toLowerCase();
            if (q === "") {
                score = 1;
            } else if (name.startsWith(q)) {
                score = 100;
            } else if (name.includes(q)) {
                score = 60;
            } else if ((e.genericName + " " + e.keywords.join(" ") + " " + e.comment).toLowerCase().includes(q)) {
                score = 30;
            }
            if (score > 0)
                out.push({
                    entry: e,
                    score: score
                });
        }
        out.sort((a, b) => b.score - a.score || a.entry.name.localeCompare(b.entry.name));
        return out.map(x => x.entry);
    }

    onQueryChanged: selectedIndex = 0

    function show() {
        // The loader stays active across open/close, so the TextInput and its
        // text survive too — clearing only `query` left stale text on screen
        // over an unfiltered list, and the next keystroke appended to it.
        searchField.text = "";
        query = "";
        selectedIndex = 0;
        open = true;
    }

    function hide() {
        open = false;
    }

    function toggle() {
        if (open)
            hide();
        else
            show();
    }

    function launch(entry) {
        if (!entry)
            return;
        entry.execute();
        hide();
    }

    function moveSelection(delta) {
        const n = entries.length;
        if (n === 0)
            return;
        selectedIndex = Math.min(n - 1, Math.max(0, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    PanelWindow {
        visible: launcherRoot.open
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qshell-launcher"
        WlrLayershell.keyboardFocus: launcherRoot.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: launcherRoot.theme.alpha(launcherRoot.theme.surface0, 0.5)

            MouseArea {
                anchors.fill: parent
                onClicked: launcherRoot.hide()
            }
        }

        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: launcherRoot.theme.space(140)
            height: launcherRoot.theme.space(110)
            radius: launcherRoot.theme.radius(1.5)
            color: launcherRoot.theme.surface1
            border.width: launcherRoot.theme.borderWidth
            border.color: launcherRoot.theme.surface3

            opacity: launcherRoot.open ? 1 : 0
            scale: launcherRoot.open ? 1 : 0.96
            Behavior on opacity {
                NumberAnimation {
                    duration: launcherRoot.theme.time(0.8)
                    easing.type: launcherRoot.theme.easing
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: launcherRoot.theme.time(0.8)
                    easing.type: launcherRoot.theme.easing
                }
            }

            MouseArea {
                // Swallow clicks so they don't fall through to the scrim.
                anchors.fill: parent
            }

            Column {
                anchors.fill: parent
                anchors.margins: launcherRoot.theme.space(4)
                spacing: launcherRoot.theme.space(3)

                Rectangle {
                    width: parent.width
                    height: launcherRoot.theme.space(10)
                    radius: launcherRoot.theme.radius(1)
                    color: launcherRoot.theme.surface2
                    border.width: launcherRoot.theme.borderWidth
                    border.color: searchField.activeFocus ? launcherRoot.theme.accent : launcherRoot.theme.surface3

                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: launcherRoot.theme.space(3)
                        anchors.rightMargin: launcherRoot.theme.space(3)
                        verticalAlignment: TextInput.AlignVCenter
                        color: launcherRoot.theme.textPrimary
                        font.family: launcherRoot.theme.fontUi
                        font.pixelSize: launcherRoot.theme.fontPx(1.1)
                        focus: true
                        onTextChanged: launcherRoot.query = text

                        Keys.onDownPressed: launcherRoot.moveSelection(1)
                        Keys.onUpPressed: launcherRoot.moveSelection(-1)
                        Keys.onReturnPressed: launcherRoot.launch(launcherRoot.entries[launcherRoot.selectedIndex])
                        Keys.onEscapePressed: launcherRoot.hide()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchField.text === ""
                            color: launcherRoot.theme.textMuted
                            font.family: launcherRoot.theme.fontUi
                            font.pixelSize: launcherRoot.theme.fontPx(1.1)
                            text: "search apps"
                        }
                    }
                }

                ListView {
                    id: list
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    model: launcherRoot.entries
                    currentIndex: launcherRoot.selectedIndex

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: list.width
                        height: launcherRoot.theme.space(10)
                        radius: launcherRoot.theme.radius(0.75)
                        color: index === launcherRoot.selectedIndex ? launcherRoot.theme.alpha(launcherRoot.theme.accent, 0.18) : (rowHover.hovered ? launcherRoot.theme.alpha(launcherRoot.theme.textPrimary, 0.06) : "transparent")

                        HoverHandler {
                            id: rowHover
                        }

                        TapHandler {
                            onTapped: launcherRoot.launch(modelData)
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: launcherRoot.theme.space(2)
                            anchors.rightMargin: launcherRoot.theme.space(2)
                            spacing: launcherRoot.theme.space(3)

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: launcherRoot.theme.space(7)
                                source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    color: launcherRoot.theme.textPrimary
                                    font.family: launcherRoot.theme.fontUi
                                    font.pixelSize: launcherRoot.theme.fontPx(1.0)
                                    text: modelData.name
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                    color: launcherRoot.theme.textMuted
                                    font.family: launcherRoot.theme.fontUi
                                    font.pixelSize: launcherRoot.theme.fontPx(0.833)
                                    text: modelData.genericName || modelData.comment || ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
