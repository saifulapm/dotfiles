import Quickshell
import QtQuick
import QtQuick.Layouts
import "lib/deen.mjs" as D
import "lib/deen-duas.mjs" as U

// Deen's Duas: Hisn al-Muslim's chapters on the left, the open dua on the right with its Arabic, Bangla pronunciation, meaning and source.
FocusScope {
    id: page

    required property var deen

    readonly property var c: deen.c
    readonly property var fonts: deen.fonts
    readonly property var look: deen.look
    readonly property var tones: deen.tones
    readonly property string bodyFont: fonts.ui ?? ""

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
            page.noData = U.noData(answer);
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
                titleFamily: titleText.font.family,
                head: headText.text,
                ar: arText.text,
                arFamily: arText.font.family,
                arRtl: arText.horizontalAlignment === Text.AlignRight && arText.wrapMode !== Text.NoWrap,
                arLines: arText.lineCount,
                arSize: arText.font.pixelSize,
                pronLabel: pronLabel.text,
                pron: pronText.text,
                pronFamily: pronText.font.family,
                pronShown: pronText.visible,
                meaningLabel: meaningLabel.text,
                meaning: meaningText.text,
                meaningFamily: meaningText.font.family,
                sourceLabel: sourceLabel.text,
                source: sourceText.text,
                sourceFamily: sourceText.font.family,
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
                italic: pronText.font.italic
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

                // The search field: a filled pill.
                Rectangle {
                    id: fieldBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    height: 38
                    radius: 12
                    color: tones.field
                    border.width: 0

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
                        font.pixelSize: 13
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
                        anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: hintText.implicitWidth + 14
                        implicitHeight: hintText.implicitHeight + 4
                        radius: 6
                        color: "transparent"

                        Text {
                            id: hintText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: look.keyText("/")
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
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
                    font.pixelSize: 11
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
                                family: rowText.font.family,
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
                        radius: look.cursor.radius
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
                            font.family: deen.bengali
                            font.pixelSize: 14
                            font.weight: row.current ? Font.Medium : Font.Normal
                        }

                        Click {
                            name: "deen-duas-row:" + row.index
                            onTapped: {
                                page.cursor = row.index;
                                page.openAt(page.shown[row.index]);
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: divider
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                color: c.line ?? "gray"
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
                            font.family: deen.bengali
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                        Text {
                            id: headText
                            textFormat: Text.PlainText
                            text: page.openDua ? U.duaHead(page.openIndex + 1, page.openChapter.duas.length) : ""
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
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

                        // 110 and 141, instructions typed bare, have no pronunciation, so neither its label nor its line draws.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !!page.openDua && page.openDua.pron !== ""
                            spacing: 3

                            Text {
                                id: pronLabel
                                textFormat: Text.PlainText
                                text: look.tabText("Pronunciation")
                                color: c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 11
                            }
                            Text {
                                id: pronText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.openDua ? page.openDua.pron : ""
                                wrapMode: Text.Wrap
                                color: c.ink ?? "black"
                                font.family: deen.bengali
                                font.pixelSize: 16
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                id: meaningLabel
                                textFormat: Text.PlainText
                                // Where the book lacks the meaning, the label marks the English that stands in.
                                text: look.tabText(page.openDua && page.openDua.meaningEnglish ? "English" : "Meaning")
                                color: c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 11
                            }
                            Text {
                                id: meaningText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.openDua ? page.openDua.meaning : ""
                                wrapMode: Text.Wrap
                                color: c.ink ?? "black"
                                font.family: page.openDua && page.openDua.meaningEnglish ? page.bodyFont : deen.bengali
                                font.pixelSize: 16
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                id: sourceLabel
                                textFormat: Text.PlainText
                                text: look.tabText(page.openDua && page.openDua.sourceEnglish ? "English" : "Source")
                                color: c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 11
                            }
                            Text {
                                id: sourceText
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: page.openDua ? page.openDua.source : ""
                                wrapMode: Text.Wrap
                                color: c.ink ?? "black"
                                font.family: page.openDua && page.openDua.sourceEnglish ? page.bodyFont : deen.bengali
                                font.pixelSize: 14
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
