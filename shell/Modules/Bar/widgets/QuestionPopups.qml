import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../../components"
import "QuestionsModel.js" as Model

// The questions ringing on this machine: a stack of cards top-center under
// the bar (the notification toasts own the top-right corner), and the Reply
// modal. Each card names the project and the asking machine, shows the
// question and its options, and offers Reply...; the x only closes the card,
// so the question keeps waiting. Everything here reads QuestionsService,
// which loads this only while a card or the modal is up.
Scope {
    id: popupsRoot

    required property var theme
    required property var questions

    readonly property bool answering: popupsRoot.questions.answerProcess.running

    PanelWindow {
        id: popupWindow

        visible: popupsRoot.questions.popups.length > 0

        WlrLayershell.namespace: "qshell-questions"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Full-screen and fixed in size like the toast window, so adding a
        // card changes only the content; Normal keeps it clear of the bar.
        exclusionMode: ExclusionMode.Normal
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: popupColumn
        }

        Column {
            id: popupColumn

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: popupsRoot.theme.space(2)
            spacing: popupsRoot.theme.space(2)

            Repeater {
                model: popupsRoot.questions.popups

                delegate: Rectangle {
                    id: card

                    required property var modelData
                    readonly property string qid: modelData.id

                    width: popupsRoot.theme.space(95)
                    implicitHeight: cardColumn.implicitHeight + popupsRoot.theme.space(5)
                    radius: popupsRoot.theme.radius(1)
                    color: popupsRoot.theme.glass(popupsRoot.theme.surface1)
                    border.width: popupsRoot.theme.borderWidth
                    border.color: popupsRoot.theme.surface3

                    // A click anywhere off the buttons opens the modal.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popupsRoot.questions.openModal(card.qid)
                    }

                    Column {
                        id: cardColumn

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: popupsRoot.theme.space(2.5)
                        spacing: popupsRoot.theme.space(1.5)

                        Item {
                            width: parent.width
                            implicitHeight: closeButton.implicitHeight

                            StyledText {
                                theme: popupsRoot.theme
                                role: StyledText.Small
                                muted: true
                                anchors.left: parent.left
                                anchors.right: closeButton.left
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: card.modelData.project + " · " + card.modelData.machine
                            }

                            GlyphButton {
                                id: closeButton
                                theme: popupsRoot.theme
                                anchors.right: parent.right
                                glyph: "✕"
                                hint: "Close (the question keeps waiting)"
                                onActivated: popupsRoot.questions.dismiss(card.qid)
                            }
                        }

                        StyledText {
                            theme: popupsRoot.theme
                            role: StyledText.BodyLarge
                            width: parent.width
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            text: card.modelData.text
                        }

                        Flow {
                            width: parent.width
                            spacing: popupsRoot.theme.space(1.5)

                            Repeater {
                                model: card.modelData.options

                                PanelButton {
                                    required property string modelData
                                    theme: popupsRoot.theme
                                    label: modelData
                                    enabled: !popupsRoot.answering
                                    onClicked: popupsRoot.questions.answer(card.qid, modelData, "")
                                }
                            }

                            PanelButton {
                                theme: popupsRoot.theme
                                label: "Reply…"
                                onClicked: popupsRoot.questions.openModal(card.qid)
                            }
                        }

                        StyledText {
                            theme: popupsRoot.theme
                            role: StyledText.Small
                            width: parent.width
                            visible: popupsRoot.questions.errorId === card.qid && popupsRoot.questions.modalId === ""
                            wrapMode: Text.Wrap
                            color: popupsRoot.theme.error
                            text: popupsRoot.questions.lastError
                        }
                    }
                }
            }
        }
    }

    OverlaySurface {
        id: modal

        theme: popupsRoot.theme
        namespace: "qshell-question-reply"
        opened: popupsRoot.questions.modalQuestion !== null && !popupsRoot.questions.capturing
        cardWidth: popupsRoot.theme.space(120)
        cardHeight: modalColumn.implicitHeight + popupsRoot.theme.space(6)

        onDismissed: popupsRoot.questions.closeModal()
        onOpenedChanged: if (opened)
            Qt.callLater(() => replyInput.forceActiveFocus())

        // A fresh question starts with an empty box; the box itself outlives
        // the modal hiding for the file picker, so the draft does too.
        Connections {
            target: popupsRoot.questions
            function onModalIdChanged() {
                replyInput.text = "";
            }
            function onTextPasteWanted() {
                replyInput.paste();
            }
        }

        Column {
            id: modalColumn

            readonly property var question: popupsRoot.questions.modalQuestion || ({
                    id: "",
                    project: "",
                    machine: "",
                    text: ""
                })

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: popupsRoot.theme.space(3)
            spacing: popupsRoot.theme.space(2)

            StyledText {
                theme: popupsRoot.theme
                role: StyledText.Small
                muted: true
                width: parent.width
                elide: Text.ElideRight
                text: modalColumn.question.project + " · " + modalColumn.question.machine
            }

            StyledText {
                theme: popupsRoot.theme
                role: StyledText.BodyLarge
                width: parent.width
                wrapMode: Text.Wrap
                text: modalColumn.question.text
            }

            Rectangle {
                width: parent.width
                height: popupsRoot.theme.space(24)
                radius: popupsRoot.theme.radius(0.75)
                color: popupsRoot.theme.surface2
                border.width: popupsRoot.theme.borderWidth
                border.color: replyInput.activeFocus ? popupsRoot.theme.accent : popupsRoot.theme.surface3

                Flickable {
                    id: replyFlick

                    anchors.fill: parent
                    anchors.margins: popupsRoot.theme.space(2)
                    contentHeight: replyInput.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: replyInput

                        width: replyFlick.width
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        color: popupsRoot.theme.textPrimary
                        font.family: popupsRoot.theme.fontUi
                        font.pixelSize: popupsRoot.theme.fontPx(1.0)
                        selectByMouse: true
                        Keys.onEscapePressed: popupsRoot.questions.closeModal()
                        // The service reads the clipboard first: an image
                        // attaches, and text comes back here as a paste.
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                popupsRoot.questions.paste();
                                event.accepted = true;
                            }
                        }
                        onCursorRectangleChanged: {
                            if (cursorRectangle.y < replyFlick.contentY)
                                replyFlick.contentY = cursorRectangle.y;
                            else if (cursorRectangle.y + cursorRectangle.height > replyFlick.contentY + replyFlick.height)
                                replyFlick.contentY = cursorRectangle.y + cursorRectangle.height - replyFlick.height;
                        }

                        StyledText {
                            theme: popupsRoot.theme
                            role: StyledText.BodyLarge
                            muted: true
                            visible: replyInput.text === ""
                            text: "Your answer. Ctrl+V attaches images."
                        }
                    }
                }
            }

            // The attachments in the order mem gets them, each with its own
            // remove.
            Flow {
                width: parent.width
                visible: popupsRoot.questions.attachments.length > 0
                spacing: popupsRoot.theme.space(1.5)

                Repeater {
                    model: popupsRoot.questions.attachments

                    Rectangle {
                        id: tile

                        required property string modelData
                        required property int index

                        width: popupsRoot.theme.space(32)
                        height: popupsRoot.theme.space(18)
                        radius: popupsRoot.theme.radius(0.75)
                        color: popupsRoot.theme.surface2
                        border.width: popupsRoot.theme.borderWidth
                        border.color: popupsRoot.theme.surface3

                        Image {
                            anchors.fill: parent
                            anchors.margins: popupsRoot.theme.borderWidth
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            source: Model.fileUrl(tile.modelData)
                        }

                        GlyphButton {
                            theme: popupsRoot.theme
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: popupsRoot.theme.space(0.5)
                            glyph: "✕"
                            hint: "Remove this image"
                            onActivated: popupsRoot.questions.detach(tile.index)
                        }
                    }
                }
            }

            StyledText {
                theme: popupsRoot.theme
                role: StyledText.Small
                width: parent.width
                visible: popupsRoot.questions.errorId !== "" && popupsRoot.questions.errorId === popupsRoot.questions.modalId
                wrapMode: Text.Wrap
                color: popupsRoot.theme.error
                text: popupsRoot.questions.lastError
            }

            Item {
                width: parent.width
                implicitHeight: sendButton.implicitHeight

                Row {
                    anchors.right: parent.right
                    spacing: popupsRoot.theme.space(1.5)

                    PanelButton {
                        theme: popupsRoot.theme
                        label: "file"
                        enabled: !popupsRoot.answering
                        onClicked: popupsRoot.questions.pickFile()
                    }

                    PanelButton {
                        theme: popupsRoot.theme
                        label: "Cancel"
                        onClicked: popupsRoot.questions.closeModal()
                    }

                    PanelButton {
                        id: sendButton
                        theme: popupsRoot.theme
                        label: "Send"
                        selected: true
                        enabled: replyInput.text.trim() !== "" && !popupsRoot.answering
                        onClicked: popupsRoot.questions.answer(popupsRoot.questions.modalId, replyInput.text, popupsRoot.questions.attachments)
                    }
                }
            }
        }
    }
}
