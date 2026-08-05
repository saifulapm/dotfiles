import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit

// Polkit authentication agent. The agent object is eager — it must be
// registered with polkit from startup or privileged prompts have no UI to
// land in. The dialog window loads only while a request is active.
Scope {
    id: polkitRoot

    required property var theme

    readonly property var agent: agentObj
    readonly property bool active: agentObj.isActive && agentObj.flow !== null

    function cancel() {
        if (active)
            agentObj.flow.cancelAuthenticationRequest();
    }

    PolkitAgent {
        id: agentObj
    }

    Loader {
        active: polkitRoot.active

        sourceComponent: PanelWindow {
            visible: true
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qshell-polkit"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                anchors.fill: parent
                color: polkitRoot.theme.alpha(polkitRoot.theme.surface0, 0.6)
            }

            Rectangle {
                anchors.centerIn: parent
                width: 420
                implicitHeight: dialogColumn.implicitHeight + polkitRoot.theme.space(8)
                radius: polkitRoot.theme.radius(1.5)
                color: polkitRoot.theme.surface1
                border.width: polkitRoot.theme.borderWidth
                border.color: polkitRoot.theme.surface3

                Column {
                    id: dialogColumn
                    x: polkitRoot.theme.space(4)
                    y: polkitRoot.theme.space(4)
                    width: parent.width - polkitRoot.theme.space(8)
                    spacing: polkitRoot.theme.space(3)

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: polkitRoot.theme.textPrimary
                        font.family: polkitRoot.theme.fontUi
                        font.pixelSize: polkitRoot.theme.fontPx(1.1)
                        font.weight: Font.DemiBold
                        text: polkitRoot.active ? polkitRoot.agent.flow.message : ""
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideMiddle
                        color: polkitRoot.theme.textMuted
                        font.family: polkitRoot.theme.fontMono
                        font.pixelSize: polkitRoot.theme.fontPx(0.833)
                        text: polkitRoot.active ? polkitRoot.agent.flow.actionId : ""
                    }

                    Rectangle {
                        width: parent.width
                        height: polkitRoot.theme.space(9)
                        radius: polkitRoot.theme.radius(1)
                        color: polkitRoot.theme.surface2
                        border.width: polkitRoot.theme.borderWidth
                        border.color: polkitRoot.active && polkitRoot.agent.flow.supplementaryIsError ? polkitRoot.theme.error : polkitRoot.theme.surface3

                        TextInput {
                            id: responseInput
                            anchors.fill: parent
                            anchors.leftMargin: polkitRoot.theme.space(3)
                            anchors.rightMargin: polkitRoot.theme.space(3)
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: polkitRoot.active && polkitRoot.agent.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"
                            color: polkitRoot.theme.textPrimary
                            font.family: polkitRoot.theme.fontMono
                            font.pixelSize: polkitRoot.theme.fontPx(1.0)
                            focus: true
                            enabled: polkitRoot.active && polkitRoot.agent.flow.isResponseRequired

                            onAccepted: {
                                if (polkitRoot.active)
                                    polkitRoot.agent.flow.submit(text);
                                text = "";
                            }

                            Keys.onEscapePressed: polkitRoot.cancel()

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: responseInput.text === ""
                                color: polkitRoot.theme.textMuted
                                font.family: polkitRoot.theme.fontUi
                                font.pixelSize: polkitRoot.theme.fontPx(1.0)
                                text: polkitRoot.active && polkitRoot.agent.flow.inputPrompt !== "" ? polkitRoot.agent.flow.inputPrompt : "password"
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        visible: text !== ""
                        color: polkitRoot.active && polkitRoot.agent.flow.supplementaryIsError ? polkitRoot.theme.error : polkitRoot.theme.textMuted
                        font.family: polkitRoot.theme.fontUi
                        font.pixelSize: polkitRoot.theme.fontPx(0.917)
                        text: polkitRoot.active ? polkitRoot.agent.flow.supplementaryMessage : ""
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: polkitRoot.theme.space(2)

                        Rectangle {
                            implicitWidth: cancelLabel.implicitWidth + polkitRoot.theme.space(6)
                            implicitHeight: polkitRoot.theme.space(8)
                            radius: polkitRoot.theme.radius(0.75)
                            color: cancelHover.hovered ? polkitRoot.theme.alpha(polkitRoot.theme.textPrimary, 0.1) : polkitRoot.theme.surface2

                            HoverHandler {
                                id: cancelHover
                            }
                            TapHandler {
                                onTapped: polkitRoot.cancel()
                            }

                            Text {
                                id: cancelLabel
                                anchors.centerIn: parent
                                color: polkitRoot.theme.textPrimary
                                font.family: polkitRoot.theme.fontUi
                                font.pixelSize: polkitRoot.theme.fontPx(0.917)
                                text: "Cancel"
                            }
                        }

                        Rectangle {
                            implicitWidth: authLabel.implicitWidth + polkitRoot.theme.space(6)
                            implicitHeight: polkitRoot.theme.space(8)
                            radius: polkitRoot.theme.radius(0.75)
                            color: authHover.hovered ? polkitRoot.theme.alpha(polkitRoot.theme.accent, 0.85) : polkitRoot.theme.accent

                            HoverHandler {
                                id: authHover
                            }
                            TapHandler {
                                onTapped: {
                                    if (polkitRoot.active)
                                        polkitRoot.agent.flow.submit(responseInput.text);
                                    responseInput.text = "";
                                }
                            }

                            Text {
                                id: authLabel
                                anchors.centerIn: parent
                                color: polkitRoot.theme.textOnAccent
                                font.family: polkitRoot.theme.fontUi
                                font.pixelSize: polkitRoot.theme.fontPx(0.917)
                                font.weight: Font.DemiBold
                                text: "Authenticate"
                            }
                        }
                    }
                }
            }
        }
    }
}
