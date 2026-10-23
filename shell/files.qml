//@ pragma AppId files
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "services" as Services
import "lib/files.mjs" as F
import "lib/status.mjs" as Status
import "lib/voice.mjs" as L

// Files, an App: its own qs process started by bin/dots-files, a normal window in the shell's theme; the process ends with its window.
ShellRoot {
    id: app

    readonly property string home: Quickshell.env("HOME")
    property string folder: home
    // Process start to the window's first frame, set once.
    property var firstFrameMs: null

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var look: L.listLook(theme.tokens)
    readonly property string voice: look.voice
    readonly property var head: F.headText(voice, home, folder)

    // qs has no quit, so a child ends its parent: the process must not outlive the window.
    function quit() {
        ender.running = true;
    }

    Services.Theme {
        id: theme
    }

    Process {
        id: ender
        command: ["sh", "-c", "kill -TERM $PPID"]
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
        target: "files"

        function state(): string {
            procStatus.reload();
            return JSON.stringify({
                folder: app.folder,
                title: win.title,
                head: app.head,
                voice: app.voice,
                firstFrameMs: app.firstFrameMs,
                rssKiB: Status.rssKiB(procStatus.text())
            });
        }
    }

    FloatingWindow {
        id: win

        title: app.head.folder
        implicitWidth: 1200
        implicitHeight: 716
        color: c.surface ?? "white"

        Connections {
            target: win.contentItem.Window.window
            function onFrameSwapped() {
                if (app.firstFrameMs !== null)
                    return;
                uptime.reload();
                app.firstFrameMs = Status.processAgeMs(uptime.text(), selfStat.text());
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    app.quit();
                    event.accepted = true;
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The header: Files' label, the folder in the display face, the key that opens it.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                spacing: 10

                Text {
                    id: labelText
                    textFormat: Text.PlainText
                    text: app.head.label
                    color: look.small.color
                    font.family: look.small.font
                    font.pixelSize: 10
                    font.letterSpacing: app.voice === "plain" ? 0 : 1.4
                }
                Text {
                    id: folderText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: app.head.folder
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: c.ink ?? "black"
                    font.family: app.voice === "bracket" ? fonts.mono ?? "" : fonts.display ?? ""
                    font.pixelSize: 18
                }
                Rectangle {
                    readonly property bool boxed: look.label.kind !== "header"
                    implicitWidth: chipText.implicitWidth + (boxed ? 14 : 0)
                    implicitHeight: chipText.implicitHeight + (boxed ? 4 : 0)
                    radius: look.label.kind === "pill" ? 8 : 0
                    color: boxed ? look.label.fill : "transparent"

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: app.head.chip
                        color: parent.boxed ? look.label.color : c.accent
                        font.family: look.small.font
                        font.pixelSize: 10
                        font.letterSpacing: app.voice === "plain" ? 0 : 1.4
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: look.rule.color
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
