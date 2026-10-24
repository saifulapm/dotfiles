//@ pragma AppId deen
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "services" as Services
import "lib/deen.mjs" as D
import "lib/status.mjs" as Status
import "lib/voice.mjs" as L

// Deen, an App: its own qs process started by bin/dots-deen, a normal window in the shell's theme with five tabs, Read, Memorise, Duas, Hadith and Prayer; the process ends with its window.
ShellRoot {
    id: app

    // Process start to the window's first frame, set once.
    property var firstFrameMs: null
    property string tab: "read"
    readonly property string backend: Quickshell.env("DOTS_DEEN") || "deen"

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property string voice: look.voice
    readonly property string arabic: D.arabicFamily(Qt.fontFamilies())

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    // Runs `deen <args>` off the render loop and hands done its one JSON answer, or null when it failed.
    function api(args, done) {
        const call = caller.createObject(app, {
            command: [backend].concat(args)
        });
        call.done = done;
        call.running = true;
    }

    function pageOf(name) {
        return name === "read" ? readPage : name === "memorise" ? memorisePage : name === "duas" ? duasPage : name === "hadith" ? hadithPage : prayerPage;
    }

    Services.Theme {
        id: theme
    }

    Component {
        id: caller

        Process {
            property var done: null
            stdout: StdioCollector {
                id: answerOut
            }
            onExited: {
                const answer = D.answer(answerOut.text);
                if (done)
                    done(answer);
                destroy();
            }
        }
    }

    Process {
        id: ender
        // Its children first: qs dies on SIGTERM without ending them, which would leave a deen call or an mpv running on.
        command: ["sh", "-c", "for p in $(pgrep -P $PPID); do [ \"$p\" = $$ ] || kill -TERM \"$p\"; done; kill -TERM $PPID"]
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            app.quit();
        }
    }

    FileView {
        id: uptime
        path: "/proc/uptime"
        blockAllReads: true
    }

    FileView {
        id: selfStat
        path: "/proc/self/stat"
        blockLoading: true
    }

    // Read at call time; blockAllReads, or text() after reload() is the previous call's RSS.
    FileView {
        id: procStatus
        path: "/proc/self/status"
        blockAllReads: true
    }

    IpcHandler {
        target: "deen"

        function state(): string {
            procStatus.reload();
            return JSON.stringify({
                tab: app.tab,
                tabs: tabList.drawn(),
                heading: headingText.text,
                firstFrameMs: app.firstFrameMs,
                rssKiB: Status.rssKiB(procStatus.text()),
                voice: app.voice,
                arabic: app.arabic,
                read: readPage.state(),
                memorise: memorisePage.state(),
                duas: duasPage.state(),
                hadith: hadithPage.state(),
                prayer: prayerPage.state()
            });
        }
    }

    FloatingWindow {
        id: win

        readonly property bool plain: app.voice === "plain"
        readonly property bool bracket: app.voice === "bracket"
        readonly property bool caps: app.voice === "caps"
        readonly property string bodyFont: (bracket ? app.fonts.mono : app.fonts.ui) ?? ""

        title: "Deen"
        implicitWidth: 1200
        implicitHeight: 716
        color: app.c.surface ?? "white"

        Connections {
            target: win.contentItem.Window.window
            function onFrameSwapped() {
                if (app.firstFrameMs !== null)
                    return;
                uptime.reload();
                app.firstFrameMs = Status.processAgeMs(uptime.text(), selfStat.text());
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The App's name and the open section, as each board heads its window.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: win.plain ? 52 : implicitHeight
                Layout.leftMargin: win.plain ? 18 : 14
                Layout.rightMargin: win.plain ? 18 : 14
                Layout.topMargin: win.plain ? 0 : 12
                Layout.bottomMargin: win.plain ? 0 : 12
                spacing: win.plain ? 12 : 10

                Rectangle {
                    implicitWidth: nameText.implicitWidth + (win.plain ? 18 : 0)
                    implicitHeight: nameText.implicitHeight + (win.plain ? 6 : 0)
                    radius: 8
                    color: win.plain ? app.look.label.fill : "transparent"

                    Text {
                        id: nameText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: win.caps ? "DEEN" : "Deen"
                        color: (win.plain ? app.look.label.color : app.c.muted) ?? "gray"
                        font.family: win.bracket ? app.fonts.mono ?? "" : win.bodyFont
                        font.pixelSize: win.plain ? 12 : 10
                        font.weight: win.plain ? Font.Medium : Font.Normal
                        font.letterSpacing: win.plain ? 0 : 1.4
                    }
                }
                Text {
                    id: headingText
                    textFormat: Text.PlainText
                    text: D.tabName(app.tab)
                    color: app.c.ink ?? "black"
                    font.family: (win.caps ? app.fonts.display : win.bodyFont) ?? ""
                    font.pixelSize: win.caps ? 18 : win.plain ? 14 : 12
                    font.weight: win.caps ? Font.Normal : Font.Bold
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            Rule {
                Layout.fillWidth: true
                dashed: win.bracket
                color: (win.caps ? app.c.ink : app.c.line) ?? "gray"
            }

            // The five sections; Tab moves to the next.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: win.plain ? 48 : implicitHeight
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: win.plain ? 0 : 8
                Layout.bottomMargin: win.plain ? 0 : 8
                spacing: 6

                Repeater {
                    id: tabList
                    model: D.TABS

                    function drawn() {
                        const out = [];
                        for (let i = 0; i < count; i++) {
                            const t = itemAt(i);
                            if (t)
                                out.push(t.drawn());
                        }
                        return out;
                    }

                    Rectangle {
                        id: tabItem
                        required property string modelData
                        readonly property bool current: modelData === app.tab
                        function drawn() {
                            return {
                                text: tabText.text,
                                current: current
                            };
                        }
                        implicitWidth: tabText.implicitWidth + 28
                        implicitHeight: tabText.implicitHeight + 12
                        radius: win.plain ? 10 : 0
                        color: current ? (win.plain ? app.look.label.fill : win.bracket ? app.c.accent : app.c.ink) ?? "black" : "transparent"

                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: app.look.tabText(D.tabName(tabItem.modelData))
                            color: (tabItem.current ? (win.plain ? app.look.label.color : app.c.surface) : app.c.muted) ?? "gray"
                            font.family: win.bodyFont
                            font.pixelSize: win.plain ? 13 : win.bracket ? 11 : 10.5
                            font.weight: tabItem.current && !win.caps ? (win.plain ? Font.Medium : Font.Bold) : Font.Normal
                            font.letterSpacing: win.plain ? 0 : 1.4
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    textFormat: Text.PlainText
                    text: app.look.keys([["tab", "next section"]]).map(k => k.key + " " + k.word)[0]
                    color: app.c.muted ?? "gray"
                    font.family: win.bracket ? app.fonts.mono ?? "" : win.bodyFont
                    font.pixelSize: win.bracket ? 10 : 11
                    font.letterSpacing: win.bracket ? 1.4 : 0
                }
            }
            Rule {
                Layout.fillWidth: true
                dashed: win.bracket
                color: (win.caps ? app.c.ink : app.c.line) ?? "gray"
            }

            // Each page fills the rest and draws its own keys; Tab and Esc reach the frame from any page that leaves them.
            Item {
                id: pages
                Layout.fillWidth: true
                Layout.fillHeight: true
                focus: true

                Keys.onPressed: event => {
                    // Shift+Tab arrives as Backtab, or as Tab with Shift held, by keymap.
                    const back = event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier));
                    if (event.key === Qt.Key_Tab && !back) {
                        app.tab = D.tabAfter(app.tab, 1);
                        event.accepted = true;
                    } else if (back) {
                        app.tab = D.tabAfter(app.tab, -1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        app.quit();
                        event.accepted = true;
                    }
                }

                DeenRead {
                    id: readPage
                    anchors.fill: parent
                    visible: app.tab === "read"
                    focus: visible
                    deen: app
                }
                DeenMemorise {
                    id: memorisePage
                    anchors.fill: parent
                    visible: app.tab === "memorise"
                    focus: visible
                    deen: app
                }
                DeenDuas {
                    id: duasPage
                    anchors.fill: parent
                    visible: app.tab === "duas"
                    focus: visible
                    deen: app
                }
                DeenHadith {
                    id: hadithPage
                    anchors.fill: parent
                    visible: app.tab === "hadith"
                    focus: visible
                    deen: app
                }
                DeenPrayer {
                    id: prayerPage
                    anchors.fill: parent
                    visible: app.tab === "prayer"
                    focus: visible
                    deen: app
                }
            }
        }
    }

    // A one-pixel rule, solid, or dashed as Blueprint draws its rules.
    component Rule: Item {
        property bool dashed: false
        property color color: "black"
        implicitHeight: 1

        Rectangle {
            anchors.fill: parent
            visible: !parent.dashed
            color: parent.color
        }
        Dashed {
            anchors.fill: parent
            visible: parent.dashed
            color: parent.color
        }
    }
}
