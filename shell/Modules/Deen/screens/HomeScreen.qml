import QtQuick
import QtQuick.Controls
import "../components"

// The page the hub opens on: what time it is in the day's worship, one ayah,
// one narration, and the four things worth doing next.
//
// NOTHING HERE IS CHOSEN BY A MODEL. The ayah and the narration are a pure
// function of the date — the same pair on every machine, from datasets that are
// already installed and already name their sources — and the prayer times are
// read from the calendar the bar's prayer widget already caches. This screen
// composes; it does not author, and it does not fetch.
//
// It is a landing page, so it is allowed to be quieter than the rooms it leads
// to: one loud number (the countdown), two cards, one row of doors.
FocusScope {
    id: screen

    required property var style
    // {today, tomorrow} — two rows of the aladhan calendar the bar caches.
    required property var prayer
    required property string prayerError
    // {date, ayah, surah, hadith} from `deen api daily`.
    required property var daily
    required property string dailyError
    required property int hifzDue

    signal reciteRequested
    signal memoriseRequested
    signal duasRequested(int chapter)
    signal hadithRequested
    signal readRequested(int surah)
    signal playRequested(string reference)
    signal openRequested(string url)

    // ------------------------------------------------------------- the clock
    // Minutes since midnight, re-read once a minute while this page is up. A
    // countdown that only moves when you switch screens is a picture of a
    // countdown.
    property int nowMinutes: 0

    function readClock() {
        const d = new Date();
        screen.nowMinutes = d.getHours() * 60 + d.getMinutes();
    }

    onVisibleChanged: if (screen.visible)
        screen.readClock()

    Component.onCompleted: screen.readClock()

    Timer {
        interval: 60000
        repeat: true
        running: screen.visible
        onTriggered: screen.readClock()
    }

    // The five prayers, and sunrise — which is not one of them but is when Fajr
    // ends, so a page about the day's shape has to show it.
    readonly property var prayerNames: ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    readonly property var dayNames: ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

    // "16:27 (+06)" → 987. The timezone suffix is aladhan's and is the same for
    // every row, so it carries no information the clock does not already have.
    function minutesOf(text) {
        const m = /^\s*(\d{1,2}):(\d{2})/.exec(String(text || ""));
        return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
    }

    function clockText(text) {
        const m = /^\s*(\d{1,2}:\d{2})/.exec(String(text || ""));
        return m ? m[1] : "—";
    }

    readonly property var timings: screen.prayer && screen.prayer.today ? screen.prayer.today.timings : null

    // The next prayer, and after Isha that is tomorrow's Fajr — taken from
    // TOMORROW'S row rather than today's, because a Fajr that moves a minute a
    // day would otherwise be a minute wrong every night.
    readonly property var next: {
        if (!screen.timings)
            return null;
        for (const name of screen.prayerNames) {
            const at = screen.minutesOf(screen.timings[name]);
            if (at >= 0 && at > screen.nowMinutes)
                return {
                    name: name,
                    at: at,
                    text: screen.clockText(screen.timings[name]),
                    tomorrow: false
                };
        }
        const t = screen.prayer && screen.prayer.tomorrow ? screen.prayer.tomorrow.timings : null;
        const fajr = t ? screen.minutesOf(t.Fajr) : -1;
        if (fajr < 0)
            return null;
        return {
            name: "Fajr",
            at: fajr + 1440,
            text: screen.clockText(t.Fajr),
            tomorrow: true
        };
    }

    readonly property string countdown: {
        if (!screen.next)
            return "";
        const left = screen.next.at - screen.nowMinutes;
        if (left <= 0)
            return "now";
        const h = Math.floor(left / 60);
        const m = left % 60;
        return h > 0 ? ("in " + h + "h " + m + "m") : ("in " + m + "m");
    }

    readonly property string hijri: {
        const d = screen.prayer && screen.prayer.today ? screen.prayer.today.date : null;
        if (!d || !d.hijri)
            return "";
        return d.hijri.day + " " + d.hijri.month.en + " " + d.hijri.year;
    }

    // Morning adhkar until Asr, evening after it — the book's own division, and
    // the one thing on this page that changes with the hour rather than the day.
    readonly property bool eveningNow: {
        const asr = screen.timings ? screen.minutesOf(screen.timings.Asr) : -1;
        return asr >= 0 && screen.nowMinutes >= asr;
    }

    Flickable {
        id: page

        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + screen.style.ui(40)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {}

        Column {
            id: column

            anchors.horizontalCenter: parent.horizontalCenter
            y: screen.style.ui(20)
            width: Math.min(page.width - screen.style.pagePad * 2, screen.style.ui(980))
            spacing: screen.style.ui(14)

            // ------------------------------------------------------ the hero
            // A COLUMN, not two anchored blocks. The first version anchored the
            // times to the bottom of a card sized only by the countdown above
            // them, so the six tiles were drawn straight through it.
            Rectangle {
                width: parent.width
                height: heroColumn.height + screen.style.ui(36)
                radius: screen.style.radiusLg
                color: screen.style.alpha(screen.style.accent, 0.07)
                border.width: screen.style.hairline
                border.color: screen.style.alpha(screen.style.accent, 0.22)

                Column {
                    id: heroColumn

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: screen.style.ui(18)
                    spacing: screen.style.ui(16)

                    Item {
                        width: parent.width
                        height: Math.max(nextBlock.height, dateBlock.height)

                        Column {
                            id: nextBlock

                            anchors.left: parent.left
                            anchors.top: parent.top
                            spacing: screen.style.ui(2)

                            Text {
                                textFormat: Text.PlainText
                                text: screen.next ? (screen.next.name.toUpperCase() + (screen.next.tomorrow ? " · TOMORROW" : "")) : "PRAYER TIMES"
                                color: screen.style.accent
                                font.family: screen.style.fontFamily
                                font.pixelSize: screen.style.type(11)
                                font.weight: Font.Bold
                                font.letterSpacing: 1.4
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: screen.next ? screen.countdown : (screen.prayerError !== "" ? "not cached yet" : "—")
                                color: screen.style.brightFg
                                font.family: screen.style.fontFamily
                                font.pixelSize: screen.style.type(28)
                                font.weight: Font.Bold
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: screen.next ? ("at " + screen.next.text) : (screen.prayerError !== "" ? screen.prayerError : "")
                                color: screen.style.muted
                                font.family: screen.style.fontFamily
                                font.pixelSize: screen.style.type(11)
                            }
                        }

                        Column {
                            id: dateBlock

                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: screen.style.ui(3)

                            Text {
                                textFormat: Text.PlainText
                                anchors.right: parent.right
                                text: screen.hijri
                                color: screen.style.alpha(screen.style.fg, 0.9)
                                font.family: screen.style.fontFamily
                                font.pixelSize: screen.style.type(13)
                                font.weight: Font.DemiBold
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.right: parent.right
                                text: Qt.formatDate(new Date(), "dddd, d MMMM yyyy")
                                color: screen.style.muted
                                font.family: screen.style.fontFamily
                                font.pixelSize: screen.style.type(11)
                            }
                        }
                    }

                    // The day's six times, the next one wearing the accent, so
                    // the page answers "where am I in the day" unread.
                    Row {
                        id: times

                        width: parent.width
                        spacing: screen.style.ui(8)
                        visible: screen.timings !== null

                        Repeater {
                            model: screen.dayNames

                            delegate: StatTile {
                                required property var modelData

                                width: (times.width - screen.style.ui(8) * 5) / 6
                                style: screen.style
                                label: modelData.toUpperCase()
                                value: screen.timings ? screen.clockText(screen.timings[modelData]) : "—"
                                valueColor: screen.next && !screen.next.tomorrow && screen.next.name === modelData ? screen.style.accent : screen.style.brightFg
                            }
                        }
                    }
                }
            }

            // --------------------------------------------- the day's two cards
            // Side by side where there is room. Below 760 px of content they
            // stack, because an ayah squeezed into half of a narrow window is
            // four words a line.
            Grid {
                id: cards

                width: parent.width
                columns: width >= screen.style.ui(760) ? 2 : 1
                columnSpacing: screen.style.ui(14)
                rowSpacing: screen.style.ui(14)

                readonly property real cellWidth: cards.columns === 2 ? (width - screen.style.ui(14)) / 2 : width

                // ------------------------------------------ ayah of the day
                Rectangle {
                    width: cards.cellWidth
                    height: ayahBody.height + screen.style.ui(30)
                    radius: screen.style.radiusMd
                    color: screen.style.alpha(screen.style.fg, 0.03)
                    border.width: screen.style.hairline
                    border.color: screen.style.alpha(screen.style.fg, 0.1)

                    Column {
                        id: ayahBody

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: screen.style.ui(15)
                        spacing: screen.style.ui(10)

                        Text {
                            textFormat: Text.PlainText
                            text: "AYAH OF THE DAY"
                            color: screen.style.muted
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(9)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            visible: screen.daily !== null
                            text: screen.daily ? screen.daily.ayah.ar : ""
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WordWrap
                            color: screen.style.fg
                            font.family: screen.style.arabicFamily
                            font.pixelSize: screen.style.type(22)
                            lineHeight: 1.15
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            visible: screen.daily !== null
                            text: screen.daily ? screen.daily.ayah.bn : ""
                            wrapMode: Text.WordWrap
                            color: screen.style.muted
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(12)
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            visible: screen.daily !== null
                            text: screen.daily ? screen.daily.ayah.en : ""
                            wrapMode: Text.WordWrap
                            color: screen.style.alpha(screen.style.muted, 0.72)
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(11)
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            visible: screen.daily === null
                            text: screen.dailyError !== "" ? screen.dailyError : "…"
                            wrapMode: Text.WordWrap
                            color: screen.style.muted
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(11)
                        }

                        Flow {
                            width: parent.width
                            spacing: screen.style.ui(6)
                            visible: screen.daily !== null

                            MetaChip {
                                style: screen.style
                                text: screen.daily ? (screen.daily.surah.n + " · " + screen.daily.surah.en + " " + screen.daily.ayah.a) : ""
                                dotColor: screen.style.accent
                            }

                            GlassButton {
                                style: screen.style
                                iconText: "󰐊"  // md-play
                                text: "Listen"
                                compact: true
                                onClicked: screen.playRequested(screen.daily.ayah.s + ":" + screen.daily.ayah.a)
                            }

                            GlassButton {
                                style: screen.style
                                iconText: "󰂺"  // md-book-open
                                text: "In context"
                                compact: true
                                onClicked: screen.readRequested(screen.daily.ayah.s)
                            }
                        }
                    }
                }

                // ---------------------------------------- hadith of the day
                Rectangle {
                    width: cards.cellWidth
                    height: hadithBody.height + screen.style.ui(30)
                    radius: screen.style.radiusMd
                    color: screen.style.alpha(screen.style.fg, 0.03)
                    border.width: screen.style.hairline
                    border.color: screen.style.alpha(screen.style.fg, 0.1)

                    Column {
                        id: hadithBody

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: screen.style.ui(15)
                        spacing: screen.style.ui(10)

                        Text {
                            textFormat: Text.PlainText
                            text: "HADITH OF THE DAY"
                            color: screen.style.muted
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(9)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            // Only ever from Bukhari or Muslim: a narration that
                            // arrives unasked should not be one you have to weigh
                            // a grading dispute about. Searching reaches the rest.
                            text: screen.daily && screen.daily.hadith ? screen.daily.hadith.hadith.en : (screen.dailyError !== "" ? screen.dailyError : "…")
                            wrapMode: Text.WordWrap
                            color: screen.style.alpha(screen.style.fg, 0.9)
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(12)
                            maximumLineCount: 9
                            elide: Text.ElideRight
                        }

                        Text {
                            textFormat: Text.PlainText
                            width: parent.width
                            visible: screen.daily !== null && screen.daily.hadith !== null && (screen.daily.hadith.hadith.bn || "") !== ""
                            text: screen.daily && screen.daily.hadith ? (screen.daily.hadith.hadith.bn || "") : ""
                            wrapMode: Text.WordWrap
                            color: screen.style.muted
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(11)
                            maximumLineCount: 6
                            elide: Text.ElideRight
                        }

                        Flow {
                            width: parent.width
                            spacing: screen.style.ui(6)
                            visible: screen.daily !== null && screen.daily.hadith !== null

                            MetaChip {
                                style: screen.style
                                text: screen.daily && screen.daily.hadith ? (screen.daily.hadith.collection.toUpperCase() + " " + screen.daily.hadith.hadith.n) : ""
                                dotColor: screen.style.accent
                            }

                            MetaChip {
                                style: screen.style
                                visible: screen.daily && screen.daily.hadith && (screen.daily.hadith.section || "") !== ""
                                text: screen.daily && screen.daily.hadith ? (screen.daily.hadith.section || "") : ""
                            }

                            GlassButton {
                                style: screen.style
                                iconText: "󰖟"  // md-web
                                text: "sunnah.com"
                                compact: true
                                onClicked: screen.openRequested(screen.daily.hadith.url)
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------- the four doors
            Flow {
                width: parent.width
                spacing: screen.style.ui(8)

                GlassButton {
                    style: screen.style
                    primary: true
                    iconText: "󰍬"  // md-microphone
                    text: "Recite an ayah"
                    onClicked: screen.reciteRequested()
                }

                GlassButton {
                    style: screen.style
                    iconText: "󰃀"  // md-bookmark-check
                    // The number is the whole point: an SRS you have to open to
                    // discover is one you stop opening.
                    text: screen.hifzDue > 0 ? ("Memorise · " + screen.hifzDue + " due") : "Memorise"
                    onClicked: screen.memoriseRequested()
                }

                GlassButton {
                    style: screen.style
                    iconText: "󱠧"  // md-mosque
                    text: screen.eveningNow ? "Evening adhkar" : "Morning adhkar"
                    onClicked: screen.duasRequested(27)
                }

                GlassButton {
                    style: screen.style
                    iconText: "⌕"
                    text: "Search the hadith"
                    onClicked: screen.hadithRequested()
                }
            }
        }
    }
}
