import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "." as Root
import "lib/control.mjs" as Lib
import "lib/control-home.mjs" as Home
import "lib/control-system.mjs" as Sys
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T
import "lib/idle.mjs" as Idle

// Control drawn inside the island on its fill (board 4): Home's clock and tiles, and a page per section behind its tile. A section is an Item with: required property var theme; property int selected; readonly property var rows ([{title, detail}]); optional readonly property bool levels (true when every row has a volume or brightness that h/l steps); function key(event): bool for keys other than j/k, Up/Down and Esc, or for every key while its optional typing is true; function state(): object.
Item {
    id: control

    required property var theme
    required property var notifs
    required property var sync
    // The Desk's clock service, null until the Desk loads.
    property var clock: null
    // The island reports this as its surface while Control is shown.
    readonly property string name: "control"
    // The island grows to this width for Control, as board 4 draws it.
    readonly property int wantWidth: 640
    readonly property bool busy: false
    property bool shown: false
    // True once the island has come to rest on Control; the surfaces' window sets it.
    property bool settled: false
    // The shell makes Control in its warm-up, before anyone opens it; the sections that probe the system wait for this.
    property bool opened: false
    // The section whose page shows, or "" on Home.
    property string page: ""
    // Control's big clock, which the island's resting clock glides into; hidden while the glide draws it.
    readonly property Item clockItem: bigClock
    property bool clockHidden: false
    // The tile Home's keys act on.
    property string cursor: "wifi"
    property real wheelRest: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    // A pair that failed, said on the Bluetooth page, where the island's own toast cannot show while Control holds it; cleared by the next request or leaving the page.
    property string pairNote: ""
    Connections {
        target: Root.Pairing
        function onFailed(device) {
            control.pairNote = "Pairing failed: " + device;
        }
        function onCurrentChanged() {
            if (Root.Pairing.current)
                control.pairNote = "";
        }
    }
    onPageChanged: pairNote = ""

    // Enter on Record screen and on Calendar hand off to the Recorder and to the island's calendar card.
    signal recordWanted
    signal calendarWanted

    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, and the tones lifted to read on it.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    readonly property var sections: [audio, wifi, bluetooth, power, display, route]
    readonly property int current: Math.max(0, Lib.SECTIONS.indexOf(page))
    readonly property var section: sections[current]
    readonly property var rows: page === "" ? [] : section.rows
    readonly property var now: clock ? clock.now : new Date()

    // What Home's tiles read, from the sections that already watch each service.
    readonly property var wifiNet: wifi.networks.find(n => n.connected) ?? null
    readonly property var btDevice: bluetooth.devices.find(d => d.connected) ?? null
    readonly property var sink: audio.defaultSink
    readonly property var tiles: Home.tiles({
        wifi: wifiNet ? { name: wifiNet.name, signal: Math.round(wifiNet.signalStrength * 100) } : null,
        wifiOn: wifi.wifi.length > 0,
        bt: btDevice ? { name: btDevice.name, battery: btDevice.batteryAvailable ? Math.round(btDevice.battery * 100) : null } : null,
        btOn: bluetooth.on,
        sink: sink?.audio ? { name: sink.description || sink.name, volume: sink.audio.volume, muted: sink.audio.muted } : null,
        panel: display.panels.length ? display.panels[0].percent : null,
        recording: Root.State.recordingSince > 0,
        recordingMs: Root.State.recordingSince > 0 ? recordNow - Root.State.recordingSince : 0,
        battery: power.hasBattery ? { percent: Math.round(power.battery.percentage * 100), profile: power.profileName, left: Home.leftText(power.battery.timeToEmpty) } : null,
        units: control.sync ? control.sync.units : {},
        dnd: control.notifs.dnd,
        awakeUntil: Root.State.awakeUntil,
        now: now.getTime()
    })

    // Record screen counts the seconds of a running recording while Control shows; the clock's minute tick is too coarse.
    property real recordNow: Date.now()
    Root.Tick {
        interval: 1000
        repeat: true
        running: control.shown && Root.State.recordingSince > 0
        onTriggered: control.recordNow = Date.now()
    }

    implicitHeight: (page === "" ? Home.height() : pageColumn.implicitHeight) + 32

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        opened = true;
        recordNow = Date.now();
        page = "";
        cursor = "wifi";
        shown = true;
        forceActiveFocus();
    }

    // Opens a section's page by name, as the power key opens Power.
    function show(name) {
        if (Lib.SECTIONS.indexOf(name) >= 0)
            page = name;
    }

    function close() {
        shown = false;
        // Only the secret clears as Control closes; the rest is drawn until the close stops drawing.
        wifi.psk = "";
        bluetooth.stopScan();
    }

    // Esc on a page goes back to the tile that opened it; on Home it closes Control.
    function back() {
        if (page === "") {
            close();
            return;
        }
        cursor = Home.TILE_OF[page] ?? cursor;
        // A scan runs only while its page shows.
        if (page === "bluetooth")
            bluetooth.stopScan();
        page = "";
    }

    // A click outside closes an open field first, and Control only once nothing is open inside (2TM85BFB).
    function stepBack() {
        if (page !== "" && section.typing && section.closeLine)
            section.closeLine();
        else if (!(page !== "" && section.cancel && section.cancel()))
            close();
    }

    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        section.selected = Math.max(0, Math.min(rows.length - 1, section.selected + by));
    }

    // Enter on a tile opens its page; the switches flip, Lock locks, and Record screen and Calendar close Control for what they open.
    function act(id) {
        cursor = id;
        if (Home.PAGES[id]) {
            page = Home.PAGES[id];
        } else if (id === "dnd") {
            notifs.setDnd(!notifs.dnd);
        } else if (id === "awake") {
            // The switch turns Stay awake off, or on for its first step, 30 minutes; Power's page holds the longer steps.
            Root.State.awakeUntil = Root.State.awakeUntil > Date.now() ? 0 : Idle.nextAwake(Date.now(), 0);
        } else if (id === "lock") {
            close();
            Quickshell.execDetached(Sys.actionCommand("lock"));
        } else if (id === "record") {
            close();
            recordWanted();
        } else if (id === "calendar") {
            close();
            calendarWanted();
        }
    }

    // - and = on Sound step the default output 5%, and on Brightness the built-in panel one step; dir is -1 or 1.
    function step(id, dir) {
        if (id === "sound" && sink?.audio)
            sink.audio.volume = Lib.stepVolume(sink.audio.volume, dir);
        else if (id === "brightness" && display.panels.length) {
            display.selected = 0;
            display.key({ key: dir > 0 ? Qt.Key_L : Qt.Key_H, modifiers: 0, text: "" });
        }
    }

    // A wheel turn over a slider steps it once per whole notch; wheelRest holds a touchpad's part of one.
    function turn(id, angle) {
        const t = Lib.wheelSteps(wheelRest, angle);
        wheelRest = t.rest;
        for (let i = 0; i < Math.abs(t.steps); i++)
            step(id, t.steps > 0 ? 1 : -1);
    }

    // A click on a page's row selects it and hands its section the Enter its key() handles; an open password line takes only keys.
    function runRow(index) {
        if (section.typing)
            return;
        section.selected = index;
        section.key({ key: Qt.Key_Return, modifiers: 0, text: "" });
    }

    // A click on a part of the Power page selects it and hands Power the Enter its key() handles.
    function runPower(id) {
        const i = power.items.findIndex(it => it.id === id);
        if (i < 0)
            return;
        if (power.selected !== i)
            power.selected = i;
        power.key({ key: Qt.Key_Return, modifiers: 0, text: "" });
    }

    // A wheel turn over a slider row selects it and takes one h or l step its key() handles for each whole notch.
    function turnRow(index, angle) {
        if (!section.levels || section.typing)
            return;
        const t = Lib.wheelSteps(wheelRest, angle);
        wheelRest = t.rest;
        section.selected = index;
        for (let i = 0; i < Math.abs(t.steps); i++)
            section.key({ key: t.steps > 0 ? Qt.Key_L : Qt.Key_H, modifiers: 0, text: "" });
    }

    // An item's box in window coordinates.
    function box(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height };
    }

    function state() {
        const cur = page === "" ? null : rowRepeater.itemAt(section.selected);
        return JSON.stringify(Object.assign({
            open: shown,
            page: page || "home",
            section: page || "home",
            sections: Lib.SECTIONS,
            cursor: cursor,
            tiles: tiles.map((t, i) => {
                const item = tileRepeater.itemAt(i);
                return Object.assign({}, t, item ? { fill: String(item.color), box: box(item), focused: item.focused, content: item.content ? box(item.content) : null } : {});
            }),
            selected: page === "" ? -1 : section.selected,
            rows: rows.map(r => r.title),
            details: rows.map(r => r.detail),
            // The caption over each row that starts a group, as the Sound page draws OUTPUT, PLAYING and INPUT.
            caps: rows.map(r => r.cap ?? ""),
            tones: rows.map(r => r.tone ?? ""),
            detailLines: Array.from({ length: rowRepeater.count }, (_, i) => rowRepeater.itemAt(i).detailLines),
            scanning: scanRow.visible,
            pairNote: pairCard.visible ? pairText.text : null,
            // The Power page as drawn: the profile and Stay awake segments lit, and each action's label.
            power: page === "power" && powerLoader.item ? powerLoader.item.drawn : null,
            // A page's field takes every key.
            typing: page !== "" && !!section.typing,
            detailsDrawn: Array.from({ length: rowRepeater.count }, (_, i) => rowRepeater.itemAt(i).drawnDetail),
            // The open password field as drawn, in the asking network's row.
            field: Array.from({ length: rowRepeater.count }, (_, i) => rowRepeater.itemAt(i).fieldLook).find(f => f) ?? null,
            rowHeights: Array.from({ length: rowRepeater.count }, (_, i) => rowRepeater.itemAt(i).height),
            cursorFill: cur ? String(cur.color) : null,
            cursorBox: cur ? box(cur.box) : null,
            // The glyph each slider row's pill draws; the page rows draw none.
            pillGlyphs: Array.from({ length: rowRepeater.count }, (_, i) => rowRepeater.itemAt(i).pillGlyph),
            cursorName: cur ? Object.assign(box(cur.nameItem), { truncated: cur.nameItem.truncated }) : null,
            clock: { text: bigClock.text, px: bigClock.font.pixelSize, box: box(bigClock) },
            date: dateText.text,
            openMs: openMs,
            opens: opens,
            settled: settled,
            drawing: shown,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: control.Window.active
        }, page === "" ? {} : section.state()));
    }

    Component.onCompleted: Root.State.loaded.push("control")

    Keys.onPressed: event => {
        const k = event.key;
        // A held Enter acts once: its repeats never confirm Reboot, Log out or Power off, nor flip a switch back.
        if (event.isAutoRepeat && (k === Qt.Key_Return || k === Qt.Key_Enter)) {
            event.accepted = true;
            return;
        }
        // A section's open password line takes every key first, so j, k and - type and Esc closes only the line.
        if (page !== "" && section.typing) {
            section.key(event);
            event.accepted = true;
            return;
        }
        // Esc puts a confirming button back before it leaves the page.
        if (k === Qt.Key_Escape && !(page !== "" && section.cancel && section.cancel()))
            back();
        else if (k === Qt.Key_Escape)
            return;
        else if (page !== "") {
            if (k === Qt.Key_J || k === Qt.Key_Down)
                move(1);
            else if (k === Qt.Key_K || k === Qt.Key_Up)
                move(-1);
            else if (k === Qt.Key_Equal || k === Qt.Key_Minus)
                // - and = step the focused slider as h and l always have.
                section.key({ key: k === Qt.Key_Equal ? Qt.Key_L : Qt.Key_H, modifiers: 0, text: "" });
            else if (!section.key(event))
                return;
        } else {
            const dx = k === Qt.Key_H || k === Qt.Key_Left ? -1 : k === Qt.Key_L || k === Qt.Key_Right ? 1 : 0;
            const dy = k === Qt.Key_K || k === Qt.Key_Up ? -1 : k === Qt.Key_J || k === Qt.Key_Down ? 1 : 0;
            if (dx || dy)
                cursor = Home.move(cursor, dx, dy);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                act(cursor);
            else if (k === Qt.Key_Equal || k === Qt.Key_Minus)
                step(cursor, k === Qt.Key_Equal ? 1 : -1);
            else
                return;
        }
        event.accepted = true;
    }

    // The sections hold each page's rows and keys; each is visible while its page shows, as pw-dump and the scans wait for that, but draws nothing here.
    Item {
        width: 0
        height: 0
        clip: true

        Root.ControlAudio {
            id: audio
            visible: control.page === "audio"
            theme: control.theme
        }
        Root.ControlWifi {
            id: wifi
            visible: control.page === "wifi"
            theme: control.theme
        }
        Root.ControlBluetooth {
            id: bluetooth
            visible: control.page === "bluetooth"
            theme: control.theme
        }
        Root.ControlPower {
            id: power
            onRan: control.close()
            visible: control.page === "power"
            probe: control.opened
            theme: control.theme
        }
        Root.ControlDisplay {
            id: display
            visible: control.page === "display"
            probe: control.opened
            theme: control.theme
        }
        Root.ControlRoute {
            id: route
            visible: control.page === "route"
            probe: control.opened
            theme: control.theme
            notifs: control.notifs
            sync: control.sync
        }
    }

    // Home: the clock with today's date, then the tiles; the click-outside check reads a press on this as one on Control.
    Item {
        id: home
        objectName: "card"
        visible: control.page === ""
        x: 16
        y: 16
        width: Home.WIDTH
        height: Home.height()

        Row {
            height: Home.ROWS[0]
            x: 4
            spacing: 14

            Text {
                id: bigClock
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: Qt.formatTime(control.now, "HH:mm")
                color: control.on
                font.family: control.fonts.mono ?? ""
                font.pixelSize: 34
                font.weight: Font.Bold
                font.letterSpacing: -1
                opacity: control.clockHidden ? 0 : 1
            }

            Rectangle {
                id: calendarBox
                readonly property bool focused: control.cursor === "calendar"
                anchors.verticalCenter: parent.verticalCenter
                width: dateColumn.implicitWidth + 16
                height: dateColumn.implicitHeight + 8
                radius: 10
                color: focused ? Qt.alpha(control.on, 0.1) : "transparent"

                Column {
                    id: dateColumn
                    anchors.centerIn: parent

                    Text {
                        id: dateText
                        textFormat: Text.PlainText
                        text: Qt.formatDate(control.now, "dddd, d MMMM")
                        color: control.on
                        font.family: control.fonts.ui ?? ""
                        font.pixelSize: 13
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: "Calendar"
                        color: control.tones.muted
                        font.family: control.fonts.ui ?? ""
                        font.pixelSize: 11
                    }
                }

                Root.Click {
                    name: "control-tile:calendar"
                    onTapped: control.act("calendar")
                }
            }
        }

        Repeater {
            id: tileRepeater
            // One delegate per tile for good; each reads its tile from control.tiles, so a change of volume or time redraws text, not the tiles.
            model: Home.TILES.length - 1

            // A tile: its fill only, no edge (8B5MMCB6); on, it inverts.
            Rectangle {
                id: tile
                required property int index
                readonly property var t: control.tiles[index]
                readonly property var at: Home.TILES[index + 1]
                readonly property bool focused: control.cursor === at.id
                // The tile's drawn content, for state(): it must sit inside the tile.
                readonly property Item content: tileLoader.item?.children[0] ?? null
                readonly property color ink: t.on ? control.fill : control.on
                readonly property color sub: t.on ? Qt.alpha(control.fill, 0.7) : control.tones.muted
                x: at.x
                y: Home.rowTop(at.row)
                width: at.w
                height: Home.ROWS[at.row]
                radius: 14
                // The focused tile is a shade above the rest, as the launcher's selected card is; an inverted one dims a little instead.
                color: t.on ? Qt.alpha(control.on, focused ? 0.8 : 1) : Qt.alpha(control.on, focused ? 0.1 : 0.05)

                // Under the click area, which takes no wheel; only the sliders take a turn.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    enabled: tile.at.id === "sound" || tile.at.id === "brightness"
                    onWheel: event => control.turn(tile.at.id, event.angleDelta.y)
                }

                Root.Click {
                    name: "control-tile:" + tile.at.id
                    onTapped: control.act(tile.at.id)
                }

                // Wi-Fi, Bluetooth, Record screen, Battery and Sync: a round icon beside the name and a line under it.
                Component {
                    id: iconLayout
                    // A Loader sizes its item to itself, so the layout sits in a plain Item that takes that size and keeps its own anchors.
                    Item {
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            spacing: 10
                            Rectangle {
                                width: 36
                                height: 36
                                radius: 18
                                // Inverted, the circle is the island's fill again, as board 4 draws Wi-Fi.
                                color: tile.t.on ? control.fill : Qt.alpha(control.on, 0.1)
                                Text {
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: String.fromCodePoint(({ wifi: 0xF0928, bluetooth: 0xF00AF, record: 0xF044A, battery: 0xF0082, sync: 0xF04E6 })[tile.t.id] ?? 0xF0928)
                                    color: tile.t.id === "record" || tile.t.danger ? control.tones.danger : control.on
                                    font.family: "Symbols Nerd Font Mono"
                                    font.pixelSize: 18
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: tile.width - 12 - 36 - 10 - 12
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: tile.t.label
                                    color: tile.ink
                                    font.family: control.fonts.ui ?? ""
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: tile.t.detail
                                    color: tile.t.danger ? control.tones.danger : tile.sub
                                    font.family: control.fonts.ui ?? ""
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }

                // Sound: its name and output over a pill slider.
                Component {
                    id: soundLayout
                    // A Loader sizes its item to itself, so the layout sits in a plain Item that takes that size and keeps its own anchors.
                    Item {
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            width: tile.width - 24
                            spacing: 7
                            Item {
                                width: parent.width
                                height: soundName.implicitHeight
                                Text {
                                    id: soundName
                                    textFormat: Text.PlainText
                                    text: tile.t.label
                                    color: tile.ink
                                    font.family: control.fonts.ui ?? ""
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.baseline: soundName.baseline
                                    width: Math.min(implicitWidth, parent.width - soundName.implicitWidth - 8)
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: tile.t.detail
                                    color: tile.sub
                                    font.family: control.fonts.ui ?? ""
                                    font.pixelSize: 11
                                }
                            }
                            Pill {
                                width: parent.width
                                height: 18
                                level: tile.t.level ?? 0
                                glyph: 0xF057E
                            }
                        }
                    }
                }

                // Brightness: its name, a pill slider and the percent.
                Component {
                    id: brightnessLayout
                    // A Loader sizes its item to itself, so the layout sits in a plain Item that takes that size and keeps its own anchors.
                    Item {
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 14
                            spacing: 12
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 92
                                textFormat: Text.PlainText
                                text: tile.t.label
                                color: tile.ink
                                font.family: control.fonts.ui ?? ""
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Pill {
                                anchors.verticalCenter: parent.verticalCenter
                                width: tile.width - 28 - 92 - 38 - 24
                                height: 22
                                level: tile.t.level ?? 0
                                glyph: 0xF05A8
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38
                                horizontalAlignment: Text.AlignRight
                                textFormat: Text.PlainText
                                text: tile.t.detail
                                color: control.tones.muted
                                font.family: control.fonts.ui ?? ""
                                font.pixelSize: 13
                            }
                        }
                    }
                }

                // Do Not Disturb and Stay awake: a glyph, the name and a switch.
                Component {
                    id: switchLayout
                    // A Loader sizes its item to itself, so the layout sits in a plain Item that takes that size and keeps its own anchors.
                    Item {
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: String.fromCodePoint(tile.t.id === "dnd" ? 0xF0F65 : 0xF0176)
                                color: tile.t.on ? tile.ink : control.tones.muted
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 16
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: tile.width - 12 - 16 - 10 - 10 - 38 - 12
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: tile.t.label
                                color: tile.ink
                                font.family: control.fonts.ui ?? ""
                                font.pixelSize: 13
                            }
                            Switch {
                                anchors.verticalCenter: parent.verticalCenter
                                on: tile.t.on
                                inverted: tile.t.on
                            }
                        }
                    }
                }

                // Lock and Power: a square button with its glyph, Power in the danger tone.
                Component {
                    id: buttonLayout
                    // A Loader sizes its item to itself, so the layout sits in a plain Item that takes that size and keeps its own anchors.
                    Item {
                        Text {
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String.fromCodePoint(tile.t.id === "lock" ? 0xF033E : 0xF0425)
                            color: tile.t.danger ? control.tones.danger : control.on
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 17
                        }
                    }
                }

                // Each tile builds only its own layout: five layouts in every tile cost about 4 MB of idle RSS.
                Loader {
                    id: tileLoader
                    anchors.fill: parent
                    sourceComponent: ["wifi", "bluetooth", "record", "battery", "sync"].indexOf(tile.at.id) >= 0 ? iconLayout : tile.at.id === "sound" ? soundLayout : tile.at.id === "brightness" ? brightnessLayout : tile.at.id === "dnd" || tile.at.id === "awake" ? switchLayout : buttonLayout
                }
            }
        }
    }

    // A page: the back circle and the section's name, then its rows; a row may carry a glyph, a line under its name and a mark at its right, and the asking network's row opens its password field in place.
    Column {
        id: pageColumn
        objectName: "card"
        visible: control.page !== ""
        x: 16
        y: 16
        width: control.width - 32
        spacing: 6

        Item {
            width: parent.width
            height: 40

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 16
                color: Qt.alpha(control.on, 0.1)
                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(0xF0141)
                    color: control.on
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 16
                }
                Root.Click {
                    name: "control-back"
                    onTapped: control.back()
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 44
                textFormat: Text.PlainText
                text: control.page === "audio" ? "Sound" : Lib.TITLES[control.current]
                color: control.on
                font.family: control.fonts.ui ?? ""
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            // Bluetooth's adapter, on or off, as o turns it.
            Switch {
                visible: control.page === "bluetooth" && !!bluetooth.adapter
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                on: bluetooth.on

                Root.Click {
                    name: "control-switch"
                    onTapped: bluetooth.key({ key: Qt.Key_O, modifiers: 0, text: "" })
                }
            }
        }

        // A failed pair says so on the Bluetooth page; the request itself draws as the island's pairing prompt over Control.
        Rectangle {
            id: pairCard
            visible: control.page === "bluetooth" && control.pairNote !== ""
            width: parent.width
            height: pairText.implicitHeight + 24
            radius: 12
            color: Qt.alpha(control.on, 0.1)

            Text {
                id: pairText
                x: 12
                y: 12
                width: parent.width - 24
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: control.pairNote
                color: control.tones.danger
                font.family: control.fonts.ui ?? ""
                font.pixelSize: 13
                font.weight: Font.Bold
            }
        }

        // A page with no rows says why, as Bluetooth turned off does.
        Text {
            visible: control.rows.length === 0 && text !== ""
            x: 4
            height: 48
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: control.page === "bluetooth" ? bluetooth.empty : control.page === "wifi" ? (wifi.wifi.length ? "No networks" : "No Wi-Fi") : control.page === "audio" ? "No audio devices" : ""
            color: control.tones.muted
            font.family: control.fonts.ui ?? ""
            font.pixelSize: 13
        }

        Repeater {
            id: rowRepeater
            // Power draws its own page below.
            model: control.page === "power" ? [] : control.rows

            // A row, under its caption when it starts a group: OUTPUT, PLAYING or INPUT.
            Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: index === control.section.selected
                // The secured network the password field is open for.
                readonly property bool asking: control.page === "wifi" && wifi.typing && wifi.networks[index] === wifi.asking
                readonly property bool level: modelData.level !== undefined
                readonly property string drawnDetail: level ? value.text : detail.text
                readonly property string cap: modelData.cap ?? ""
                readonly property alias color: rowFill.color
                readonly property alias box: rowFill
                readonly property var fieldLook: rowFill.look
                readonly property int detailLines: level ? 1 : detail.lineCount
                readonly property Item nameItem: level ? levelName : title
                readonly property string pillGlyph: level ? rowPill.drawnGlyph : ""
                width: pageColumn.width
                height: rowFill.height + (cap ? 24 : 0)

                Text {
                    visible: row.cap !== ""
                    x: 4
                    height: 22
                    verticalAlignment: Text.AlignBottom
                    textFormat: Text.PlainText
                    text: row.cap
                    color: control.tones.muted
                    font.family: control.fonts.ui ?? ""
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }

                Rectangle {
                    id: rowFill
                    y: row.cap ? 24 : 0
                    width: parent.width
                    height: row.asking ? 104 : row.level ? 52 : 48
                    radius: 12
                    color: Qt.alpha(control.on, row.on ? 0.1 : 0.05)

                    // Under the click area, which takes no wheel; a slider row steps on a turn.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        enabled: row.level
                        onWheel: event => control.turnRow(row.index, event.angleDelta.y)
                    }

                    Root.Click {
                        name: "control-row:" + row.index
                        onTapped: control.runRow(row.index)
                    }

                    // A slider row: the glyph in a circle, the name, a pill slider, the percent and a check on the default.
                    Row {
                        visible: row.level
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        width: parent.width - 24
                        spacing: 12

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            radius: 16
                            color: Qt.alpha(control.on, 0.1)
                            Text {
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: row.modelData.glyph ?? ""
                                color: control.on
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 16
                            }
                        }
                        Text {
                            id: levelName
                            anchors.verticalCenter: parent.verticalCenter
                            width: 150
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: row.modelData.title
                            color: control.on
                            font.family: control.fonts.ui ?? ""
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Pill {
                            id: rowPill
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 32 - 150 - 44 - 16 - 4 * 12
                            height: 18
                            level: row.modelData.level ?? 0
                        }
                        Text {
                            id: value
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            horizontalAlignment: Text.AlignRight
                            textFormat: Text.PlainText
                            text: row.modelData.value ?? ""
                            color: control.tones.muted
                            font.family: control.fonts.ui ?? ""
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            textFormat: Text.PlainText
                            text: row.modelData.mark ?? ""
                            color: control.tones.accent
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 14
                        }
                    }

                    Row {
                        visible: !row.level
                        y: 24 - height / 2
                        x: 12
                        width: parent.width - 24
                        spacing: 12

                        Text {
                            visible: !!row.modelData.glyph
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            textFormat: Text.PlainText
                            text: row.modelData.glyph ?? ""
                            color: control.on
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 17
                        }
                        Text {
                            id: title
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 260)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                            text: row.modelData.title
                            color: control.on
                            font.family: control.fonts.ui ?? ""
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            id: detail
                            anchors.verticalCenter: parent.verticalCenter
                            // The rest of the row less the glyph and the mark; a long line is cut on one line, never wrapped over the next row.
                            width: parent.width - title.width - (row.modelData.glyph ? 32 : 0) - (mark.visible ? mark.width + 12 : 0) - 12
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                            text: row.asking && wifi.message !== "" ? wifi.message : row.modelData.sub ?? row.modelData.detail
                            color: row.asking && wifi.message !== "" || row.modelData.tone === "danger" ? control.tones.danger : control.tones.muted
                            font.family: control.fonts.ui ?? ""
                            font.pixelSize: 11
                        }
                        Text {
                            id: mark
                            visible: !!row.modelData.mark
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: row.modelData.mark ?? ""
                            color: row.modelData.markTone === "accent" ? control.tones.accent : control.tones.muted
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 15
                        }
                    }

                    // The password field and Join, drawn in the asking network's row: one dot per typed character.
                    Row {
                        visible: row.asking
                        x: 12
                        y: 52
                        width: parent.width - 24
                        spacing: 8

                        Rectangle {
                            id: field
                            width: parent.width - join.width - 8
                            height: 36
                            radius: 10
                            color: Qt.alpha(control.on, 0.1)

                            Text {
                                id: dots
                                anchors.verticalCenter: parent.verticalCenter
                                x: 12
                                width: parent.width - 24
                                clip: true
                                textFormat: Text.PlainText
                                text: "•".repeat([...wifi.psk].length)
                                color: control.on
                                font.family: control.fonts.ui ?? ""
                                font.pixelSize: 13
                                font.letterSpacing: 2
                            }
                            Text {
                                id: placeholder
                                visible: wifi.psk === ""
                                anchors.verticalCenter: parent.verticalCenter
                                x: 12
                                textFormat: Text.PlainText
                                text: "Password"
                                color: control.tones.muted
                                font.family: control.fonts.ui ?? ""
                                font.pixelSize: 13
                            }
                        }
                        Rectangle {
                            id: join
                            width: joinText.implicitWidth + 32
                            height: 36
                            radius: 10
                            color: control.on
                            Text {
                                id: joinText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: "Join"
                                color: control.fill
                                font.family: control.fonts.ui ?? ""
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Root.Click {
                                name: "control-join"
                                onTapped: wifi.key({ key: Qt.Key_Return, modifiers: 0, text: "" })
                            }
                        }
                    }

                    // Read by state(): the field as drawn.
                    readonly property var look: row.asking ? { text: dots.text, font: dots.fontInfo.family, px: dots.font.pixelSize, ink: String(dots.color), fill: String(field.color), placeholder: placeholder.visible ? placeholder.text : null } : null
                }
            }
        }

        // Power, as board 4 draws it: the battery beside the charge limit, the profile and Stay awake as segments, then four square actions, the selected part a shade lighter; it loads only while its page shows.
        Loader {
            id: powerLoader
            active: control.page === "power"
            visible: active
            width: parent.width
            sourceComponent: Component {
                Column {
                    id: powerView
                    // Read by state(): the segments lit and each action's label, as drawn.
                    readonly property var drawn: ({
                            profile: profileSegments.drawnCurrent,
                            awake: awakeSegments.drawnCurrent,
                            actions: Array.from({ length: actionRepeater.count }, (_, i) => actionRepeater.itemAt(i).drawnText)
                        })
                    width: parent.width
                    spacing: 8
                    readonly property string at: power.items[power.selected]?.id ?? ""

                    Row {
                        visible: power.hasBattery || power.chargeLimit >= 0
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            visible: power.hasBattery
                            width: power.chargeLimit >= 0 ? (parent.width - 8) * 2 / 3 : parent.width
                            height: 60
                            radius: 14
                            color: Qt.alpha(control.on, powerView.at === "battery" ? 0.1 : 0.05)

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 12
                                spacing: 10

                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: Qt.alpha(control.on, 0.1)
                                    Text {
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: String.fromCodePoint(0xF0082)
                                        color: control.on
                                        font.family: "Symbols Nerd Font Mono"
                                        font.pixelSize: 18
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        textFormat: Text.PlainText
                                        text: power.hasBattery ? Math.round(power.battery.percentage * 100) + "%" : ""
                                        color: control.on
                                        font.family: control.fonts.ui ?? ""
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: power.hasBattery ? Sys.batteryLine(UPowerDeviceState.toString(power.battery.state).toLowerCase(), power.battery.timeToEmpty, power.battery.timeToFull) : ""
                                        color: control.tones.muted
                                        font.family: control.fonts.ui ?? ""
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: power.chargeLimit >= 0
                            width: power.hasBattery ? (parent.width - 8) / 3 : parent.width
                            height: 60
                            radius: 14
                            color: Qt.alpha(control.on, powerView.at === "limit" ? 0.1 : 0.05)

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 12
                                Text {
                                    textFormat: Text.PlainText
                                    text: "Charge limit"
                                    color: control.on
                                    font.family: control.fonts.ui ?? ""
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: power.chargeLimit > 0 ? power.chargeLimit + "%" : "Off"
                                    color: control.tones.muted
                                    font.family: control.fonts.ui ?? ""
                                    font.pixelSize: 11
                                }
                            }
                            Switch {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                on: power.chargeLimit > 0
                            }
                            Root.Click {
                                name: "control-power:limit"
                                onTapped: control.runPower("limit")
                            }
                        }
                    }

                    // The profile, one segment per profile, the current one inverted.
                    Segments {
                        id: profileSegments
                        selected: powerView.at === "profile"
                        options: power.profiles.map(p => ({ id: String(p), label: ({ [PowerProfile.PowerSaver]: "Power saver", [PowerProfile.Balanced]: "Balanced", [PowerProfile.Performance]: "Performance" })[p] }))
                        current: String(PowerProfiles.profile)
                        onPicked: id => {
                            power.selected = power.items.findIndex(i => i.id === "profile");
                            PowerProfiles.profile = Number(id);
                        }
                    }

                    // Stay awake: off or one of its steps, the one that holds it inverted.
                    Segments {
                        id: awakeSegments
                        selected: powerView.at === "awake"
                        label: "Stay awake"
                        glyph: 0xF0176
                        options: [{ id: "0", label: "Off" }, { id: "30", label: "30 min" }, { id: "60", label: "1 h" }, { id: "120", label: "2 h" }]
                        current: String(Idle.awakeStep(control.now.getTime(), Root.State.awakeUntil))
                        onPicked: id => {
                            power.selected = power.items.findIndex(i => i.id === "awake");
                            power.setAwake(Number(id));
                        }
                    }

                    // Lock, Log out, Reboot and Power off: a press asks again, red as "Reboot?", and only a second Enter or click runs it.
                    Row {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            id: actionRepeater
                            model: Sys.ACTIONS

                            Rectangle {
                                id: action
                                required property var modelData
                                readonly property bool asking: power.confirming === modelData.id
                                readonly property string drawnText: actionText.text
                                width: (parent.width - 24) / 4
                                height: 96
                                radius: 14
                                color: asking ? Qt.alpha(control.tones.danger, 0.16) : Qt.alpha(control.on, powerView.at === modelData.id ? 0.1 : 0.05)

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 10

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        textFormat: Text.PlainText
                                        text: String.fromCodePoint(({ lock: 0xF033E, logout: 0xF0343, reboot: 0xF0709, poweroff: 0xF0425 })[action.modelData.id])
                                        color: action.asking || action.modelData.id === "poweroff" ? control.tones.danger : control.on
                                        font.family: "Symbols Nerd Font Mono"
                                        font.pixelSize: 24
                                    }
                                    Text {
                                        id: actionText
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        textFormat: Text.PlainText
                                        text: action.asking ? action.modelData.title + "?" : action.modelData.title
                                        color: action.asking ? control.tones.danger : control.tones.muted
                                        font.family: control.fonts.ui ?? ""
                                        font.pixelSize: 12
                                        font.weight: action.asking ? Font.Bold : Font.Normal
                                    }
                                }

                                Root.Click {
                                    name: "control-power:" + action.modelData.id
                                    onTapped: control.runPower(action.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        // While Bluetooth scans, a row says so under the devices.
        Rectangle {
            id: scanRow
            visible: control.page === "bluetooth" && bluetooth.discovering
            width: parent.width
            height: 48
            radius: 12
            color: Qt.alpha(control.on, 0.05)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                spacing: 12

                Text {
                    width: 20
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(0xF0349)
                    color: control.tones.muted
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 17
                }
                Text {
                    textFormat: Text.PlainText
                    text: "Scanning for devices"
                    color: control.tones.muted
                    font.family: control.fonts.ui ?? ""
                    font.pixelSize: 13
                }
            }
        }
    }

    // A pill slider: the track in the island's text at 12%, the level filled in the text with its glyph.
    component Pill: Rectangle {
        property real level: 0
        property int glyph: 0
        readonly property string drawnGlyph: glyph ? String.fromCodePoint(glyph) : ""
        radius: height / 2
        color: Qt.alpha(control.on, 0.12)

        Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, parent.level)))
            height: parent.height
            radius: parent.radius
            visible: parent.level > 0
            color: control.on

            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 7
                textFormat: Text.PlainText
                // A page's slider has no glyph, and code point 0 would draw a missing-glyph box.
                text: parent.parent.glyph ? String.fromCodePoint(parent.parent.glyph) : ""
                color: control.fill
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: parent.height <= 18 ? 11 : 13
            }
        }
    }

    // A segmented control: an optional glyph and label, then one segment per option, the current one inverted.
    component Segments: Rectangle {
        id: seg
        property var options: []
        property string current: ""
        property bool selected: false
        property string label: ""
        property int glyph: 0
        signal picked(string id)
        readonly property real labelWidth: label ? 120 : 0
        width: parent.width
        height: 44
        radius: 14
        color: Qt.alpha(control.on, selected ? 0.1 : 0.05)

        Row {
            visible: seg.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 8
            Text {
                textFormat: Text.PlainText
                text: seg.glyph ? String.fromCodePoint(seg.glyph) : ""
                color: control.on
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 15
            }
            Text {
                textFormat: Text.PlainText
                text: seg.label
                color: control.on
                font.family: control.fonts.ui ?? ""
                font.pixelSize: 13
            }
        }

        Row {
            x: 4 + seg.labelWidth
            y: 4
            spacing: 4
            Repeater {
                model: seg.options
                Rectangle {
                    required property var modelData
                    readonly property bool on: modelData.id === seg.current
                    width: (seg.width - 8 - seg.labelWidth - 4 * (seg.options.length - 1)) / seg.options.length
                    height: 36
                    radius: 10
                    color: on ? control.on : "transparent"
                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: parent.modelData.label
                        color: parent.on ? control.fill : control.tones.muted
                        font.family: control.fonts.ui ?? ""
                        font.pixelSize: 13
                        font.weight: parent.on ? Font.Bold : Font.Normal
                    }
                    Root.Click {
                        name: "control-seg:" + parent.modelData.label
                        onTapped: seg.picked(parent.modelData.id)
                    }
                }
            }
        }

        // Read by state(): which segment shows as current.
        readonly property string drawnCurrent: (options.find(o => o.id === current) ?? {}).label ?? ""
    }

    // A 38 x 22 switch: the knob at the right and filled while on.
    component Switch: Rectangle {
        property bool on: false
        property bool inverted: false
        width: 38
        height: 22
        radius: 11
        color: on ? (inverted ? control.fill : control.on) : Qt.alpha(control.on, 0.12)

        Rectangle {
            x: parent.on ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: parent.on ? (parent.inverted ? control.on : control.fill) : control.tones.muted
        }
    }
}
