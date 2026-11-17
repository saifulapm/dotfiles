import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "." as Root
import "lib/island.mjs" as I
import "lib/questions.mjs" as Q
import "lib/voice.mjs" as V
import "lib/notifs.mjs" as N
import "lib/worldclock.mjs" as W
import "lib/control.mjs" as C
import "lib/click.mjs" as ClickLib
import "lib/island-host.mjs" as H
import "lib/switch.mjs" as Sw
import "lib/island-live.mjs" as L
import "lib/island-tones.mjs" as T

// At rest the island is the clock, a Surface box 10 px below the top edge; it draws in the surfaces' window, which fills its output.
Item {
    id: island

    required property var theme
    required property var niri
    required property var clock
    // dots-zones's answer for the calendar's city column, run when the calendar first opens.
    required property var zones
    required property var notifs
    required property var questions
    required property var lock
    // The players, which the media card reads and runs.
    required property var media
    // A theme switch's failure, shown in place of the clock for 5 s.
    property string notice: ""
    // What the island may show; each is null while it has nothing to show. A Bluetooth pairing request asks ahead of an agent's question, since it times out.
    readonly property var question: Root.Pairing.question ?? questions.current
    // The month the calendar shows, {year, month}, while Mod+I has it open.
    property var calendar: null
    readonly property var grid: heldCalendar ? I.monthGrid(heldCalendar.year, heldCalendar.month, clockLook.grid.weekStart) : null
    // The month heading as the theme words it: one text, or the month and the year apart.
    readonly property var titleParts: grid ? clockLook.grid.title.parts(grid) : []
    readonly property int today: heldCalendar && heldCalendar.year === clock.now.getFullYear() && heldCalendar.month === clock.now.getMonth() ? clock.now.getDate() : 0
    // Home first, then UTC, London and New York, each {city, time, offset, day, home}; empty until dots-zones answers.
    readonly property var cities: zones.answer ? W.cityRows(clock.now.getTime(), zones.answer) : []
    readonly property var clockLook: V.clockLook(theme.tokens)
    readonly property var notification: H.shownNotification(notifs.current, sharing)
    readonly property real recordingSince: Root.State.recordingSince
    // Bumped each second while a recording runs, so its counter moves.
    property real recordingNow: 0
    readonly property var recording: recordingSince > 0 ? I.recordingText(recordingSince, Math.max(recordingNow, recordingSince)) : null
    // Every niri cast but the shell's own recording; Do Not Disturb never hides it (2N83H6SJ).
    readonly property var shares: niri.shares(Root.State.recordingPid)
    readonly property var sharing: shares.length ? shares : null
    // Every capture stream, and each link group into one, from the registry alone, so tracking them never changes the list, which would loop; a stream's properties and a link's state arrive only once tracked.
    readonly property var captures: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioInStream)
    readonly property var captureLinks: Pipewire.linkGroups.values.filter(g => captures.includes(g.target))
    readonly property PwNode micSource: Pipewire.defaultAudioSource
    // The apps recording from the default source, newest first; a link's end that has gone reads -1 (A1KE151A). Do Not Disturb never hides it (N6622XD7).
    readonly property var micStreams: captures.map(n => ({
                id: n.id,
                capture: true,
                props: n.properties ?? {}
            }))
    readonly property var micLinks: captureLinks.map(g => ({
                source: g.source?.id ?? -1,
                target: g.target?.id ?? -1,
                active: g.state === PwLinkState.Active
            }))
    readonly property var micApps: I.micApps(micStreams, micLinks, micSource?.id ?? -1, Root.State.recordingPid)
    // The newest of them, whose window a click on the mic slot focuses.
    readonly property int micClient: I.micClient(micStreams, micLinks, micSource?.id ?? -1, Root.State.recordingPid)
    readonly property var mic: micApps.length ? micApps : null
    // Mod+I on LIVE opens a card of the shares, with who watches each; Enter stops every PipeWire share, Esc closes (MGX0WWS8).
    property bool sharingOpen: false
    readonly property var sharingCard: sharingOpen && sharing ? sharing : null
    // Each screencopy share's process name by pid, read from /proc whenever the pids change.
    property var watcherNames: ({})
    readonly property string screencopyPids: shares.filter(s => s.kind !== "PipeWire").map(s => s.pid).join(" ")
    onScreencopyPidsChanged: {
        if (!screencopyPids)
            return;
        comms.running = false;
        comms.command = ["sh", "-c", 'for p; do printf "%s\t" "$p"; cat "/proc/$p/comm" 2>/dev/null; printf "\\0"; done', "sh"].concat(screencopyPids.split(" "));
        comms.running = true;
    }
    readonly property var shareRows: (sharingCard ?? []).map(s => I.shareRow(s, watcherNames))
    // An agent's lease, {who, left} in ms, while one holds the session; leaseNow is bumped each second so the time left moves.
    property real leaseNow: Date.now()
    readonly property var lease: lock.leased ? { who: lock.heldBy, left: Math.max(0, lock.leaseUntil - leaseNow) } : null
    readonly property var leaseLook: V.leaseLook(theme.tokens)
    // The last minute takes the theme's warning; a renew past it brings the normal look back.
    readonly property bool leaseWarning: lease !== null && lease.left <= 60000
    // Mod+I during a lease opens its card: who, when it unlocked and the time left; Enter locks, Esc closes.
    property bool leaseOpen: false
    readonly property var leaseCard: leaseOpen ? lease : null
    property var osd: null
    // A paired device that just connected, {name, address, battery}, for its 2 s.
    property var btConnect: null
    property var toast: null
    // dots-capture's result, {kind, title, detail, swatch}, for the toast's 1.5 s.
    property var capture: null
    // A Taildrop send, {count, to, pct}, from dots-taildrop-send's start until its done.
    property var sending: null
    // A YouTube download: the one underneath, {n, total, list, title, pct, kind}, and a failure held 5 s over it, {title, reason}. Either one fills the slot.
    property var download: null
    property var failure: null
    readonly property var downloading: download || failure ? Object.assign({ n: 1, total: 1, list: "", title: "", pct: 0, kind: "" }, download, { failure }) : null
    property var playing: null
    // Opened by a click on the playing island; it reads the player the media keys run, so it stays through a pause.
    property bool mediaOpen: false
    readonly property var mediaCard: mediaOpen && media.target ? {
        title: media.target.trackTitle,
        artist: media.target.trackArtist,
        playing: media.target.isPlaying
    } : null
    property var heldMediaCard: null
    onMediaCardChanged: if (mediaCard)
        heldMediaCard = mediaCard
    // What each part last showed, so a part can leave with its content after its slot has emptied.
    property var heldCalendar: null
    property var heldNotification: null
    property var heldQuestion: null
    property var heldShareRows: []
    onShareRowsChanged: if (shareRows.length)
        heldShareRows = shareRows
    property string heldText: ""
    onCalendarChanged: if (calendar)
        heldCalendar = calendar
    onNotificationChanged: if (notification)
        heldNotification = notification
    onQuestionChanged: if (question)
        heldQuestion = question
    onTextChanged: if (I.isCompact(mode))
        heldText = text
    Component.onCompleted: heldText = text
    readonly property var slots: ({
            question,
            leaseCard,
            lease,
            calendar,
            sharingCard,
            mediaCard,
            notification,
            sharing,
            mic,
            recording,
            osd,
            btConnect,
            toast,
            capture,
            sending,
            downloading,
            playing,
            notice
        })
    // A surface open in the island outranks every slot; an arrival closes it instead (PCGX7JPJ).
    readonly property string mode: H.modeOf(surface, slots)
    // The slots as they last were, so an arrival while a surface is open can be told from a state already live.
    property var slotsSeen: ({})
    signal surfaceYielded
    onSlotsChanged: {
        if (surface && H.surfaceYields(slotsSeen, slots))
            surfaceYielded();
        slotsSeen = slots;
    }
    // When the current mode began, in ms since the epoch, so a check can time a mode without polling error.
    property real modeSince: Date.now()
    onModeChanged: {
        modeSince = Date.now();
        // The keyboard goes back once what it was given for is gone, such as a notification whose 5 s ran out.
        if (focused && ["calendar", "question", "notification", "leaseCard", "sharingCard", "mediaCard"].indexOf(mode) < 0)
            release();
    }
    // The lease's text is read back from what is drawn, since each theme words it its own way; the rest picks its mode from the same slots it reads, so a slot that empties never meets a mode not yet moved on.
    readonly property string text: mode === "sharingCard" ? shareRows.map(I.shareRowText).join(" · ") : mode === "leaseCard" ? (c => [c.who, c.unlocked, c.time].join(" · "))(leaseCardDrawn()) : mode === "lease" ? [leaseLook.slot.label.text, leaseLook.slot.who.text(lease.who), leaseLook.time(lease.left)].filter(t => t).join(" ") : I.islandText(H.modeOf(surface, slots), slots, clock.now)
    // How the theme's board draws a notification and the OSD.
    readonly property var noteLook: V.islandLook(theme.tokens)
    readonly property var chipLook: V.chipLook(theme.tokens)
    // The action chips draw as the legend's key chips, for a notification its app held as it arrived; they stay drawn as the card leaves.
    readonly property var keyLook: V.listLook(theme.tokens)
    property var noteChips: []
    onHeldNotificationChanged: noteChips = heldNotification && notifs.live[heldNotification.key] ? N.chipsOf(heldNotification.actions) : []
    // True from a drag's start to its drop; the toast holds while it is.
    readonly property bool noteDragging: noteArea.dragging
    // The notification's hold waits while the pointer is on the box, Mod+I focuses it or a drag holds it.
    readonly property bool noteHeld: mode === "notification" && (noteArea.containsMouse || focused || noteDragging)
    onNoteHeldChanged: notifs.pause(noteHeld)
    readonly property var osdLook: V.osdLook(theme.tokens)
    // As drawn: the theme's 420 or 440 px notification card, a 560 px question and calendar, and the theme's OSD bar; any other mode is one line as wide as its text.
    readonly property var sizes: ({
            label: mode === "rest" || mode === "surface" ? [H.REST.width, H.REST.height] : [I.boxWidth(Math.ceil(label.implicitWidth) + 28), 34],
            live: [L.liveWidth({ text: liveText.implicitWidth, tail: liveTail.visible ? liveTail.implicitWidth : 0, bar: liveBar.visible, swatch: liveSwatch.visible, clock: liveClock.implicitWidth }), 34],
            leaseCard: [leaseLook.card.width, leaseColumn.implicitHeight],
            sharingCard: [noteLook.width, shareColumn.implicitHeight + 24],
            notification: [440, card.implicitHeight + 32],
            // A long question scrolls inside a card that keeps a fifth of the screen clear.
            question: [I.MAX_WIDTH, Math.min(ask.implicitHeight + 32, Math.round(output.height * 0.8))],
            calendar: [I.MAX_WIDTH, month.implicitHeight + 32],
            mediaCard: [noteLook.width, mediaColumn.implicitHeight + 24],
            // An open surface's own width and height, up to the output's less 48 px each way (PMQRFEYY, M4SVCQVQ).
            surface: [Math.min(surfaceWidth, output.width - 48), Math.min(surfaceHeight, output.height - 48)]
        })
    readonly property string part: ["notification", "question", "calendar", "leaseCard", "sharingCard", "mediaCard", "surface"].indexOf(mode) >= 0 ? mode : live ? "live" : "label"
    // Board 2's one-line state of this mode, picked from the same slots the mode reads, or null; heldLive keeps the last one so it leaves drawn.
    readonly property var live: L.liveState(H.modeOf(surface, slots), slots, clock.now)
    property var heldLive: null
    onLiveChanged: if (live)
        heldLive = live
    // The clock as every card's header draws it.
    readonly property string clockNow: L.clockText(clock.now)
    // The island's four tones, each lifted to 4.5:1 on its fill.
    readonly property var tones: theme.tokens ? T.islandTones(theme.tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    // The box's size once a morph settles; the margins and `island state` read this, never a size mid-morph.
    readonly property real targetWidth: sizes[part][0]
    readonly property real targetHeight: sizes[part][1]
    readonly property real boxWidth: targetWidth
    readonly property real drawnWidth: box.width
    // The approved motion (38G8XV1J); none before the scheme loads, so the first frame draws at rest.
    readonly property var motion: theme.tokens ? H.hostMotion() : null
    readonly property bool animating: morphing.running || [labelPart, livePart, leaseCardPart, sharingCardPart, mediaCardPart, notePart, monthPart, askPart, surfacePart].some(p => p.busy) || surfaceBusy
    // The box morphs from where it is drawn to its target on one clock, so width and height land together.
    property real fromWidth: 0
    property real fromHeight: 0
    property real toWidth: targetWidth
    property real toHeight: targetHeight
    property real progress: 1
    // Picked when a morph starts, since the mode that picks it changes in the same instant as the target.
    property var curve: null
    // The last morph as drawn, for island state and the bench: open or close, the box it began from, and each frame's [ms since it began, box width, box height, window width, window height, work ms].
    property string morphKind: ""
    property var morphFrom: null
    property var morphFrames: []
    property real morphT0: 0
    // When the window's frame began its scene graph sync and finished rendering, which the surfaces' window sets.
    property real syncedAt: 0
    property real renderedAt: 0
    // Called on each of the window's frames while the box morphs; the last field is the frame's own work, sync to rendered, in ms.
    function swapped() {
        if (morphWaits > 0) {
            morphWaits -= 1;
            if (morphWaits === 0) {
                morphT0 = Date.now();
                morphing.restart();
            }
            return;
        }
        if (morphing.running)
            morphFrames.push([Date.now() - morphT0, box.width, box.height, parent ? parent.width : 0, parent ? parent.height : 0, renderedAt - syncedAt]);
    }
    // What the box last morphed for; a size change with the same content, such as a font loading or a theme switch, snaps instead.
    property string morphedFor: ""
    onTargetWidthChanged: morph()
    onTargetHeightChanged: morph()

    function morph() {
        const content = part + ":" + (notification?.key ?? question?.id ?? "");
        const fresh = morphedFor !== "" && content !== morphedFor;
        morphedFor = content;
        // Width and height each call this; the second lands on the morph the first started.
        if (!fresh && morphing.running) {
            toWidth = targetWidth;
            toHeight = targetHeight;
            return;
        }
        if (!motion || !fresh) {
            morphing.stop();
            toWidth = targetWidth;
            toHeight = targetHeight;
            progress = 1;
            return;
        }
        fromWidth = box.width;
        fromHeight = box.height;
        morphKind = I.isCompact(mode) ? "close" : "open";
        morphFrom = [fromWidth, fromHeight];
        morphFrames = [];
        morphT0 = Date.now();
        toWidth = targetWidth;
        toHeight = targetHeight;
        curve = I.isCompact(mode) ? motion.close : motion.open;
        morphing.duration = curve.ms;
        progress = 0;
        // A surface's open changes the window's input and keyboard, which draws a frame of its own; the box starts moving two frames later, so that frame is not one of the morph's.
        if (part === "surface") {
            morphing.stop();
            morphWaits = 2;
            return;
        }
        morphWaits = 0;
        morphing.restart();
    }
    // Frames still to swap before a surface's open starts to move.
    property int morphWaits: 0
    component HeadText: Text {
        textFormat: Text.PlainText
        color: island.noteLook.head.color
        font.family: island.noteLook.head.font
        font.pixelSize: island.noteLook.head.size
        font.letterSpacing: island.noteLook.head.spacing
    }
    // Six dots, two across and three down, that say the chip can be picked up.
    component ChipGrip: Item {
        property var size: ({ w: 8, h: 12, r: 1 })
        property color color: "black"
        width: size.w
        height: size.h

        Repeater {
            model: 6
            Rectangle {
                required property int index
                x: parent.width / 2 + (index % 2 ? 2 : -2) - width / 2
                y: parent.height / 2 + (Math.floor(index / 2) - 1) * 4 - height / 2
                width: 2 * parent.size.r
                height: width
                radius: width / 2
                color: parent.color
            }
        }
    }
    // A page with its corner folded, drawn from the board's own path.
    component ChipGlyph: Shape {
        id: chipGlyph
        property var size: ({ w: 12, h: 14, stroke: 1, path: "" })
        property color color: "black"
        width: size.w
        height: size.h
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: chipGlyph.color
            strokeWidth: chipGlyph.size.stroke
            fillColor: "transparent"
            joinStyle: ShapePath.MiterJoin
            PathSvg {
                path: chipGlyph.size.path
            }
        }
    }
    // A chip's outline: a rounded box.
    component ChipBack: Rectangle {
        property color fill: "transparent"
        property color frame: "transparent"
        property real frameWidth: 1
        color: fill
        border.width: frameWidth
        border.color: frame
    }
    // A file notification's chip: the grip, a file glyph and the extension or count; empty, it is the slot a dragged chip left.
    component FileChip: Item {
        id: fileChip
        property var look: null
        // The chipLook place it sits in: toast, row or cursor.
        property var at: null
        property var files: []
        property bool empty: false
        readonly property string text: look && files.length > 0 ? look.label(files) : ""
        readonly property real dash: look?.empty.width ?? 1
        readonly property bool hollow: empty && look !== null
        visible: files.length > 0 && look !== null
        implicitWidth: chipRow.implicitWidth + (at ? at.pad[1] + at.pad[3] : 0)
        implicitHeight: chipRow.implicitHeight + (at ? at.pad[0] + at.pad[2] : 0)

        ChipBack {
            anchors.fill: parent
            visible: !fileChip.hollow
            fill: fileChip.at?.fill ?? "transparent"
            frame: fileChip.at?.frame ?? "transparent"
            radius: fileChip.at?.radius ?? 0
        }
        Shape {
            anchors.fill: parent
            visible: fileChip.hollow
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                strokeColor: fileChip.look?.empty.color ?? "transparent"
                strokeWidth: fileChip.dash
                strokeStyle: ShapePath.DashLine
                dashPattern: [4 / strokeWidth, 3 / strokeWidth]
                fillColor: "transparent"
                PathRectangle {
                    x: fileChip.dash / 2
                    y: fileChip.dash / 2
                    width: fileChip.width - fileChip.dash
                    height: fileChip.height - fileChip.dash
                    radius: fileChip.at?.radius ?? 0
                }
            }
        }
        Row {
            id: chipRow
            x: fileChip.at?.pad[3] ?? 0
            y: fileChip.at?.pad[0] ?? 0
            spacing: fileChip.look?.gap ?? 0
            visible: !fileChip.hollow || fileChip.look.empty.content

            ChipGrip {
                anchors.verticalCenter: parent.verticalCenter
                size: fileChip.look?.grip ?? ({ w: 8, h: 12, r: 1 })
                color: fileChip.hollow ? fileChip.look.empty.color : fileChip.at?.grip ?? "transparent"
            }
            ChipGlyph {
                anchors.verticalCenter: parent.verticalCenter
                size: fileChip.look?.glyph ?? ({ w: 12, h: 14, stroke: 1, path: "" })
                color: fileChip.hollow ? fileChip.look.empty.color : fileChip.at?.glyph ?? "transparent"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: fileChip.text
                color: fileChip.hollow ? fileChip.look.empty.color : fileChip.at?.text ?? "transparent"
                font.family: fileChip.look?.font ?? ""
                font.pixelSize: fileChip.look?.size ?? 10
                font.letterSpacing: fileChip.look?.spacing ?? 0
            }
        }
    }
    // What follows the pointer in a drag: the chip with the file's name, elided, as the boards draw it; grabbed to an image before the drag starts.
    component DragFace: Item {
        id: face
        property var look: null
        property var files: []
        // The grabbed image's url, kept with its result so the image stays alive.
        property var grabbed: null
        readonly property string url: grabbed ? String(grabbed.url) : ""
        readonly property var drag: look?.drag ?? null
        width: faceRow.implicitWidth + (drag ? drag.pad[1] + drag.pad[3] : 0)
        height: faceRow.implicitHeight + (drag ? drag.pad[0] + drag.pad[2] : 0)

        function grab() {
            if (files.length > 0 && width > 0)
                grabToImage(r => face.grabbed = r);
        }

        ChipBack {
            anchors.fill: parent
            fill: face.drag?.fill ?? "transparent"
            frame: face.drag?.frame ?? "transparent"
            frameWidth: face.drag?.frameWidth ?? 1
            radius: face.drag?.radius ?? 0
        }
        Row {
            id: faceRow
            x: face.drag?.pad[3] ?? 0
            y: face.drag?.pad[0] ?? 0
            spacing: face.drag?.gap ?? 0

            ChipGrip {
                visible: face.drag?.grip ? true : false
                anchors.verticalCenter: parent.verticalCenter
                size: face.look?.grip ?? ({ w: 8, h: 12, r: 1 })
                color: face.drag?.grip ?? "transparent"
            }
            ChipGlyph {
                anchors.verticalCenter: parent.verticalCenter
                size: face.look?.glyph ?? ({ w: 12, h: 14, stroke: 1, path: "" })
                color: face.drag?.glyph ?? "transparent"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 280)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: face.look && face.files.length > 0 ? face.look.name(face.files) : ""
                color: face.drag?.text ?? "transparent"
                font.family: face.look?.font ?? ""
                font.pixelSize: face.drag?.size ?? 12
                font.weight: face.drag?.weight ?? 400
                font.letterSpacing: face.drag?.spacing ?? 0
            }
        }
    }

    // The one-line state as drawn, for `island state`: what heldLive says, the text as it shows (elided or not), and where the clock's right edge sits against the box's.
    function liveDrawn() {
        if (part !== "live" || !heldLive)
            return null;
        return {
            icon: heldLive.icon,
            text: liveText.text,
            elided: liveText.truncated,
            tail: heldLive.tail,
            tone: heldLive.tone,
            ink: String(livePart.ink),
            bar: liveBar.visible ? { pct: heldLive.bar, width: liveBar.width, fill: liveFill.width } : null,
            swatch: heldLive.swatch,
            clock: liveClock.text,
            clockRight: Math.round(livePart.width - (liveClock.x + liveClock.width)),
            clockLeft: Math.round(liveClock.x),
            textRight: Math.round(liveRow.x + liveText.x + liveText.width)
        };
    }

    // The card's name, unlock time and time left as drawn.
    function leaseCardDrawn() {
        return {
            who: cardWhoCard.text,
            elided: cardWhoCard.truncated,
            unlocked: cardUnlockedCard.text,
            time: cardTime.text,
            timeColor: String(cardTime.color)
        };
    }

    // The city column's rows as drawn, for `island state`.
    function citiesDrawn() {
        const rows = [];
        for (let i = 0; i < cityRepeater.count; i++)
            rows.push(cityRepeater.itemAt(i).drawn());
        return rows;
    }

    // The month grid as drawn, for `island state`: the title text, the weekday letters and today's cell.
    function gridDrawn() {
        const weekdays = [];
        for (let i = 0; i < weekdayRepeater.count; i++)
            weekdays.push(weekdayRepeater.itemAt(i).children[0].text);
        let today = null;
        for (let i = 0; i < dayRepeater.count; i++) {
            const cell = dayRepeater.itemAt(i);
            if (cell.todayMark.visible)
                today = { day: cell.dayText.text, width: cell.todayMark.width, height: cell.todayMark.height, filled: cell.todayMark.color.a > 0, border: cell.todayMark.border.width, bold: cell.dayText.font.weight === Font.Bold };
        }
        return {
            title: titleLeft.text,
            weekdays,
            today
        };
    }

    // dots-call sending: the count and machine come once, then the whole send's percent; a percent outside a send is dropped.
    function sendStart(count, to) {
        sending = { count: Math.max(1, parseInt(count) || 1), to: String(to), pct: 0 };
    }

    function sendProgress(pct) {
        if (sending)
            sending = Object.assign({}, sending, { pct: Math.max(0, Math.min(100, parseInt(pct) || 0)) });
    }

    function sendDone() {
        sending = null;
    }

    // dots-call downloading: start names the place in the queue once, progress follows, failed holds its words 5 s whatever starts meanwhile, and done ends the queue without cutting that hold short; a percent outside a download is dropped.
    function downloadStart(n, total, list, title, kind) {
        download = { n: parseInt(n) || 1, total: parseInt(total) || 1, list: String(list), title: String(title), pct: 0, kind: String(kind) };
    }

    function downloadProgress(pct) {
        if (download)
            download = Object.assign({}, download, { pct: Math.max(0, Math.min(100, parseInt(pct) || 0)) });
    }

    function downloadFailed(title, reason) {
        failure = { title: String(title), reason: String(reason) };
        failureTick.restart();
    }

    function downloadDone() {
        download = null;
    }

    // The sharing card's rows as drawn, each with its width against the card's.
    function sharingState() {
        const rows = [];
        for (let i = 0; i < shareRepeater.count; i++)
            rows.push(shareRepeater.itemAt(i).drawn);
        return { rows, inner: shareColumn.width };
    }

    // What the lease card draws, for `island state`; the one-line slot is under live.
    function leaseState() {
        if (mode === "leaseCard")
            return Object.assign({ card: true, label: leaseFrameLabel.visible ? leaseFrameLabel.text : "", bar: leaseLook.card.bar, keys: leaseLook.card.keys.map(k => k.join(" ")).join(" · ") }, leaseCardDrawn());
        return null;
    }

    // Where a notification's parts are drawn, in output pixels, for `island state`.
    function noteState() {
        if (mode !== "notification")
            return null;
        const at = (item) => {
            const p = item.mapToItem(null, 0, 0);
            return { x: p.x, y: p.y, w: item.width, h: item.height };
        };
        const shownChip = columnChip.visible ? columnChip : null;
        return {
            app: noteHead.detailItem.text,
            age: noteHead.clockItem.text,
            summary: noteHead.titleItem.text,
            summaryLines: noteHead.titleItem.lineCount,
            body: body.text,
            cardBottom: card.mapToItem(null, 0, card.height).y,
            boxBottom: box.mapToItem(null, 0, box.height).y,
            summaryFont: [noteHead.titleItem.font.family, noteHead.titleItem.font.pixelSize],
            summaryBox: at(noteHead.titleItem),
            summaryColor: String(noteHead.titleItem.color),
            bodyBox: body.visible ? at(body) : null,
            islandBox: at(box),
            appElided: noteHead.detailItem.truncated,
            appEnd: noteHead.detailItem.mapToItem(null, noteHead.detailItem.width, 0).x,
            ageStart: noteHead.clockItem.mapToItem(null, 0, 0).x,
            clockRight: Math.round(card.width - (noteHead.clockItem.x + noteHead.clockItem.width)),
            tileBox: at(noteHead.circleItem),
            glyph: noteHead.letterItem.visible ? noteHead.letterItem.text : null,
            icon: noteHead.iconImage.visible ? String(noteHead.iconImage.source) : null,
            buttons: noteButtons.visible ? Array.from({ length: actionRepeater.count }, (_, i) => actionRepeater.itemAt(i).drawn) : [],
            bar: noteBar.visible ? noteBar.drawn() : null,
            picture: thumb.visible ? at(thumb) : null,
            chip: shownChip ? shownChip.text : null,
            chipBox: shownChip ? at(shownChip) : null,
            chipEmpty: shownChip ? shownChip.empty : false,
            actions: Array.from({ length: actionRepeater.count }, (_, i) => actionRepeater.itemAt(i).drawn.text),
            actionBoxes: Array.from({ length: actionRepeater.count }, (_, i) => at(actionRepeater.itemAt(i))),
            // The first button's text and fill, which board 2 inverts.
            actionInk: actionRepeater.count ? [actionRepeater.itemAt(0).drawn.ink, actionRepeater.itemAt(0).drawn.fill] : null,
            dragging: noteDragging,
            frame: [box.style.frame.width, String(box.style.frame.color)],
            faceUrl: noteFace.url
        };
    }

    // A pairing request's kind, what has been typed and its keys as drawn, or null.
    function pairingState() {
        if (mode !== "question" || !question.pairing)
            return null;
        return {
            kind: question.pairing,
            pin: pinText.text,
            keys: question.keys.map(k => k.join(" "))
        };
    }

    // Mod+I gives the island the keyboard to act on what it shows; anything but a question gives it back.
    property bool focused: false
    property bool replying: false
    // True while the file picker or slurp has the keyboard for an attachment, which the island takes back after.
    property bool attaching: false
    // Why the last attach found nothing, such as no image on the clipboard; the next key clears it.
    property string askNote: ""
    readonly property var askLinks: Q.linkify(Q.unbidi(heldQuestion?.pairing ? "" : heldQuestion?.text ?? ""))
    readonly property var askFiles: heldQuestion ? questions.attached[heldQuestion.id] ?? [] : []
    readonly property string askFailed: heldQuestion ? questions.failed[heldQuestion.id] ?? "" : ""
    // Where a screenshot or a pasted image is kept until mem has handed it to the hub.
    readonly property string attachDir: Quickshell.env("XDG_RUNTIME_DIR") + "/dots-island-attach"

    // Only an address linkify found is opened, by its index.
    function openLink(index) {
        const url = askLinks.urls[Number(index)];
        if (url)
            Quickshell.execDetached(["xdg-open", url]);
    }

    function pickFiles() {
        attaching = true;
        picker.forId = question.id;
        picker.connected = true;
    }

    function shoot() {
        attaching = true;
        shooter.forId = question.id;
        shooter.file = attachDir + "/" + question.id + "-" + Date.now() + ".png";
        shooter.command = ["sh", "-c", 'mkdir -p "${1%/*}" && r=$(slurp) && grim -g "$r" "$1"', "sh", shooter.file];
        shooter.running = true;
    }

    // An image on the clipboard only; grep reads every type, so wl-paste never dies of SIGPIPE.
    function paste() {
        paster.forId = question.id;
        paster.file = attachDir + "/" + question.id + "-" + Date.now() + ".png";
        paster.command = ["sh", "-c", 'wl-paste --list-types | grep -x image/png >/dev/null && mkdir -p "${1%/*}" && wl-paste -t image/png >"$1"', "sh", paster.file];
        paster.running = true;
    }

    function attachDone() {
        attaching = false;
        if (focused)
            keys.forceActiveFocus();
    }

    // The question card as drawn, for `island state`.
    function askState() {
        if (mode !== "question" || question.pairing)
            return null;
        return {
            expanded: focused,
            replying,
            where: where.text,
            lines: askText.lineCount,
            truncated: askText.truncated,
            summary: askSummary.visible ? askSummary.text : null,
            options: askOptions.visible ? Array.from({ length: askRows.count }, (_, i) => askRows.itemAt(i)?.drawn ?? null) : [],
            links: askLinks.urls,
            attached: askFiles.map(Q.baseName),
            failed: askFailed,
            note: askNote,
            scrolls: askFlick.interactive,
            // The text's top left in the window, which is centred at the top of its output.
            textAt: (p => [Math.round(p.x), Math.round(p.y)])(askText.mapToItem(null, 0, 0)),
            window: width
        };
    }

    function focusIsland() {
        if (cardOpen)
            return;
        if (mode === "lease")
            leaseOpen = true;
        else if (mode === "sharing")
            sharingOpen = true;
        else if (mode === "rest" || mode === "playing") {
            calendar = {
                year: clock.now.getFullYear(),
                month: clock.now.getMonth()
            };
            zones.need();
        } else if (mode !== "question" && mode !== "notification" && mode !== "leaseCard" && mode !== "sharingCard")
            return;
        focused = true;
        keys.forceActiveFocus();
    }

    // A click on the resting island opens what it shows: the media, lease or sharing card, a closed question, the recording app's window, the YouTube App during its download (0WP8K4M3), or the calendar when nothing is live.
    readonly property bool clickable: ["rest", "playing", "lease", "sharing", "mic", "downloading"].indexOf(mode) >= 0 || (mode === "question" && !focused)
    function openActivity() {
        if (mode === "mic") {
            focusRecorder();
        } else if (mode === "downloading") {
            Quickshell.execDetached([Quickshell.env("DOTS_YOUTUBE_APP") || Quickshell.shellDir + "/bin/dots-youtube"]);
        } else if (mode === "playing") {
            mediaOpen = true;
            focused = true;
            keys.forceActiveFocus();
        } else if (clickable) {
            focusIsland();
        }
    }

    // The recording process, then its parent and on up, since chromium records from a child of the process that owns its windows; the answer picks the window. The process is the client's pipewire.sec.pid, which PipeWire sets from the socket; a PulseAudio app's client is pipewire-pulse's socket, so for one its application.process.id stands. pw-dump matches a serial too, so jq takes the object by its id.
    function focusRecorder() {
        if (micClient <= 0)
            return;
        ancestry.running = false;
        ancestry.command = ["sh", "-c", 'p=$(pw-dump "$1" 2>/dev/null | jq -r --argjson c "$1" \'first(.[] | select(.id == $c) | .info.props | if .["client.api"] == "pipewire-pulse" then .["application.process.id"] else .["pipewire.sec.pid"] end) // empty\'); while [ "${p:-0}" -gt 1 ]; do echo "$p"; p=$(awk \'/^PPid:/ { print $2 }\' "/proc/$p/status" 2>/dev/null); done', "sh", String(micClient)];
        ancestry.running = true;
    }

    // A click on an option answers with it as its number key does, and Reply opens the reply line as r does; neither while the reply line or the file picker has the question.
    function clickOption(index) {
        const q = question;
        if (!q || q.pairing || !focused || replying || attaching)
            return;
        askNote = "";
        if (index === Math.min(q.options.length, 9)) {
            replying = true;
            reply.forceActiveFocus();
        } else {
            questions.answer(q.id, q.options[index]);
        }
    }

    // The media card's previous, playPause and next, as the media keys run them.
    function runMedia(key) {
        media[key]();
    }

    // Runs the notification's default action when it has one; either way it leaves the island.
    function openNotification() {
        if (notification)
            notifs.act(notification.key);
        putAway();
    }

    // 1 to 9 runs the chip with that number, which the app dismisses unless the notification is resident.
    function runChip(key) {
        const chip = noteChips.find(c => c.key === key);
        if (chip)
            notifs.runAction(notification.key, chip.identifier);
    }

    // Leaves the island only: the notification stays in the Mod+A history.
    function putAway() {
        if (notification)
            notifs.gone(notification.key);
        release();
    }

    // A capture's Captured or a refusal shows for 1.5 s.
    function showToast(text) {
        toast = text;
        toastTick.restart();
    }

    function showCapture(kind, title, detail) {
        capture = I.captureOf(kind, title, detail);
        toastTick.restart();
    }

    // The wheel over the island turns the volume as the volume keys do (binds.kdl), 5 % a notch; a touchpad's small turns add up to a notch first.
    property real wheelRest: 0
    function wheeled(angle) {
        const t = C.wheelSteps(wheelRest, angle);
        wheelRest = t.rest;
        if (t.steps > 0)
            Quickshell.execDetached(["sh", "-c", `wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ ${5 * t.steps}%+`]);
        else if (t.steps < 0)
            Quickshell.execDetached(["sh", "-c", `wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 && wpctl set-volume @DEFAULT_AUDIO_SINK@ ${-5 * t.steps}%-`]);
    }

    // Where a click area is drawn on the island's output, {x, y, w, h}, or null: the island fills its output from the origin.
    function box(name) {
        return ClickLib.boxJson(island, name);
    }

    function release() {
        focused = false;
        leaseOpen = false;
        sharingOpen = false;
        mediaOpen = false;
        calendar = null;
        replying = false;
        reply.text = "";
        askNote = "";
    }

    // The hub rewrites the file on any change, so only a different question takes the keyboard back.
    readonly property string questionId: question?.id ?? ""
    onQuestionIdChanged: release()

    // The output the island follows, niri's focused one, as the surfaces' window it draws in does.
    readonly property var output: Quickshell.screens.find(s => s.name === niri.focusedOutput) ?? Quickshell.screens[0]
    // Hidden with the margins while the shown window runs edge to edge, as a fullscreen window covers it; an open surface shows over it (BRQAT409).
    visible: !!surface || !niri.edgeToEdge(niri.focusedOutput, output.width)
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    property real fillStartedAt: 0
    property real fillEndedAt: 0
    // The surface open inside the island by name, or null; what waits behind it, a count; and the prompt that took the island over, or null (SCNB8HVY).
    property var surface: null
    // The open surface's size as it asks for it, and the part its content draws in.
    property real surfaceWidth: 0
    property real surfaceHeight: 0
    // True while a card not yet moved into the island is open; the island takes no input then.
    property bool cardOpen: false
    enabled: !cardOpen
    // True while the open surface's rows still fade in.
    property bool surfaceBusy: false
    // When the box and its content last came to rest, in ms since the epoch.
    property real settledAt: 0
    onAnimatingChanged: if (!animating)
        settledAt = Date.now()
    readonly property Item surfaceSlot: surfacePart
    readonly property int waiting: 0
    readonly property var takeover: null
    // The surfaces' window holds the keyboard for the island while this is true; a hidden island takes none, so a fullscreen window keeps its keys.
    readonly property bool wantsKeys: focused && !attaching && visible
    // At rest the surfaces' window takes clicks only on this.
    readonly property Item maskItem: box
    // The island's fill as drawn this frame.
    readonly property color fillColor: fillShape.fill

    Connections {
        target: Root.Pairing
        function onFailed(device) {
            island.showToast("Pairing failed: " + device);
        }
    }

    Connections {
        target: Root.State
        function onToast(text) {
            island.showToast(text);
        }
    }

    Connections {
        target: island.theme
        function onNotice(text) {
            island.notice = text;
            noticeTick.restart();
        }
    }

    Tick {
        interval: 1000
        repeat: true
        running: island.recordingSince > 0
        onTriggered: island.recordingNow = Date.now()
    }

    Tick {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: island.lock.leased
        onTriggered: island.leaseNow = Date.now()
    }

    // A renew moves the end, so the time left reads from now, not from the last tick.
    Connections {
        target: island.lock
        function onLeaseUntilChanged() {
            island.leaseNow = Date.now();
        }
    }

    NumberAnimation {
        id: morphing
        target: island
        property: "progress"
        from: 0
        to: 1
    }

    PwObjectTracker {
        objects: island.captures.concat(island.captureLinks)
    }

    // The shell's own file picker, asked over its socket as bin/dots-portal asks it: one request line, one answer line.
    Socket {
        id: picker
        property string forId: ""
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/dots-picker-" + Quickshell.env("WAYLAND_DISPLAY") + ".sock"
        onConnectedChanged: {
            if (connected) {
                write(JSON.stringify({ mode: "open", multiple: true, title: "Attach to the answer", app: "", folder: Quickshell.env("HOME"), name: "", filters: [], filter: 0, accept: "" }) + "\n");
                flush();
            } else {
                island.attachDone();
            }
        }
        onError: island.attachDone()
        parser: SplitParser {
            onRead: data => {
                let r = null;
                try {
                    r = JSON.parse(data);
                } catch (e) {}
                if (r?.response === 0 && Array.isArray(r.paths) && r.paths.length)
                    island.questions.attach(picker.forId, r.paths);
                picker.connected = false;
            }
        }
    }

    Process {
        id: shooter
        property string forId: ""
        property string file: ""
        // slurp exits non-zero when Esc cancels it, which attaches nothing.
        onExited: code => {
            if (code === 0)
                island.questions.attach(forId, [file]);
            island.attachDone();
        }
    }

    Process {
        id: paster
        property string forId: ""
        property string file: ""
        onExited: code => {
            if (code === 0)
                island.questions.attach(forId, [file]);
            else
                island.askNote = "No image on the clipboard";
        }
    }

    Process {
        id: ancestry
        stdout: StdioCollector {
            onStreamFinished: {
                const id = I.windowFor(island.niri.state.windows, text.split("\n").filter(l => l).map(Number));
                if (id !== null)
                    Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(id)]);
            }
        }
    }

    Process {
        id: comms
        stdout: StdioCollector {
            onStreamFinished: island.watcherNames = I.commNames(text)
        }
    }

    Tick {
        id: toastTick
        interval: 1500
        onTriggered: {
            island.toast = null;
            island.capture = null;
        }
    }

    Tick {
        id: failureTick
        interval: 5000
        onTriggered: island.failure = null
    }

    Tick {
        id: noticeTick
        interval: 5000
        onTriggered: island.notice = ""
    }

    // Artboard's open lease card is a selected frame named Island; the island sits 10 px from the top, so the name goes beside its corner, not above.
    Text {
        id: leaseFrameLabel
        visible: island.mode === "leaseCard" && island.leaseLook.card.label !== ""
        anchors.right: box.left
        anchors.rightMargin: 12
        y: box.y
        textFormat: Text.PlainText
        text: island.leaseLook.card.label
        color: island.theme.tokens?.color.accent ?? "transparent"
        font.family: island.theme.tokens?.type.ui ?? ""
        font.pixelSize: 11
        font.weight: Font.Medium
    }

    // The bottom corners' radius on the box's own progress, 14 at rest and 20 on anything taller.
    readonly property real bottomRadius: progress >= 1 || !curve ? H.bottomRadius(toHeight) : H.bottomRadius(fromHeight, toHeight, I.ease(curve.points, progress))

    // The island's fill: the box joined to the top edge by a concave corner on each side, square to the edge, rounded below, with no frame or shadow.
    Shape {
        id: fillShape
        x: box.x - H.CONCAVE
        y: box.y
        width: box.width + 2 * H.CONCAVE
        height: box.height
        preferredRendererType: Shape.CurveRenderer
        readonly property real r: Math.min(island.bottomRadius, box.height / 2, box.width / 2)
        property color fill: box.style.fill
        // A colorscheme switch crossfades it with the paper, as every surface's fill does; island state reports when the last crossfade began and ended.
        Behavior on fill {
            ColorAnimation {
                duration: Sw.SWITCH.ms * Root.State.slowdown
                easing.type: Easing.InOutSine
                onRunningChanged: running ? island.fillStartedAt = Date.now() : island.fillEndedAt = Date.now()
            }
        }

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: fillShape.fill
            startX: 0
            startY: 0
            PathLine {
                x: fillShape.width
                y: 0
            }
            PathArc {
                x: fillShape.width - H.CONCAVE
                y: H.CONCAVE
                radiusX: H.CONCAVE
                radiusY: H.CONCAVE
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: fillShape.width - H.CONCAVE
                y: fillShape.height - fillShape.r
            }
            PathArc {
                x: fillShape.width - H.CONCAVE - fillShape.r
                y: fillShape.height
                radiusX: fillShape.r
                radiusY: fillShape.r
            }
            PathLine {
                x: H.CONCAVE + fillShape.r
                y: fillShape.height
            }
            PathArc {
                x: H.CONCAVE
                y: fillShape.height - fillShape.r
                radiusX: fillShape.r
                radiusY: fillShape.r
            }
            PathLine {
                x: H.CONCAVE
                y: H.CONCAVE
            }
            PathArc {
                x: 0
                y: 0
                radiusX: H.CONCAVE
                radiusY: H.CONCAVE
                direction: PathArc.Counterclockwise
            }
        }
    }

    Root.Surface {
        id: box
        // Centred on the output, so the box morphs without the window resizing; its top is the output's top row.
        x: Math.round((island.width - width) / 2)
        y: 0
        bare: true
        width: island.progress >= 1 || !island.curve ? island.toWidth : island.fromWidth + (island.toWidth - island.fromWidth) * I.ease(island.curve.points, island.progress)
        height: island.progress >= 1 || !island.curve ? island.toHeight : island.fromHeight + (island.toHeight - island.fromHeight) * I.ease(island.curve.points, island.progress)
        tokens: island.theme.tokens
        role: "island"
        // The open lease card is framed in the accent.
        restyle: island.mode === "leaseCard" ? island.leaseLook.card.box : null

        // Under every part, so a question's scroll and a notification's own area take the pointer first.
        Root.Click {
            name: "island"
            acceptedButtons: island.clickable ? Qt.LeftButton : Qt.NoButton
            cursorShape: island.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onTapped: island.openActivity()
            onWheel: event => island.wheeled(event.angleDelta.y)
        }

        // Each part is drawn at its own size and clipped to the box as it morphs; a one-line part comes in over the close, a card on the open's timing.
        Item {
            anchors.fill: parent
            clip: true

            IslandPart {
                id: labelPart
                shown: island.part === "label"
                key: island.mode
                swap: island.motion?.closeSwap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.label[0]
                height: island.sizes.label[1]

                Text {
                    id: label
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 28)
                    elide: Text.ElideRight
                    text: I.isCompact(island.mode) ? island.text : island.heldText
                    color: box.style.text
                    font.family: island.theme.tokens?.type.mono ?? ""
                    font.pixelSize: 13
                    font.weight: island.mode === "rest" ? Font.Bold : Font.Medium
                }
            }

            // Board 2's one-line state: a 14 px filled icon, the short text, a tail, a pill bar, and the clock pinned right; the danger tone colours all but the clock.
            IslandPart {
                id: livePart
                shown: island.part === "live"
                key: island.mode
                swap: island.motion?.closeSwap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.live[0]
                height: island.sizes.live[1]
                readonly property var s: island.heldLive
                readonly property color ink: s?.tone === "danger" ? island.tones.danger : box.style.text
                readonly property string font: island.theme.tokens?.type.mono ?? ""
                // What the row holds beside the text, each with its gap, so the text's width never reads the row's.
                readonly property real beside: L.LIVE.icon + L.LIVE.gap + (liveSwatch.visible ? L.LIVE.swatch + L.LIVE.gap : 0) + (liveTail.visible ? L.LIVE.gap + liveTail.implicitWidth : 0) + (liveBar.visible ? L.LIVE.gap + L.LIVE.bar : 0)

                Row {
                    id: liveRow
                    x: L.LIVE.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: L.LIVE.gap

                    Text {
                        id: liveIcon
                        width: L.LIVE.icon
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: livePart.s?.icon ?? ""
                        color: livePart.ink
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: L.LIVE.icon
                    }

                    Rectangle {
                        id: liveSwatch
                        visible: (livePart.s?.swatch ?? "") !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: L.LIVE.swatch
                        height: width
                        radius: 4
                        color: livePart.s?.swatch || "transparent"
                    }

                    // Anyone's text, so one line, elided before the clock once the box is at its widest.
                    Text {
                        id: liveText
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        width: Math.min(implicitWidth, livePart.width - 2 * L.LIVE.pad - L.LIVE.clockGap - liveClock.implicitWidth - livePart.beside)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: livePart.s?.text ?? ""
                        color: livePart.ink
                        font.family: livePart.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Text {
                        id: liveTail
                        visible: text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: livePart.s?.tail ?? ""
                        color: livePart.s?.tone === "danger" ? livePart.ink : island.tones.muted
                        font.family: livePart.font
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                    }

                    // The pill bar: a track in the on colour's 14 % and its fill to the percent.
                    Rectangle {
                        id: liveBar
                        visible: livePart.s?.bar !== null && livePart.s?.bar !== undefined
                        anchors.verticalCenter: parent.verticalCenter
                        width: L.LIVE.bar
                        height: 6
                        radius: 3
                        color: Qt.alpha(box.style.text, 0.14)

                        Rectangle {
                            id: liveFill
                            width: Math.round(parent.width * Math.max(0, Math.min(100, livePart.s?.bar ?? 0)) / 100)
                            height: parent.height
                            radius: parent.radius
                            color: livePart.ink
                        }
                    }
                }

                Text {
                    id: liveClock
                    anchors.right: parent.right
                    anchors.rightMargin: L.LIVE.pad
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: livePart.s?.clock ?? ""
                    color: box.style.text
                    font.family: livePart.font
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
            }

            IslandPart {
                id: leaseCardPart
                shown: island.part === "leaseCard"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.leaseCard[0]
                height: island.sizes.leaseCard[1]

                Column {
                    id: leaseColumn
                    // Not named card: the notification's id: card would win the lookup.
                    readonly property var look: island.leaseLook.card
                    readonly property color ink: look.ink || box.style.text
                    readonly property color muted: island.theme.tokens?.color.muted ?? ink
                    readonly property color accent: island.theme.tokens?.color.accent ?? ink
                    readonly property color timeColor: island.leaseWarning ? island.leaseLook.warning.time : ink
                    readonly property string font: island.theme.tokens?.type.ui ?? ""
                    readonly property real share: island.lease && island.lock.leaseUntil > island.lock.unlockedAt ? Math.min(1, island.lease.left / (island.lock.leaseUntil - island.lock.unlockedAt)) : 0
                    width: parent.width

                    // A lock tile, the head, name and unlock time, the time at the right, and the bar.
                    Item {
                        width: parent.width
                        height: cardRow.implicitHeight + 14 + 6 + 30

                        Item {
                            id: cardRow
                            x: 18
                            y: 16
                            width: parent.width - 36
                            implicitHeight: Math.max(40, cardMiddle.implicitHeight, cardRight.implicitHeight)

                            Rectangle {
                                id: cardTile
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                radius: 12
                                color: leaseColumn.look.tile ?? "transparent"

                                Shape {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18

                                    ShapePath {
                                        strokeColor: leaseColumn.ink
                                        strokeWidth: 1.6
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        PathSvg {
                                            path: "M 5.5 8 H 12.5 A 2 2 0 0 1 14.5 10 V 13.5 A 2 2 0 0 1 12.5 15.5 H 5.5 A 2 2 0 0 1 3.5 13.5 V 10 A 2 2 0 0 1 5.5 8 Z M 6 8 V 5.5 A 3 3 0 0 1 11.8 4.5"
                                        }
                                    }
                                }
                            }

                            Column {
                                id: cardMiddle
                                x: 54
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - cardRight.width - 14
                                spacing: 3

                                Text {
                                    textFormat: Text.PlainText
                                    text: leaseColumn.look.head ?? ""
                                    color: leaseColumn.look.headColor || leaseColumn.muted
                                    font.family: leaseColumn.font
                                    font.pixelSize: 12
                                }

                                Text {
                                    id: cardWhoCard
                                    width: parent.width
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    text: leaseColumn.look.who(island.lease?.who ?? "")
                                    color: leaseColumn.ink
                                    font.family: leaseColumn.font
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                }

                                Text {
                                    id: cardUnlockedCard
                                    textFormat: Text.PlainText
                                    text: leaseColumn.look.unlocked(Qt.formatTime(new Date(island.lock.unlockedAt), "HH:mm"))
                                    color: leaseColumn.look.unlockedColor || leaseColumn.muted
                                    font.family: leaseColumn.font
                                    font.pixelSize: 13
                                }
                            }

                            Column {
                                id: cardRight
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    id: cardTime
                                    anchors.right: parent.right
                                    textFormat: Text.PlainText
                                    text: island.leaseLook.time(island.lease?.left ?? 0)
                                    color: leaseColumn.timeColor
                                    font.family: leaseColumn.font
                                    font.pixelSize: 26
                                    font.weight: Font.Bold
                                    font.letterSpacing: -0.5
                                    font.features: { "tnum": 1 }
                                }

                                Text {
                                    anchors.right: parent.right
                                    textFormat: Text.PlainText
                                    text: leaseColumn.look.left ?? ""
                                    color: leaseColumn.look.headColor || leaseColumn.muted
                                    font.family: leaseColumn.font
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Rectangle {
                            x: 18
                            y: cardRow.y + cardRow.height + 14
                            width: parent.width - 36
                            height: 6
                            radius: 3
                            color: leaseColumn.look.tile ?? "transparent"

                            Rectangle {
                                width: parent.width * leaseColumn.share
                                height: parent.height
                                radius: 3
                                color: island.leaseWarning ? island.leaseLook.warning.time : leaseColumn.look.barFill ?? leaseColumn.accent
                            }
                        }
                    }

                    // The keys as chips, under a rule.
                    Item {
                        width: parent.width
                        height: keysRow.implicitHeight + 22

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: leaseColumn.look.tile
                        }

                        Row {
                            id: keysRow
                            x: 18
                            y: 10
                            spacing: 8

                            Repeater {
                                model: leaseColumn.look.keys

                                Rectangle {
                                    required property var modelData
                                    width: keyText.implicitWidth + 14
                                    height: keyText.implicitHeight + 6
                                    radius: 6
                                    color: leaseColumn.look.tile

                                    // The key in ink, then what it does.
                                    Row {
                                        id: keyText
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            textFormat: Text.PlainText
                                            text: parent.parent.modelData[0]
                                            color: leaseColumn.ink
                                            font.family: leaseColumn.font
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            textFormat: Text.PlainText
                                            text: parent.parent.modelData[1]
                                            color: leaseColumn.look.headColor || leaseColumn.muted
                                            font.family: leaseColumn.font
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // One row per share, as plain as the label: its target and who watches, and ↵ stop where Enter can stop it.
            IslandPart {
                id: sharingCardPart
                shown: island.part === "sharingCard"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.sharingCard[0]
                height: island.sizes.sharingCard[1]

                Column {
                    id: shareColumn
                    x: 14
                    y: 12
                    width: parent.width - 28
                    spacing: 8

                    Repeater {
                        id: shareRepeater
                        model: island.heldShareRows

                        Item {
                            id: shareRow
                            required property var modelData
                            readonly property var drawn: ({ text: rowText.text, stop: stopText.visible, lines: rowText.lineCount, elided: rowText.truncated, width: Math.ceil(rowText.width + (stopText.visible ? stopText.width + 12 : 0)) })
                            width: shareColumn.width
                            height: rowText.implicitHeight

                            Text {
                                id: rowText
                                width: parent.width - (stopText.visible ? stopText.implicitWidth + 12 : 0)
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: I.shareRowText(Object.assign({}, shareRow.modelData, { stop: false }))
                                color: box.style.text
                                font.family: island.theme.tokens?.type.mono ?? ""
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            Text {
                                id: stopText
                                anchors.right: parent.right
                                visible: shareRow.modelData.stop
                                textFormat: Text.PlainText
                                text: "↵ stop"
                                color: island.theme.tokens?.color.accent ?? box.style.text
                                font.family: island.theme.tokens?.type.mono ?? ""
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }

            IslandPart {
                id: mediaCardPart
                shown: island.part === "mediaCard"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.mediaCard[0]
                height: island.sizes.mediaCard[1]

                Column {
                    id: mediaColumn
                    x: 14
                    y: 12
                    width: parent.width - 28
                    spacing: 8

                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: I.trackText(island.heldMediaCard ?? {})
                        color: box.style.text
                        font.family: island.theme.tokens?.type.mono ?? ""
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Row {
                        spacing: 18

                        Repeater {
                            model: I.mediaControls(island.heldMediaCard?.playing ?? false)

                            Text {
                                required property var modelData
                                textFormat: Text.PlainText
                                text: modelData.text
                                color: island.noteLook.control.color
                                font.family: island.theme.tokens?.type.mono ?? ""
                                font.pixelSize: 13

                                Root.Click {
                                    name: "media:" + parent.modelData.key
                                    onTapped: island.runMedia(parent.modelData.key)
                                }
                            }
                        }
                    }
                }
            }

            // The open surface's content, laid out at its target size from the first frame so it never reflows mid-morph; the surfaces' window parents it here.
            IslandPart {
                id: surfacePart
                shown: island.part === "surface"
                key: island.surface ?? ""
                swap: island.motion?.swap ?? null
                staggered: true
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.surface[0]
                height: island.sizes.surface[1]
            }

            IslandPart {
                id: notePart
                shown: island.part === "notification"
                key: island.notification?.key ?? ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.notification[0]
                height: island.sizes.notification[1]

                // Board 2's card: the header, the body beside a file chip or picture, the level, then the actions as buttons.
                Column {
                    id: card
                    x: 16
                    y: 16
                    width: parent.width - 2 * x
                    spacing: 8

                    Root.CardHead {
                        id: noteHead
                        width: parent.width
                        image: island.heldNotification?.icon ?? ""
                        letter: island.noteLook.glyph(island.heldNotification?.app ?? "")
                        title: island.noteLook.summaryText(island.heldNotification?.summary ?? "")
                        detail: island.noteLook.appText(island.heldNotification?.app ?? "")
                        clock: island.clockNow
                        ink: box.style.text
                        muted: island.tones.muted
                        danger: island.tones.danger
                        font: island.theme.tokens?.type.mono ?? ""
                    }

                    Row {
                        id: noteContent
                        visible: body.visible || noteBar.visible || columnChip.visible || thumb.visible
                        width: parent.width
                        spacing: 12

                        Column {
                            width: parent.width - (columnChip.visible ? columnChip.width + parent.spacing : 0) - (thumb.visible ? thumb.width + parent.spacing : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                id: body
                                width: parent.width
                                visible: text !== ""
                                text: island.noteLook.bodyText(island.heldNotification?.body ?? "")
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                color: box.style.text
                                font.family: island.theme.tokens?.type.mono ?? ""
                                font.pixelSize: 13
                            }

                            // The value hint, in the bar the OSD draws a volume with.
                            OsdBars {
                                id: noteBar
                                visible: typeof island.heldNotification?.progress === "number"
                                width: parent.width
                                look: island.osdLook
                                value: island.heldNotification?.progress ?? 0
                            }
                        }

                        FileChip {
                            id: columnChip
                            anchors.verticalCenter: parent.verticalCenter
                            width: implicitWidth
                            height: implicitHeight
                            look: island.chipLook
                            at: island.chipLook.toast
                            files: island.heldNotification?.files ?? []
                            empty: island.noteDragging
                        }

                        // The notification's picture, 48 px at the card's right.
                        ClippingRectangle {
                            id: thumb
                            visible: thumbImage.status === Image.Ready
                            anchors.verticalCenter: parent.verticalCenter
                            width: 48
                            height: 48
                            radius: 12
                            color: "transparent"

                            Image {
                                id: thumbImage
                                anchors.fill: parent
                                source: island.heldNotification?.picture ?? ""
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 96
                                sourceSize.height: 96
                            }
                        }
                    }

                    // The actions share the card's width, the first inverted; a notification with none has no row.
                    Row {
                        id: noteButtons
                        visible: island.noteChips.length > 0
                        width: parent.width
                        spacing: 8

                        Repeater {
                            id: actionRepeater
                            model: island.noteChips

                            Root.CardButton {
                                required property var modelData
                                required property int index
                                width: (noteButtons.width - noteButtons.spacing * (actionRepeater.count - 1)) / Math.max(1, actionRepeater.count)
                                text: V.line(modelData.text)
                                primary: index === 0
                                ink: box.style.text
                                fill: box.style.fill
                                font: island.theme.tokens?.type.mono ?? ""
                            }
                        }
                    }
                }

                // Out of sight: the drag image is grabbed from here.
                Item {
                    width: 0
                    height: 0
                    clip: true

                    DragFace {
                        id: noteFace
                        look: island.chipLook
                        files: island.heldNotification?.files ?? []
                    }
                }
            }

            IslandPart {
                id: monthPart
                shown: island.part === "calendar"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.calendar[0]
                height: island.sizes.calendar[1]

                Column {
                    id: month
                    x: 18
                    y: 16
                    width: parent.width - 36
                    spacing: 10

                    // The month, a rule, then the city column.
                    Row {
                        width: parent.width

                        Column {
                            id: monthGrid
                            width: island.clockLook.gridWidth
                            spacing: island.clockLook.grid.gap

                            Item {
                                width: parent.width
                                height: 24

                                Text {
                                    id: titleLeft
                                    readonly property var at: island.clockLook.grid.title.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: island.titleParts[0] ?? ""
                                    color: at.color || box.style.text
                                    font.family: at.font
                                    font.pixelSize: at.size
                                    font.weight: at.weight
                                    font.letterSpacing: at.spacing
                                }
                            }

                            Column {
                                spacing: island.clockLook.grid.rowGap

                                Row {
                                    Repeater {
                                        id: weekdayRepeater
                                        model: island.clockLook.grid.weekdays

                                        Item {
                                            required property string modelData
                                            readonly property var at: island.clockLook.grid.weekday
                                            width: island.clockLook.grid.cell
                                            height: island.clockLook.grid.weekHeight

                                            Text {
                                                id: weekdayText
                                                anchors.centerIn: parent
                                                textFormat: Text.PlainText
                                                text: parent.modelData
                                                color: parent.at.color || box.style.text
                                                font.family: parent.at.font
                                                font.pixelSize: parent.at.size
                                                font.letterSpacing: parent.at.spacing
                                            }
                                        }
                                    }
                                }

                                Grid {
                                    columns: 7

                                    Repeater {
                                        id: dayRepeater
                                        model: island.grid?.cells ?? []

                                        Item {
                                            required property var modelData
                                            readonly property bool isToday: modelData !== null && modelData === island.today
                                            readonly property var at: island.clockLook.grid.day
                                            readonly property var mark: island.clockLook.grid.today
                                            property alias dayText: dayLabel
                                            property alias todayMark: todayBox
                                            width: island.clockLook.grid.cell
                                            height: island.clockLook.grid.rowHeight

                                            Rectangle {
                                                id: todayBox
                                                visible: parent.isToday
                                                anchors.centerIn: parent
                                                width: parent.mark.w
                                                height: parent.mark.h
                                                radius: parent.mark.radius
                                                color: parent.mark.inverted ? parent.mark.fill || box.style.text : "transparent"
                                                border.width: parent.mark.border
                                                border.color: parent.mark.borderColor
                                            }

                                            Text {
                                                id: dayLabel
                                                anchors.centerIn: parent
                                                textFormat: Text.PlainText
                                                text: parent.modelData ?? ""
                                                color: parent.isToday && parent.mark.inverted ? box.style.fill : parent.at.color || box.style.text
                                                font.family: parent.at.font
                                                font.pixelSize: parent.at.size
                                                font.weight: parent.isToday ? Font.Bold : Font.Normal
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // The gap between the month and the cities; no line divides them.
                        Item {
                            width: 2 * island.clockLook.gap + 1
                            height: Math.max(monthGrid.height, cityColumn.height)
                        }

                        Column {
                            id: cityColumn
                            width: month.width - monthGrid.width - 2 * island.clockLook.gap - 1

                            Repeater {
                                id: cityRepeater
                                model: island.cities

                                Item {
                                    id: cityRow
                                    required property var modelData
                                    readonly property var look: island.clockLook
                                    readonly property bool home: modelData.home
                                    width: cityColumn.width
                                    height: Math.max(cityNames.height, cityTime.implicitHeight) + (home ? 8 : 18)

                                    function drawn() {
                                        return {
                                            city: cityName.text,
                                            time: cityTime.text,
                                            offset: offsetUnder.visible ? offsetUnder.text : "",
                                            day: cityDay.visible ? cityDay.text : ""
                                        };
                                    }

                                    Column {
                                        id: cityNames
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: cityRow.home ? -4 : 0
                                        spacing: 1

                                        Item {
                                            width: cityName.implicitWidth
                                            height: cityName.implicitHeight

                                            Text {
                                                id: cityName
                                                readonly property var at: cityRow.home ? cityRow.look.homeLabel : cityRow.look.name
                                                textFormat: Text.PlainText
                                                text: cityRow.look.city(cityRow.modelData.city)
                                                color: at.color || box.style.text
                                                font.family: at.font
                                                font.pixelSize: at.size
                                                font.weight: at.weight
                                                font.letterSpacing: at.spacing
                                            }

                                            Item {
                                                visible: cityRow.home
                                                anchors.left: cityName.right
                                                anchors.verticalCenter: cityName.verticalCenter
                                                width: cityMark.implicitWidth
                                                height: cityMark.implicitHeight

                                                Text {
                                                    id: cityMark
                                                    readonly property var at: cityRow.look.homeLabel
                                                    anchors.centerIn: parent
                                                    textFormat: Text.PlainText
                                                    text: cityRow.look.mark.text
                                                    color: at.color || box.style.text
                                                    font.family: at.font
                                                    font.pixelSize: at.size
                                                    font.letterSpacing: at.spacing
                                                }
                                            }
                                        }

                                        // The day word shows only when the city's day is not home's. A child's visible is false while this row is hidden, so this reads their conditions.
                                        Row {
                                            visible: !cityRow.home || cityRow.modelData.day !== ""
                                            spacing: 6

                                            Text {
                                                id: offsetUnder
                                                visible: !cityRow.home
                                                textFormat: Text.PlainText
                                                text: cityRow.look.offsetText(cityRow.modelData.offset)
                                                color: cityRow.look.offset.color || box.style.text
                                                font.family: cityRow.look.offset.font
                                                font.pixelSize: cityRow.look.offset.size
                                                font.letterSpacing: cityRow.look.offset.spacing
                                            }

                                            Text {
                                                id: cityDay
                                                visible: cityRow.modelData.day !== ""
                                                textFormat: Text.PlainText
                                                text: cityRow.look.dayText(cityRow.modelData.day)
                                                color: cityRow.look.offset.color || box.style.text
                                                font.family: cityRow.look.offset.font
                                                font.pixelSize: cityRow.look.offset.size
                                                font.letterSpacing: cityRow.look.offset.spacing
                                            }
                                        }
                                    }

                                    Text {
                                        id: cityTime
                                        readonly property var at: cityRow.home ? cityRow.look.homeTime : cityRow.look.time
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: cityRow.home ? -4 : 0
                                        textFormat: Text.PlainText
                                        text: cityRow.modelData.time
                                        color: at.color || box.style.text
                                        font.family: at.font
                                        font.pixelSize: at.size
                                        font.weight: at.weight
                                        font.letterSpacing: at.spacing
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        text: "h/l month · Esc"
                        color: Qt.alpha(box.style.text, 0.55)
                        font.family: island.theme.tokens?.type.mono ?? ""
                        font.pixelSize: 11
                    }
                }
            }

            IslandPart {
                id: askPart
                shown: island.part === "question"
                key: island.question?.id ?? ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.question[0]
                height: island.sizes.question[1]

                // A dropped file attaches to the answer, open or closed.
                DropArea {
                    anchors.fill: parent
                    enabled: island.part === "question" && !island.question?.pairing
                    keys: ["text/uri-list"]
                    onDropped: drop => {
                        const paths = drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(p => p.startsWith("/"));
                        if (paths.length && island.question)
                            island.questions.attach(island.question.id, paths);
                        drop.accept(Qt.CopyAction);
                    }
                }

                Flickable {
                    id: askFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: ask.implicitHeight + 32
                    interactive: contentHeight > height
                    clip: interactive
                    boundsBehavior: Flickable.StopAtBounds
                    // A new question, or the card closing, starts at the top.
                    readonly property string at: island.questionId + island.focused
                    onAtChanged: contentY = 0

                    Column {
                        id: ask
                        x: 20
                        y: 16
                        width: askFlick.width - 40
                        spacing: 12

                        Item {
                            width: parent.width
                            height: where.implicitHeight

                            Text {
                                id: where
                                textFormat: Text.PlainText
                                width: parent.width - hint.implicitWidth - 12
                                elide: Text.ElideRight
                                text: [island.heldQuestion?.project, island.heldQuestion?.machine].filter(p => p).map(Q.unbidi).join(" · ")
                                color: Qt.alpha(box.style.text, 0.65)
                                font.family: island.theme.tokens?.type.mono ?? ""
                                font.pixelSize: 11
                            }

                            Text {
                                id: hint
                                textFormat: Text.PlainText
                                anchors.right: parent.right
                                text: island.heldQuestion?.pairing ? "" : island.focused ? "a file · s shot · ^V paste · Esc" : "Mod+I"
                                color: Qt.alpha(box.style.text, 0.65)
                                font.family: island.theme.tokens?.type.mono ?? ""
                                font.pixelSize: 11
                            }
                        }

                        // Two lines until Mod+I opens the card, then all of it; a pairing request is plain text, a question's web addresses are links.
                        Text {
                            id: askText
                            width: parent.width
                            text: island.heldQuestion?.pairing ? island.heldQuestion.text : island.askLinks.html
                            textFormat: island.heldQuestion?.pairing ? Text.PlainText : Text.StyledText
                            wrapMode: Text.Wrap
                            maximumLineCount: island.heldQuestion?.pairing ? 6 : island.focused ? 10000 : 2
                            elide: Text.ElideRight
                            lineHeight: 1.3
                            color: box.style.text
                            linkColor: box.style.text
                            font.family: island.theme.tokens?.type.ui ?? ""
                            font.pixelSize: 15
                            onLinkActivated: link => island.openLink(link)

                            HoverHandler {
                                cursorShape: askText.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                        }

                        Text {
                            id: askSummary
                            visible: !island.heldQuestion?.pairing && !island.focused
                            width: parent.width
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            text: island.heldQuestion ? Q.summary(island.heldQuestion) : ""
                            color: Qt.alpha(box.style.text, 0.8)
                            font.family: island.theme.tokens?.type.ui ?? ""
                            font.pixelSize: 13
                        }

                        // Every option in full, one to a row, the recommended one filled and starred.
                        Column {
                            id: askOptions
                            visible: !island.heldQuestion?.pairing && island.focused && !island.replying
                            width: parent.width
                            spacing: 6

                            Repeater {
                                id: askRows
                                model: (island.heldQuestion?.options ?? []).slice(0, 9).concat(["Reply…"])

                                Rectangle {
                                    required property string modelData
                                    required property int index
                                    readonly property bool isReply: index === Math.min(island.heldQuestion?.options.length ?? 0, 9)
                                    readonly property bool recommended: !isReply && modelData === island.heldQuestion?.recommend
                                    readonly property var drawn: ({ text: optionText.text, recommended, lines: optionText.lineCount, elided: optionText.truncated })
                                    width: parent.width
                                    height: optionText.implicitHeight + 12
                                    radius: 8
                                    color: recommended ? box.style.text : "transparent"
                                    border.width: recommended ? 0 : 1
                                    border.color: Qt.alpha(box.style.text, 0.35)

                                    Text {
                                        id: optionText
                                        x: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 24
                                        textFormat: Text.PlainText
                                        wrapMode: Text.Wrap
                                        text: (parent.isReply ? "r" : parent.index + 1) + " · " + Q.unbidi(parent.modelData) + (parent.recommended ? "  ★" : "")
                                        color: parent.recommended ? box.style.fill : box.style.text
                                        font.family: island.theme.tokens?.type.ui ?? ""
                                        font.pixelSize: 13
                                    }

                                    Root.Click {
                                        name: "ask:option:" + parent.index
                                        onTapped: island.clickOption(parent.index)
                                    }
                                }
                            }
                        }

                        // A pairing request names the keys that answer it in place of options.
                        Flow {
                            width: parent.width
                            spacing: 8
                            visible: !!island.heldQuestion?.pairing

                            Repeater {
                                model: island.heldQuestion?.pairing ? island.heldQuestion.keys.map(k => k.join(" ")) : []

                                Rectangle {
                                    required property string modelData
                                    required property int index
                                    width: Math.min(chip.implicitWidth + 24, ask.width)
                                    height: chip.implicitHeight + 12
                                    radius: 8
                                    color: index === 0 ? box.style.text : "transparent"
                                    border.width: index === 0 ? 0 : 1
                                    border.color: Qt.alpha(box.style.text, 0.35)

                                    Text {
                                        id: chip
                                        textFormat: Text.PlainText
                                        anchors.centerIn: parent
                                        width: Math.min(implicitWidth, parent.width - 24)
                                        elide: Text.ElideRight
                                        text: parent.modelData
                                        color: parent.index === 0 ? box.style.fill : box.style.text
                                        font.family: island.theme.tokens?.type.ui ?? ""
                                        font.pixelSize: 13
                                    }
                                }
                            }
                        }

                        // What goes with the answer, and why the last answer or attach did not go through.
                        Text {
                            visible: island.askFiles.length > 0
                            width: parent.width
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            text: "Attached: " + island.askFiles.map(Q.baseName).join(", ") + (island.focused ? " · x removes" : "")
                            color: Qt.alpha(box.style.text, 0.8)
                            font.family: island.theme.tokens?.type.mono ?? ""
                            font.pixelSize: 11
                        }

                        Text {
                            visible: island.askFailed !== "" || island.askNote !== ""
                            width: parent.width
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            text: island.askNote || "Not sent: " + island.askFailed
                            color: box.style.text
                            font.family: island.theme.tokens?.type.mono ?? ""
                            font.pixelSize: 11
                        }

                        // The PIN or passkey as typed, for a request that asks one.
                        Rectangle {
                            visible: ["pin", "passkey"].indexOf(island.heldQuestion?.pairing) >= 0
                            width: parent.width
                            height: 32
                            radius: 8
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(box.style.text, 0.5)

                            Text {
                                id: pinText
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: Text.AlignVCenter
                                textFormat: Text.PlainText
                                text: Root.Pairing.pin
                                color: box.style.text
                                font.family: island.theme.tokens?.type.mono ?? ""
                                font.pixelSize: 13
                            }
                        }

                        Rectangle {
                            visible: island.replying
                            width: parent.width
                            height: 32
                            radius: 8
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(box.style.text, 0.5)

                            TextInput {
                                id: reply
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: box.style.text
                                font.family: island.theme.tokens?.type.ui ?? ""
                                font.pixelSize: 13
                                Keys.onReturnPressed: {
                                    if (text.trim() !== "" && island.question)
                                        island.questions.answer(island.question.id, text);
                                }
                                Keys.onEscapePressed: {
                                    island.replying = false;
                                    text = "";
                                    keys.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }
        }

        // A click opens a notification and a right click puts it away; the keyboard does the same through Mod+I.
        Root.DragOut {
            id: noteArea
            anchors.fill: parent
            enabled: island.mode === "notification"
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            // A click on an action chip runs that action alone; the area covers the card, so it finds the chip itself.
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    return island.putAway();
                for (let i = 0; i < actionRepeater.count; i++) {
                    const chip = actionRepeater.itemAt(i);
                    if (chip.contains(chip.mapFromItem(noteArea, mouse.x, mouse.y)))
                        return island.runChip(chip.modelData.key);
                }
                island.openNotification();
            }
            // A file notification drags from its chip only; one with no file drags its body from anywhere.
            property bool onChip: false
            readonly property var payload: N.dragPayload(island.heldNotification ?? { body: "" })
            onPressed: mouse => {
                onChip = columnChip.visible && columnChip.contains(columnChip.mapFromItem(noteArea, mouse.x, mouse.y));
                if (onChip)
                    noteFace.grab();
            }
            offering: onChip || payload.mime === "text/plain"
            mime: ({ [payload.mime]: payload.data })
            image: payload.mime === "text/uri-list" ? noteFace.url : ""
        }

        Item {
            id: keys
            focus: island.focused
            Keys.onPressed: event => {
                event.accepted = true;
                if (island.mode === "leaseCard") {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        island.release();
                        island.lock.lockNow();
                    } else if (event.key === Qt.Key_Escape) {
                        island.release();
                    }
                    return;
                }
                if (island.mode === "sharingCard") {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        for (const id of I.stopSessions(island.sharingCard))
                            Quickshell.execDetached(["niri", "msg", "action", "stop-cast", "--session-id", String(id)]);
                        island.release();
                    } else if (event.key === Qt.Key_Escape) {
                        island.release();
                    }
                    return;
                }
                if (island.mode === "mediaCard") {
                    if (event.key === Qt.Key_Escape)
                        island.release();
                    else if (event.key === Qt.Key_H)
                        island.runMedia("previous");
                    else if (event.key === Qt.Key_L)
                        island.runMedia("next");
                    else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        island.runMedia("playPause");
                    return;
                }
                if (island.mode === "calendar") {
                    if (event.key === Qt.Key_Escape)
                        island.release();
                    else if (event.key === Qt.Key_H || event.key === Qt.Key_L)
                        island.calendar = I.shiftMonth(island.calendar.year, island.calendar.month, event.key === Qt.Key_H ? -1 : 1);
                    return;
                }
                if (island.mode === "notification") {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        island.openNotification();
                    else if (event.key === Qt.Key_D || event.key === Qt.Key_Escape)
                        island.putAway();
                    else
                        island.runChip(event.text);
                    return;
                }
                const q = island.question;
                if (!q)
                    return;
                if (q.pairing) {
                    Root.Pairing.key(event);
                    return;
                }
                island.askNote = "";
                if (event.key === Qt.Key_Escape) {
                    island.questions.putAway(q.id);
                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                    island.paste();
                } else if (event.key === Qt.Key_A) {
                    island.pickFiles();
                } else if (event.key === Qt.Key_S) {
                    island.shoot();
                } else if (event.key === Qt.Key_X) {
                    island.questions.detachAll(q.id);
                } else if (event.key === Qt.Key_J || event.key === Qt.Key_K) {
                    askFlick.contentY = Math.max(0, Math.min(askFlick.contentHeight - askFlick.height, askFlick.contentY + (event.key === Qt.Key_J ? 80 : -80)));
                } else if (event.key === Qt.Key_R) {
                    island.replying = true;
                    reply.forceActiveFocus();
                } else {
                    const option = Q.optionFor(q, event.text);
                    if (option !== null)
                        island.questions.answer(q.id, option);
                }
            }
        }
    }
}
