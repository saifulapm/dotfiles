import Quickshell
import QtQuick
import QtQuick.Layouts
import "lib/deen-prayer.mjs" as P

// Deen's Prayer: a day's five prayers on the left, the next one's countdown, the city and the method on the right.
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

    // DOTS_DEEN_NOW pins the minute for a check; without it the clock runs.
    readonly property var pinned: P.parseNow(Quickshell.env("DOTS_DEEN_NOW"))
    property var now: pinned ?? new Date()
    readonly property string todayKey: P.dayKey(now)
    property int offset: 0
    readonly property string shownKey: P.shiftDay(todayKey, offset)
    readonly property bool today: offset === 0

    property bool asked: false
    property bool failed: false
    property var day: null
    property var tomorrow: null
    property int serial: 0

    readonly property var coming: day && today ? P.next(day.times, now) : null
    readonly property bool afterIsha: day !== null && today && coming === null
    // After Isha the wait is to tomorrow's Fajr, once that day has been asked for.
    readonly property var upcoming: !day || !today ? null : coming ? coming : tomorrow ? {
        "name": "fajr",
        "time": tomorrow.fajr,
        "left": P.untilTomorrow(tomorrow.fajr, now)
    } : null

    function load(refresh) {
        const mine = ++serial;
        deen.api(["prayer", "--date", shownKey].concat(refresh ? ["--refresh"] : []), answer => {
            if (mine !== page.serial)
                return;
            const parsed = P.parsePrayer(answer);
            page.failed = parsed === null;
            page.day = parsed;
        });
    }

    function askTomorrow() {
        const key = P.shiftDay(todayKey, 1);
        if (tomorrow && tomorrow.date === key)
            return;
        deen.api(["prayer", "--date", key], answer => {
            const parsed = P.parsePrayer(answer);
            page.tomorrow = parsed ? {
                "date": key,
                "fajr": parsed.times.fajr
            } : null;
        });
    }

    function show(by) {
        offset = by;
        day = null;
        failed = false;
        load(false);
    }

    function state() {
        return {
            failed: failedText.visible ? failedText.text : "",
            retry: retryText.visible ? retryText.text : "",
            rows: Array.from({
                length: rowList.count
            }, (_, i) => rowList.itemAt(i)).filter(r => r).map(r => r.drawn()),
            label: labelText.visible ? labelText.text : "",
            headline: headlineText.visible ? headlineText.text : "",
            at: atText.visible ? atText.text : "",
            city: cityText.text,
            cityLines: cityText.lineCount,
            cityTruncated: cityText.truncated,
            date: dateText.text,
            asr: asrText.text,
            method: methodText.text,
            keys: keyStrip.drawn(),
            look: {
                headlineFont: headlineText.font.family,
                headlineSize: headlineText.font.pixelSize,
                dividerDashed: divider.dashed,
                ruleDashed: noteRule.dashed
            }
        };
    }

    onVisibleChanged: {
        if (!visible)
            return;
        now = pinned ?? new Date();
        if (!asked) {
            asked = true;
            load(false);
        }
    }
    onAfterIshaChanged: if (afterIsha)
        askTomorrow()

    // The countdown and the dimming follow the minute, so the page looks again every 15 s while it shows.
    Tick {
        interval: 15000
        repeat: true
        running: page.visible
        onTriggered: page.now = page.pinned ?? new Date()
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const t = event.text;
            const k = event.key;
            if (k === Qt.Key_Left || t === "h")
                page.show(page.offset - 1);
            else if (k === Qt.Key_Right || t === "l")
                page.show(page.offset + 1);
            else if (t === "t") {
                if (!page.today)
                    page.show(0);
            } else if (t === "r") {
                page.day = null;
                page.failed = false;
                page.load(true);
            } else
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

            ColumnLayout {
                Layout.preferredWidth: 472
                Layout.maximumWidth: 472
                Layout.fillHeight: true
                Layout.margins: 24
                spacing: 10

                Repeater {
                    id: rowList
                    model: page.day ? P.rows(page.day.times, page.now, page.today) : []

                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool dark: modelData.next
                        readonly property color ink: (dark ? c.surface : modelData.past ? c.muted : c.ink) ?? "gray"

                        function drawn() {
                            return {
                                name: nameText.text,
                                time: timeText.text,
                                tag: tagText.visible ? tagText.text : "",
                                next: modelData.next,
                                nameColor: String(nameText.color),
                                timeColor: String(timeText.color),
                                fill: String(color),
                                radius: radius,
                                border: border.width,
                                tagFill: tagBox.visible ? String(tagBox.color) : "",
                                tagRadius: tagBox.radius
                            };
                        }
                        Layout.fillWidth: true
                        implicitHeight: rowLine.implicitHeight + 32
                        radius: plain ? 14 : 0
                        color: dark ? ((bracket ? c.accent : c.ink) ?? "black") : plain ? "#F6F7F9" : "transparent"
                        border.width: plain || dark ? 0 : 1
                        border.color: (bracket ? c.line : c.ink) ?? "gray"

                        RowLayout {
                            id: rowLine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            spacing: 14

                            Text {
                                id: nameText
                                textFormat: Text.PlainText
                                text: row.modelData.name
                                color: row.ink
                                font.family: (row.dark && caps ? fonts.display : page.bodyFont) ?? ""
                                font.pixelSize: row.dark ? (caps ? 25 : plain ? 20 : 18) : (plain ? 18 : bracket ? 16 : 17)
                                font.weight: row.dark ? (caps ? Font.Normal : Font.Bold) : Font.Medium
                            }
                            Rectangle {
                                id: tagBox
                                visible: row.modelData.tag !== ""
                                implicitWidth: tagText.implicitWidth + (row.dark && !bracket ? (plain ? 16 : 12) : 0)
                                implicitHeight: tagText.implicitHeight + (row.dark && !bracket ? (plain ? 4 : 2) : 0)
                                radius: plain ? 8 : 0
                                color: row.dark && !bracket ? c.surface ?? "white" : "transparent"

                                Text {
                                    id: tagText
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: bracket && row.dark ? "[" + look.tabText(row.modelData.tag) + "]" : row.modelData.tag
                                    color: (row.dark ? (bracket ? c.surface : c.ink) : c.muted) ?? "gray"
                                    font.family: page.bodyFont
                                    font.pixelSize: plain ? 11 : 10
                                    font.weight: bracket && row.dark ? Font.Bold : plain && row.dark ? Font.Medium : Font.Normal
                                    font.letterSpacing: caps ? 1.4 : bracket ? 1.2 : 0
                                    font.capitalization: caps ? Font.AllUppercase : Font.MixedCase
                                }
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                            Text {
                                id: timeText
                                textFormat: Text.PlainText
                                text: row.modelData.time
                                color: row.ink
                                font.family: (bracket ? fonts.mono : page.bodyFont) ?? ""
                                font.pixelSize: row.dark ? 22 : 20
                                font.weight: row.dark && !caps ? Font.Bold : row.dark ? Font.Medium : Font.Normal
                            }
                        }
                    }
                }
                Item {
                    Layout.fillHeight: true
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
                    color: c.line ?? "gray"
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
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 30
                spacing: 22

                Text {
                    id: failedText
                    Layout.fillWidth: true
                    visible: page.failed
                    textFormat: Text.PlainText
                    text: "Prayer times need the network once a month"
                    wrapMode: Text.Wrap
                    color: c.ink ?? "black"
                    font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                    font.pixelSize: caps ? 25 : plain ? 20 : 16
                    font.weight: caps ? Font.Normal : Font.Bold
                }
                Text {
                    id: retryText
                    Layout.fillWidth: true
                    visible: page.failed
                    textFormat: Text.PlainText
                    text: look.keyText("r") + " " + look.tabText("to retry")
                    color: c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 12
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.day !== null
                    spacing: 22

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            id: labelText
                            textFormat: Text.PlainText
                            text: look.tabText(page.today ? "Next prayer" : "Not today")
                            visible: !page.today || page.upcoming !== null
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: plain ? 11 : 10
                            font.letterSpacing: plain ? 0 : 1.4
                        }
                        Text {
                            id: headlineText
                            Layout.fillWidth: true
                            visible: labelText.visible
                            textFormat: Text.PlainText
                            text: !page.today ? P.dayWord(P.dayDiff(page.todayKey, page.shownKey)) : page.upcoming ? P.nameOf(page.upcoming.name) + " in " + P.countdown(page.upcoming.left) : ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: c.ink ?? "black"
                            font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                            font.pixelSize: caps ? 50 : plain ? 38 : 36
                            font.weight: caps ? Font.Normal : Font.Bold
                            font.letterSpacing: plain ? -0.76 : 0
                        }
                        Text {
                            id: atText
                            visible: page.today && page.upcoming !== null
                            textFormat: Text.PlainText
                            text: page.upcoming ? page.upcoming.time + " · now " + P.clock(page.now) : ""
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 13
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            id: cityText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.day ? page.day.city : ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: plain ? 16 : bracket ? 14 : 15
                        }
                        Text {
                            id: dateText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.day ? P.dateLine(page.day.date, page.day.times.sunrise, bracket) : ""
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: bracket ? 0.72 : 0
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Item {
                            id: noteRule
                            property bool dashed: bracket
                            Layout.fillWidth: true
                            Layout.preferredHeight: 17

                            Rectangle {
                                width: parent.width
                                height: 1
                                visible: !noteRule.dashed
                                color: c.line ?? "gray"
                            }
                            Dashed {
                                width: parent.width
                                height: 1
                                visible: noteRule.dashed
                                color: c.line ?? "gray"
                            }
                        }
                        Text {
                            id: asrText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: bracket ? "ASR: HANAFI (SHADOW TWICE ITS LENGTH)" : "Asr: Hanafi (shadow twice its length)"
                            wrapMode: Text.Wrap
                            color: c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: bracket ? 0.72 : 0
                        }
                        Text {
                            id: methodText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: page.day ? (bracket ? P.methodLine(page.day.method, page.day.cached).toUpperCase() : P.methodLine(page.day.method, page.day.cached)) : ""
                            wrapMode: Text.Wrap
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 12
                            font.letterSpacing: bracket ? 0.72 : 0
                        }
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
            }
        }
        DeenKeys {
            id: keyStrip
            Layout.fillWidth: true
            deen: page.deen
            pairs: [["←/→", "other day"], ["t", "today"], ["r", "refresh"], ["tab", "section"], ["esc", "close"]]
        }
    }
}
