import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets

// Toast stack, top-right. Window exists only while this component is loaded
// (shell.qml gates the Loader on the first notification) and is visible only
// while there is something to show.
Scope {
    id: popupsRoot

    required property var theme
    required property var notifs

    PanelWindow {
        visible: popupsRoot.notifs.active.length > 0 && !popupsRoot.notifs.dnd
        anchors {
            top: true
            right: true
        }
        margins {
            top: popupsRoot.theme.space(2)
            right: popupsRoot.theme.space(2)
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 380
        implicitHeight: Math.max(1, toastColumn.implicitHeight)

        Column {
            id: toastColumn
            width: parent.width
            spacing: popupsRoot.theme.space(2)

            Repeater {
                model: popupsRoot.notifs.active

                delegate: Rectangle {
                    id: toast

                    required property var modelData
                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical

                    width: toastColumn.width
                    implicitHeight: content.implicitHeight + popupsRoot.theme.space(6)
                    radius: popupsRoot.theme.radius(1)
                    color: popupsRoot.theme.surface2
                    border.width: popupsRoot.theme.borderWidth
                    border.color: critical ? popupsRoot.theme.error : popupsRoot.theme.surface3

                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: popupsRoot.theme.time(1)
                            easing.type: popupsRoot.theme.easing
                        }
                    }

                    // Auto-expire: per-notification one-shot, paused on hover.
                    // Critical notifications never expire on their own.
                    Timer {
                        interval: toast.modelData.expireTimeout > 0 ? toast.modelData.expireTimeout : 5000
                        running: !toast.critical && !toastHover.hovered
                        onTriggered: toast.modelData.expire()
                    }

                    HoverHandler {
                        id: toastHover
                    }

                    TapHandler {
                        onTapped: toast.modelData.dismiss()
                    }

                    Row {
                        id: content
                        x: popupsRoot.theme.space(3)
                        y: popupsRoot.theme.space(3)
                        width: parent.width - popupsRoot.theme.space(6)
                        spacing: popupsRoot.theme.space(3)

                        IconImage {
                            visible: source.toString() !== ""
                            implicitSize: popupsRoot.theme.space(9)
                            source: {
                                const n = toast.modelData;
                                if (n.image !== "")
                                    return n.image;
                                if (n.appIcon !== "")
                                    return Quickshell.iconPath(n.appIcon, true);
                                return "";
                            }
                        }

                        Column {
                            width: parent.width - x
                            spacing: popupsRoot.theme.space(1)

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                color: popupsRoot.theme.textMuted
                                font.family: popupsRoot.theme.fontUi
                                font.pixelSize: popupsRoot.theme.fontPx(0.833)
                                text: toast.modelData.appName
                                visible: text !== ""
                            }

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                color: popupsRoot.theme.textPrimary
                                font.family: popupsRoot.theme.fontUi
                                font.pixelSize: popupsRoot.theme.fontPx(1.0)
                                font.weight: Font.DemiBold
                                text: toast.modelData.summary
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                maximumLineCount: 3
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                                color: popupsRoot.theme.textMuted
                                font.family: popupsRoot.theme.fontUi
                                font.pixelSize: popupsRoot.theme.fontPx(0.917)
                                textFormat: Text.PlainText
                                text: toast.modelData.body
                            }

                            Row {
                                visible: toast.modelData.actions.length > 0
                                spacing: popupsRoot.theme.space(2)

                                Repeater {
                                    model: toast.modelData.actions

                                    delegate: Rectangle {
                                        required property var modelData

                                        implicitWidth: actionLabel.implicitWidth + popupsRoot.theme.space(4)
                                        implicitHeight: actionLabel.implicitHeight + popupsRoot.theme.space(2)
                                        radius: popupsRoot.theme.radius(0.5)
                                        color: actionHover.hovered ? popupsRoot.theme.alpha(popupsRoot.theme.accent, 0.3) : popupsRoot.theme.alpha(popupsRoot.theme.accent, 0.15)

                                        HoverHandler {
                                            id: actionHover
                                        }

                                        TapHandler {
                                            onTapped: parent.modelData.invoke()
                                        }

                                        Text {
                                            id: actionLabel
                                            anchors.centerIn: parent
                                            color: popupsRoot.theme.accent
                                            font.family: popupsRoot.theme.fontUi
                                            font.pixelSize: popupsRoot.theme.fontPx(0.917)
                                            text: parent.modelData.text
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
