import Quickshell
import QtQuick
import QtQuick.Layouts
import "lib/deen.mjs" as D
import "lib/deen-duas.mjs" as U

// Deen's Duas: Hisn al-Muslim's chapters on the left, the open dua on the right with its Arabic, transliteration, meaning and source.
FocusScope {
    id: page

    required property var deen

    readonly property var c: deen.c
    readonly property var fonts: deen.fonts
    readonly property var look: deen.look
    readonly property string voice: deen.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""

    property bool asked: false
    property bool failed: false
    // deen cannot read the duas, so the page says how to fetch them.
    property bool noData: false
    property var book: null
    readonly property var shown: book ? U.filter(book.chapters, field.text) : []
    property int cursor: 0
    property var openChapter: null
    property int openIndex: 0
    property bool copied: false
    readonly property var openDua: openChapter ? openChapter.duas[openIndex] : null

    // The list is asked for the first time the section shows.
    function load() {
        asked = true;
        deen.api(["dua", "list"], answer => {
            const parsed = U.parseList(answer);
            page.failed = parsed === null;
            page.noData = D.noData(answer);
            page.book = parsed;
        });
    }

    function openAt(chapter) {
        if (!chapter || chapter.duas.length === 0)
            return;
        openChapter = chapter;
        openIndex = 0;
        copied = false;
    }

    function move(by) {
        cursor = U.step(cursor, by, shown.length);
        list.positionViewAtIndex(cursor, ListView.Contain);
    }

    // The first match opens, the field closes and the cursor stays on that chapter in the whole list.
    function openFirst() {
        const first = shown[0];
        if (!first)
            return;
        openAt(first);
        closeField();
        cursor = book.chapters.indexOf(first);
        list.positionViewAtIndex(cursor, ListView.Contain);
    }

    function closeField() {
        field.text = "";
        keys.forceActiveFocus();
    }

    function copy() {
        if (!openDua)
            return;
        Quickshell.execDetached(["wl-copy", "--", U.copyText(openDua)]);
        copied = true;
    }

    function state() {
        return {
            failed: failedText.visible ? failedText.text : "",
            heading: headingText.visible ? headingText.text : "",
            field: {
                open: field.activeFocus,
                text: field.text,
                placeholder: placeholder.visible ? placeholder.text : "",
                hint: hintText.text
            },
            cursor: cursor,
            rows: Array.from({
                length: list.count
            }, (_, i) => list.itemAtIndex(i)).filter(r => r).map(r => r.drawn()),
            pane: {
                shown: pane.visible,
                title: titleText.text,
                head: headText.text,
                ar: arText.text,
                arFamily: arText.font.family,
                arRtl: arText.horizontalAlignment === Text.AlignRight && arText.wrapMode !== Text.NoWrap,
                arLines: arText.lineCount,
                arSize: arText.font.pixelSize,
                trLabel: trLabel.text,
                tr: trText.text,
                enLabel: enLabel.text,
                en: enText.text,
                sourceLabel: sourceLabel.text,
                source: sourceText.text,
                sourceLines: sourceText.lineCount,
                hint: emptyText.visible ? emptyText.text : ""
            },
            keys: keyStrip.drawn(),
            look: {
                headFont: headingText.font.family,
                titleFont: titleText.font.family,
                titleSize: titleText.font.pixelSize,
                fieldRadius: fieldBox.radius,
                fieldFill: fieldBox.color.a > 0 ? String(fieldBox.color) : "",
                fieldBorder: fieldBox.border.width,
                dividerDashed: divider.dashed,
                italic: trText.font.italic
            }
        };
    }

    onVisibleChanged: if (visible && !asked)
        load()

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const t = event.text;
            const k = event.key;
            if (t === "/")
                field.forceActiveFocus();
            else if (t === "j" || k === Qt.Key_Down)
                page.move(1);
            else if (t === "k" || k === Qt.Key_Up)
                page.move(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                page.openAt(page.shown[page.cursor]);
            else if (t === "n" && page.openChapter) {
                page.openIndex = U.nextDua(page.openIndex, page.openChapter.duas.length);
                page.copied = false;
            } else if (t === "y")
                page.copy();
            else
                return;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                Layout.preferredWidth: 300
                Layout.fillHeight: true

                // The search field: Paper's and Blueprint's ruled box, Artboard's filled pill.
                Rectangle {
                    id: fieldBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    height: plain ? 38 : 36
                    radius: plain ? 12 : 0
                    color: plain ? "#F6F7F9" : "transparent"
                    border.width: plain ? 0 : 1
                    border.color: (bracket ? c.line : c.muted) ?? "gray"

                    TextInput {
                        id: field
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: hint.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        color: c.ink ?? "black"
                        selectionColor: c.accent ?? "red"
                        selectedTextColor: c.surface ?? "white"
                        font.family: page.bodyFont
                        font.pixelSize: plain ? 13 : 12
                        onTextChanged: {
                            page.cursor = 0;
                            list.positionViewAtBeginning();
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                page.openFirst();
                            else if (event.key === Qt.Key_Escape)
                                page.closeField();
                            else
                                return;
                            event.accepted = true;
                        }

                        Text {
                            id: placeholder
                            anchors.fill: parent
                            visible: field.text === ""
                            textFormat: Text.PlainText
                            text: "Search duas"
                            color: c.muted ?? "gray"
                            font: field.font
                        }
                    }
                    Rectangle {
                        id: hint
                        anchors.right: parent.right
                        anchors.rightMargin: plain ? 9 : 12
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: hintText.implicitWidth + (plain ? 14 : 0)
                        implicitHeight: hintText.implicitHeight + (plain ? 4 : 0)
                        radius: 6
                        color: plain ? "white" : "transparent"

                        Text {
                            id: hintText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: look.keyText("/")
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: bracket ? 10 : 11
                            font.weight: plain ? Font.Medium : Font.Normal
                            font.letterSpacing: bracket ? 1.4 : 0
                        }
                    }
                }
                Text {
                    id: headingText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: fieldBox.bottom
                    anchors.margins: 10
                    anchors.topMargin: 6
                    anchors.leftMargin: 22
                    visible: page.book !== null
                    textFormat: Text.PlainText
                    text: page.book ? look.tabText(U.heading(page.book.count)) : ""
                    color: c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: plain ? 11 : 10
                    font.letterSpacing: plain ? 0 : 1.4
                }
                ListView {
                    id: list
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: headingText.bottom
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    anchors.topMargin: 8
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: page.shown

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool current: index === page.cursor

                        function drawn() {
                            const top = mapToItem(list, 0, 0).y;
                            return {
                                text: rowText.text,
                                current: current,
                                truncated: rowText.truncated,
                                lines: rowText.lineCount,
                                fill: current ? String(color) : "",
                                textColor: String(rowText.color),
                                radius: radius,
                                weight: rowText.font.weight,
                                inView: top >= 0 && top + height <= list.height
                            };
                        }
                        width: ListView.view.width
                        height: 34
                        radius: plain ? look.cursor.radius : 0
                        color: current ? look.cursor.fill : "transparent"

                        Text {
                            id: rowText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: row.modelData.name
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: (row.current ? look.cursor.text : c.ink) ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: plain ? 14 : 13
                            font.weight: row.current && !bracket ? Font.Medium : Font.Normal
                        }
                    }
                }
            }
            Item {
                id: divider
                property bool dashed: bracket
                Layout.preferredWidth: 1
                Layout.fillHeight: true

                Rectangle {
                    anchors.fill: parent
                    visible: !divider.dashed
                    color: (caps ? c.ink : c.line) ?? "gray"
                }
                Dashed {
                    visible: divider.dashed
                    x: 1
                    width: divider.height
                    height: 1
                    rotation: 90
                    transformOrigin: Item.TopLeft
                    color: c.line ?? "gray"
                }
            }
            Flickable {
                id: pane
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: paneColumn.implicitHeight + 52
                boundsBehavior: Flickable.StopAtBounds
                visible: !page.failed

                ColumnLayout {
                    id: paneColumn
                    x: 34
                    y: 26
                    width: pane.width - 68
                    spacing: 22

                    RowLayout {
                        Layout.fillWidth: true
                        visible: page.openDua !== null
                        spacing: 12

                        Text {
                            id: titleText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.openChapter ? page.openChapter.name : ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: c.ink ?? "black"
                            font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                            font.pixelSize: caps ? 25 : plain ? 20 : 18
                            font.weight: caps ? Font.Normal : Font.Bold
                        }
                        Text {
                            id: headText
                            textFormat: Text.PlainText
                            text: page.openDua ? U.duaHead(page.openIndex + 1, page.openChapter.duas.length, bracket) : ""
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: bracket ? 0.72 : 0
                        }
                    }
                    Text {
                        id: arText
                        Layout.fillWidth: true
                        visible: page.openDua !== null
                        textFormat: Text.PlainText
                        text: page.openDua ? page.openDua.ar : ""
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignRight
                        lineHeight: 1.6
                        lineHeightMode: Text.ProportionalHeight
                        color: c.ink ?? "black"
                        font.family: deen.arabic
                        font.pixelSize: U.arabicSize(text)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: page.openDua !== null
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                id: trLabel
                                textFormat: Text.PlainText
                                text: look.tabText("Transliteration")
                                color: c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: plain ? 11 : 10
                                font.letterSpacing: plain ? 0 : 1.4
                            }
                            Text {
                                id: trText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.openDua ? page.openDua.tr : ""
                                wrapMode: Text.Wrap
                                color: c.ink ?? "black"
                                font.family: page.bodyFont
                                font.italic: true
                                font.pixelSize: plain ? 16 : bracket ? 14 : 15
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                id: enLabel
                                textFormat: Text.PlainText
                                text: look.tabText("Meaning")
                                color: c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: plain ? 11 : 10
                                font.letterSpacing: plain ? 0 : 1.4
                            }
                            Text {
                                id: enText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.openDua ? page.openDua.en : ""
                                wrapMode: Text.Wrap
                                color: c.ink ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: plain ? 16 : bracket ? 14 : 15
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                id: sourceLabel
                                textFormat: Text.PlainText
                                text: look.tabText("Source")
                                color: c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: plain ? 11 : 10
                                font.letterSpacing: plain ? 0 : 1.4
                            }
                            Text {
                                id: sourceText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.openDua ? U.sourceLine(page.openDua) : ""
                                wrapMode: Text.Wrap
                                color: c.ink ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: plain ? 14 : 13
                            }
                        }
                    }
                    Text {
                        id: emptyText
                        Layout.fillWidth: true
                        visible: page.openDua === null && page.book !== null
                        textFormat: Text.PlainText
                        text: "Enter opens a chapter"
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 13
                    }
                }
            }
        }
        DeenKeys {
            id: keyStrip
            Layout.fillWidth: true
            deen: page.deen
            pairs: page.failed ? [["tab", "section"], ["esc", "close"]] : field.activeFocus ? [["↵", "open"], ["esc", "clear"], ["tab", "section"]] : [["j/k", "chapter"], ["↵", "open"], ["n", "next dua"], ["y", page.copied ? "copied" : "copy"], ["/", "search"], ["tab", "section"], ["esc", "close"]]
        }
    }

    // Without the book there is nothing to list, so the whole page says so.
    Text {
        id: failedText
        anchors.centerIn: parent
        visible: page.failed
        textFormat: Text.PlainText
        text: page.noData ? D.NO_DATA : "Hisn al-Muslim is not on this machine yet"
        color: c.muted ?? "gray"
        font.family: page.bodyFont
        font.pixelSize: 14
    }
}
