import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "." as Root
import "lib/island.mjs" as I
import "lib/questions.mjs" as Q
import "lib/voice.mjs" as V
import "lib/notifs.mjs" as N
import "lib/worldclock.mjs" as W

// At rest the island is the clock, a Surface box 10 px below the top edge; the window pads for its shadow.
PanelWindow {
    id: island

    required property var theme
    required property var niri
    required property var clock
    // dots-zones's answer for the calendar's city column, run when the calendar first opens.
    required property var zones
    required property var notifs
    required property var questions
    required property var lock
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
    readonly property var notification: notifs.current
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
    readonly property var micApps: I.micApps(captures.map(n => ({
                    id: n.id,
                    capture: true,
                    props: n.properties ?? {}
                })), captureLinks.map(g => ({
                    source: g.source?.id ?? -1,
                    target: g.target?.id ?? -1,
                    active: g.state === PwLinkState.Active
                })), micSource?.id ?? -1, Root.State.recordingPid)
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
    property var heldCapture: null
    onCaptureChanged: {
        if (capture)
            heldCapture = capture;
        holdCaptureNote();
    }
    // Paper's pill, or Artboard's and Blueprint's notification card.
    readonly property var captureLook: V.captureLook(theme.tokens)
    // A Taildrop send, {count, to, pct}, from dots-taildrop-send's start until its done.
    property var sending: null
    readonly property var sendingLook: V.sendingLook(theme.tokens)
    property var playing: null
    // What each part last showed, so a part can leave with its content after its slot has emptied.
    property var heldCalendar: null
    property var heldNotification: null
    property var heldQuestion: null
    property var heldOsd: null
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
    onOsdChanged: if (osd)
        heldOsd = osd
    onTextChanged: if (I.isCompact(mode))
        heldText = text
    Component.onCompleted: heldText = text
    readonly property var slots: ({
            question,
            leaseCard,
            lease,
            calendar,
            sharingCard,
            notification,
            sharing,
            mic,
            recording,
            osd,
            btConnect,
            toast,
            capture,
            sending,
            playing,
            notice
        })
    readonly property string mode: I.pick(slots)
    // When the current mode began, in ms since the epoch, so a check can time a mode without polling error.
    property real modeSince: Date.now()
    onModeChanged: {
        modeSince = Date.now();
        holdCaptureNote();
        // The keyboard goes back once what it was given for is gone, such as a notification whose 5 s ran out.
        if (focused && ["calendar", "question", "notification", "leaseCard", "sharingCard"].indexOf(mode) < 0)
            release();
    }
    // The lease's text is read back from what is drawn, since each theme words it its own way.
    readonly property string text: mode === "sharingCard" ? shareRows.map(I.shareRowText).join(" · ") : mode === "leaseCard" ? (c => [c.who, c.unlocked, c.time].join(" · "))(leaseCardDrawn()) : mode === "lease" ? [leaseLabel.text, leaseWho.text, leaseTime.text].filter(t => t).join(" ") : I.islandText(mode, slots, clock.now)
    // How the theme's board draws a notification and the OSD.
    readonly property var noteLook: V.islandLook(theme.tokens)
    readonly property var chipLook: V.chipLook(theme.tokens)
    // The action chips draw as the legend's key chips, and only while the app still holds the notification.
    readonly property var keyLook: V.listLook(theme.tokens)
    readonly property var noteChips: heldNotification && notifs.live[heldNotification.key] ? N.chipsOf(heldNotification.actions) : []
    // True from a drag's start to its drop; the toast holds while it is. Drag.active falls as the platform drag takes the pointer, so its start and finish set this.
    property bool noteDragging: false
    // The notification's hold waits while the pointer is on the box, Mod+I focuses it or a drag holds it.
    readonly property bool noteHeld: mode === "notification" && (noteArea.containsMouse || focused || noteDragging)
    onNoteHeldChanged: notifs.pause(noteHeld)
    readonly property var osdLook: V.osdLook(theme.tokens)
    // As drawn: the theme's 420 or 440 px notification card, a 560 px question and calendar, and the theme's OSD bar; any other mode is one line as wide as its text.
    readonly property var sizes: ({
            label: [I.boxWidth(Math.ceil(label.implicitWidth) + 28), 34],
            capture: captureLook.card ? [0, 0] : [I.boxWidth(Math.ceil(captureRow.implicitWidth) + 2 * captureLook.pad), captureLook.height],
            lease: [leaseLook.slot.width, leaseLook.slot.height],
            sending: [sendingLook.width, sendingLook.height],
            leaseCard: [leaseLook.card.width, leaseColumn.implicitHeight],
            sharingCard: [noteLook.width, shareColumn.implicitHeight + 24],
            notification: [noteLook.width, card.implicitHeight + noteLook.pad.top + noteLook.pad.bottom],
            question: [I.MAX_WIDTH, ask.implicitHeight + 32],
            calendar: [I.MAX_WIDTH, month.implicitHeight + 32],
            osd: [osdLook.width, osdLook.height]
        })
    // A capture in a card theme draws in the notification's card, but it is no notification: the Mod+A history never hears of it.
    readonly property string part: mode === "capture" ? (captureLook.card ? "notification" : "capture") : ["notification", "question", "calendar", "osd", "lease", "leaseCard", "sharingCard", "sending"].indexOf(mode) < 0 ? "label" : mode
    // The box's size once a morph settles; the margins and `island state` read this, never a size mid-morph.
    readonly property real targetWidth: sizes[part][0]
    readonly property real targetHeight: sizes[part][1]
    readonly property real boxWidth: targetWidth
    readonly property real drawnWidth: box.width
    readonly property var motion: I.islandMotion(theme.tokens?.primitive.motion)
    readonly property bool animating: morphing.running || [labelPart, capturePart, leasePart, sendingPart, leaseCardPart, sharingCardPart, osdPart, notePart, monthPart, askPart].some(p => p.busy)
    // The box morphs from where it is drawn to its target on one clock, so width and height land together.
    property real fromWidth: 0
    property real fromHeight: 0
    property real toWidth: targetWidth
    property real toHeight: targetHeight
    property real progress: 1
    // Picked when a morph starts, since the mode that picks it changes in the same instant as the target.
    property var curve: null
    // The taller of the old and new box while it morphs, so the window resizes twice per morph rather than every frame.
    property real heldHeight: 0
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
            heldHeight = 0;
            toWidth = targetWidth;
            toHeight = targetHeight;
            progress = 1;
            return;
        }
        fromWidth = box.width;
        fromHeight = box.height;
        heldHeight = Math.max(heldHeight, box.height);
        toWidth = targetWidth;
        toHeight = targetHeight;
        curve = I.isCompact(mode) ? motion.close : motion.open;
        morphing.duration = curve.ms;
        progress = 0;
        morphing.restart();
    }
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
    // A chip's outline: a box with Artboard's radius, or Blueprint's frame with its top right corner cut.
    component ChipBack: Item {
        id: chipBack
        property color fill: "transparent"
        property color frame: "transparent"
        property real frameWidth: 1
        property real radius: 0
        property real cut: 0

        Rectangle {
            anchors.fill: parent
            visible: chipBack.cut === 0
            radius: chipBack.radius
            color: chipBack.fill
            border.width: chipBack.frameWidth
            border.color: chipBack.frame
        }
        Shape {
            anchors.fill: parent
            visible: chipBack.cut > 0
            preferredRendererType: Shape.GeometryRenderer

            ShapePath {
                strokeColor: chipBack.frame
                strokeWidth: chipBack.frameWidth
                fillColor: chipBack.fill
                PathPolyline {
                    path: [Qt.point(0.5, 0.5), Qt.point(chipBack.width - 0.5 - chipBack.cut, 0.5), Qt.point(chipBack.width - 0.5, chipBack.cut), Qt.point(chipBack.width - 0.5, chipBack.height - 0.5), Qt.point(0.5, chipBack.height - 0.5), Qt.point(0.5, 0.5)]
                }
            }
        }
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
            cut: fileChip.look?.cut ?? 0
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
        width: faceRow.implicitWidth + (drag ? drag.pad[1] + drag.pad[3] : 0) + (drag?.shadow ? 3 : 0)
        height: faceRow.implicitHeight + (drag ? drag.pad[0] + drag.pad[2] : 0) + (drag?.shadow ? 3 : 0)

        function grab() {
            if (files.length > 0 && width > 0)
                grabToImage(r => face.grabbed = r);
        }

        Rectangle {
            visible: face.drag?.shadow ? true : false
            x: 3
            y: 3
            width: parent.width - 3
            height: parent.height - 3
            color: face.drag?.shadow ?? "transparent"
        }
        ChipBack {
            width: parent.width - (face.drag?.shadow ? 3 : 0)
            height: parent.height - (face.drag?.shadow ? 3 : 0)
            fill: face.drag?.fill ?? "transparent"
            frame: face.drag?.frame ?? "transparent"
            frameWidth: face.drag?.frameWidth ?? 1
            radius: face.drag?.radius ?? 0
            cut: face.drag?.cut ?? 0
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

    // A capture as drawn, for `island state`: in the pill or the card, its title, detail and swatch.
    function captureState() {
        if (mode !== "capture")
            return null;
        const hex = (item) => item.visible ? String(item.color).toUpperCase() : null;
        if (notePart.shown)
            return {
                drawn: "card",
                head: openBracket.visible ? openBracket.text + appName.text + closeBracket.text : appName.text,
                title: summary.text,
                detail: body.text,
                swatch: island.heldNotification?.swatch && tile.visible ? hex(tile) : hex(noteSwatch)
            };
        return {
            drawn: capturePart.shown ? "pill" : null,
            check: captureCheck.visible,
            title: captureTitle.text,
            titleElided: captureTitle.truncated,
            detail: captureDetail.text,
            detailFont: [captureDetail.font.family, captureDetail.font.pixelSize],
            swatch: hex(captureSwatch)
        };
    }

    // A card theme draws the capture as a notification, so the card is handed a note while the capture is what shows; one the card held stays drawn as it leaves.
    function holdCaptureNote() {
        if (capture && mode === "capture" && captureLook.card)
            heldNotification = captureLook.note(capture);
    }

    // What the OSD draws, for `island state`.
    function osdState() {
        if (mode !== "osd")
            return null;
        const p = osdValue.mapToItem(null, 0, 0);
        return {
            word: osdWord.text,
            value: osdValue.text,
            valueFont: [osdValue.font.family, osdValue.font.pixelSize],
            bars: osdLook.bars,
            lit: osdLook.bars === "blocks" ? litBlocks.text.length : osdLook.bars === "bars" ? Array.from({ length: 20 }, (_, i) => barRepeater.itemAt(i)).filter(b => b && b.on).length : Math.round(roundFill.width / roundTrack.width * 20),
            valueBox: { x: p.x + (screen.width - width) / 2, y: p.y, w: osdValue.width, h: osdValue.height }
        };
    }

    // The card's name, unlock time and time left as its layout draws them.
    function leaseCardDrawn() {
        const layout = leaseLook.card.layout;
        const row = i => sheetRepeater.itemAt(i);
        const who = layout === "print" ? cardWhoPrint : layout === "card" ? cardWhoCard : null;
        const time = layout === "print" ? printTime : layout === "card" ? cardTime : null;
        return {
            who: who ? who.text : row(0)?.value ?? "",
            elided: who ? who.truncated : row(0)?.elided ?? false,
            unlocked: layout === "print" ? cardUnlockedPrint.text : layout === "card" ? cardUnlockedCard.text : row(1)?.value ?? "",
            time: time ? time.text : row(2)?.value ?? "",
            timeColor: String(time ? time.color : row(2)?.valueColor ?? "")
        };
    }

    // The city column's rows as drawn, for `island state`.
    function citiesDrawn() {
        const rows = [];
        for (let i = 0; i < cityRepeater.count; i++)
            rows.push(cityRepeater.itemAt(i).drawn());
        return rows;
    }

    // The month grid as drawn, for `island state`: the header and title texts, the weekday letters and today's cell.
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
            header: headerName.visible ? headerName.text : gridHead.visible ? gridHead.text : "",
            title: headerMonth.text !== "" ? headerMonth.text : titleRight.visible ? titleLeft.text + " " + titleRight.text : titleLeft.text,
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

    // What the sending slot draws, for `island state`.
    function sendingState() {
        if (mode !== "sending")
            return null;
        const parts = [];
        let name = null;
        for (let i = 0; i < sendingParts.count; i++) {
            const t = sendingParts.itemAt(i);
            parts.push(t.text);
            if (t.modelData.name)
                name = t;
        }
        return {
            label: parts.join(" "),
            pct: sendingPct.visible ? sendingPct.text : "",
            elided: name ? name.truncated : false,
            lines: name ? name.lineCount : 0,
            barFill: Math.round(sendingFill.width),
            barWidth: Math.round(sendingFill.track.width),
            barHeight: Math.round(sendingFill.height),
            right: Math.round((sendingPct.visible ? sendingPct.mapToItem(sendingPart, sendingPct.width, 0).x : sendingInline.mapToItem(sendingPart, sendingInline.width, 0).x))
        };
    }

    // The sharing card's rows as drawn, each with its width against the card's.
    function sharingState() {
        const rows = [];
        for (let i = 0; i < shareRepeater.count; i++)
            rows.push(shareRepeater.itemAt(i).drawn);
        return { rows, inner: shareColumn.width };
    }

    // What the lease slot and card draw, for `island state`.
    function leaseState() {
        if (mode === "leaseCard")
            return Object.assign({ card: true, layout: leaseLook.card.layout, title: cardTitle.text, label: leaseFrameLabel.visible ? leaseFrameLabel.text : "", handles: box.style.handles, bar: leaseLook.card.bar, keys: leaseLook.card.keys.map(k => k.join(" ")).join(" · ") }, leaseCardDrawn());
        if (mode !== "lease")
            return null;
        return {
            label: leaseLabel.text,
            who: leaseWho.text,
            time: leaseTime.text,
            elided: leaseWho.truncated,
            lines: leaseWho.lineCount,
            timeColor: String(leaseTime.color),
            timeFont: leaseTime.font.family,
            timeRight: Math.round(leaseTimeBox.mapToItem(leasePart, leaseTimeBox.width, 0).x),
            fill: String(box.style.fill),
            frame: String(box.style.frame.color),
            chip: leaseChip.visible ? String(leaseChip.color) : null
        };
    }

    // Where a notification's parts are drawn, in output pixels, for `island state`.
    function noteState() {
        if (mode !== "notification")
            return null;
        const at = (item) => {
            const p = item.mapToItem(null, 0, 0);
            return { x: p.x + (screen.width - width) / 2, y: p.y, w: item.width, h: item.height };
        };
        const bracketEnd = closeBracket.mapToItem(null, closeBracket.width, 0).x;
        const shownChip = bodyChip.visible ? bodyChip : columnChip.visible ? columnChip : null;
        return {
            app: openBracket.visible ? openBracket.text + appName.text + closeBracket.text : appName.text,
            age: age.text,
            summary: summary.text,
            summaryLines: summary.lineCount,
            body: body.text,
            cardBottom: card.mapToItem(null, 0, card.height).y,
            boxBottom: box.mapToItem(null, 0, box.height).y,
            summaryFont: [summary.font.family, summary.font.pixelSize],
            summaryBox: at(summary),
            bracketsShown: openBracket.visible,
            appElided: appName.truncated,
            bracketEnd: bracketEnd,
            ageStart: age.mapToItem(null, 0, 0).x,
            tileBox: tile.visible ? at(tile) : null,
            glyph: tile.visible && glyph.visible ? glyph.text : null,
            chip: shownChip ? shownChip.text : null,
            chipBox: shownChip ? at(shownChip) : null,
            chipEmpty: shownChip ? shownChip.empty : false,
            actions: Array.from({ length: actionRepeater.count }, (_, i) => actionRepeater.itemAt(i).drawn),
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

    // Room for the widest shadow, Artboard's soft one, beside and below the box.
    readonly property int padSide: 32
    readonly property int padBelow: 44
    // Mod+I gives the island the keyboard to act on what it shows; anything but a question gives it back.
    property bool focused: false
    property bool replying: false

    function focusIsland() {
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

    function release() {
        focused = false;
        leaseOpen = false;
        sharingOpen = false;
        calendar = null;
        replying = false;
        reply.text = "";
    }

    // The hub rewrites the file on any change, so only a different question takes the keyboard back.
    readonly property string questionId: question?.id ?? ""
    onQuestionIdChanged: release()

    screen: Quickshell.screens.find(s => s.name === niri.focusedOutput) ?? Quickshell.screens[0]
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dots-island"
    WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    implicitWidth: I.MAX_WIDTH + 2 * padSide
    implicitHeight: box.y + Math.max(targetHeight, heldHeight) + padBelow
    color: "transparent"
    // Only the box takes clicks, not the shadow around it.
    mask: Region {
        item: box
    }

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
        onRunningChanged: if (!running)
            island.heldHeight = 0
    }

    PwObjectTracker {
        objects: island.captures.concat(island.captureLinks)
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

    Root.Surface {
        id: box
        // Centred in a window as wide as the widest card, so the box morphs without the window resizing.
        x: Math.round((island.implicitWidth - width) / 2)
        y: 10
        width: island.progress >= 1 || !island.curve ? island.toWidth : island.fromWidth + (island.toWidth - island.fromWidth) * I.ease(island.curve.points, island.progress)
        height: island.progress >= 1 || !island.curve ? island.toHeight : island.fromHeight + (island.toHeight - island.fromHeight) * I.ease(island.curve.points, island.progress)
        tokens: island.theme.tokens
        role: "island"
        // The lease card's own frame, and the slot's last minute: Paper's sheet and vermilion rule, Blueprint's amber frame and glow.
        restyle: island.mode === "leaseCard" ? island.leaseLook.card.box : island.mode === "lease" && island.leaseWarning ? island.leaseLook.warning.box : island.mode === "notification" && island.noteDragging && island.chipLook.frame ? { frame: island.chipLook.frame } : null

        // Each part is drawn at its own size and clipped to the box as it morphs.
        Item {
            anchors.fill: parent
            clip: true

            IslandPart {
                id: labelPart
                shown: island.part === "label"
                key: island.mode
                swap: island.motion?.swap ?? null
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
                    font.weight: Font.Medium
                }
            }

            // Paper's capture pill: a check for what was copied, the title in caps, a colour's swatch, then the count or the hex; a miss draws only its muted words.
            IslandPart {
                id: capturePart
                shown: island.part === "capture"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.capture[0]
                height: island.sizes.capture[1]

                Row {
                    id: captureRow
                    readonly property var look: island.captureLook
                    readonly property var detailLook: !look.card && island.heldCapture ? look.detail(island.heldCapture) : null
                    // What the title and detail may take once the check and swatch have theirs; a long title leaves the detail half.
                    readonly property real room: I.MAX_WIDTH - 2 * (look.pad ?? 0) - (captureCheck.visible ? captureCheck.width + spacing : 0) - (captureSwatch.visible ? captureSwatch.width + spacing : 0) - (captureTitle.visible && captureDetail.visible ? spacing : 0)
                    anchors.centerIn: parent
                    spacing: look.gap ?? 0

                    Shape {
                        id: captureCheck
                        visible: (island.heldCapture?.title ?? "") !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: captureRow.look.check ?? 0
                        height: width
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: box.style.text
                            strokeWidth: 1.6
                            fillColor: "transparent"
                            PathSvg {
                                path: "M2 6.5l2.5 2.5L10 3.5"
                            }
                        }
                    }

                    Text {
                        id: captureTitle
                        visible: text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, captureDetail.visible ? captureRow.room / 2 : captureRow.room)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: captureRow.look.card ? "" : captureRow.look.titleText(island.heldCapture?.title ?? "")
                        color: box.style.text
                        font.family: captureRow.look.title?.font ?? ""
                        font.pixelSize: captureRow.look.title?.size ?? 10
                        font.letterSpacing: captureRow.look.title?.spacing ?? 0
                    }

                    // A light outline, so a dark colour still reads on the island.
                    Rectangle {
                        id: captureSwatch
                        visible: !!island.heldCapture?.swatch
                        anchors.verticalCenter: parent.verticalCenter
                        width: captureRow.look.swatch ?? 0
                        height: width
                        color: island.heldCapture?.swatch ?? "transparent"
                        border.width: 1
                        border.color: box.style.text
                    }

                    Text {
                        id: captureDetail
                        visible: text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, captureRow.room - (captureTitle.visible ? captureTitle.width : 0))
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: island.heldCapture?.detail ?? ""
                        color: captureRow.detailLook?.color || box.style.text
                        font.family: captureRow.detailLook?.font ?? ""
                        font.pixelSize: captureRow.detailLook?.size ?? 12
                        font.weight: captureRow.detailLook?.weight ?? Font.Normal
                        font.letterSpacing: captureRow.detailLook?.spacing ?? 0
                        font.italic: captureRow.detailLook?.italic ?? false
                    }
                }
            }

            IslandPart {
                id: leasePart
                shown: island.part === "lease"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.lease[0]
                height: island.sizes.lease[1]

                // The mark, the label and the holder from the left, the time at the right edge, as the boards draw the slot.
                Row {
                    id: leaseRow
                    readonly property var slot: island.leaseLook.slot
                    readonly property var warn: island.leaseWarning ? island.leaseLook.warning : null
                    x: slot.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: slot.gap

                    // Artboard's last minute rings its dot in the chip's colour.
                    Rectangle {
                        visible: leaseRow.slot.mark !== null
                        anchors.verticalCenter: parent.verticalCenter
                        width: leaseRow.warn?.ring ? 16 : leaseRow.slot.mark?.size ?? 0
                        height: width
                        radius: leaseRow.slot.mark?.shape === "dot" ? width / 2 : 0
                        color: leaseRow.warn?.ring || "transparent"

                        Rectangle {
                            anchors.centerIn: parent
                            width: leaseRow.slot.mark?.size ?? 0
                            height: width
                            radius: leaseRow.slot.mark?.shape === "dot" ? width / 2 : 0
                            color: leaseRow.warn?.mark || leaseRow.slot.mark?.color || "transparent"
                        }
                    }

                    Text {
                        id: leaseLabel
                        visible: text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: leaseRow.slot.label.text
                        color: leaseRow.warn?.label || leaseRow.slot.label.color || box.style.text
                        font.family: leaseRow.slot.label.font
                        font.pixelSize: leaseRow.slot.label.size
                        font.letterSpacing: leaseRow.slot.label.spacing
                    }

                    // A holder's name is anyone's text: one line, elided before the time.
                    Text {
                        id: leaseWho
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        width: Math.min(implicitWidth, leasePart.width - 2 * leaseRow.slot.pad - leaseRow.spacing * (leaseLabel.visible ? 3 : 2) - (leaseRow.slot.mark ? 16 : 0) - (leaseLabel.visible ? leaseLabel.width : 0) - leaseTimeBox.width)
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: leaseRow.slot.who.text(island.lease?.who ?? "")
                        color: leaseRow.slot.who.color || box.style.text
                        font.family: leaseRow.slot.who.font
                        font.pixelSize: leaseRow.slot.who.size
                        font.weight: leaseRow.slot.who.weight
                        font.letterSpacing: leaseRow.slot.who.spacing
                    }
                }

                Item {
                    id: leaseTimeBox
                    anchors.right: parent.right
                    anchors.rightMargin: leaseRow.slot.pad
                    anchors.verticalCenter: parent.verticalCenter
                    width: leaseTime.implicitWidth + (leaseChip.visible ? 16 : 0)
                    height: leaseTime.implicitHeight + (leaseChip.visible ? 4 : 0)

                    // Artboard's last minute puts the time in a chip.
                    Rectangle {
                        id: leaseChip
                        visible: (leaseRow.warn?.chip ?? "") !== ""
                        anchors.fill: parent
                        radius: 8
                        color: leaseRow.warn?.chip || "transparent"
                    }

                    Text {
                        id: leaseTime
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: island.leaseLook.time(island.lease?.left ?? 0)
                        color: leaseRow.warn?.time || leaseRow.slot.time.color || box.style.text
                        font.family: leaseRow.slot.time.font
                        font.pixelSize: leaseRow.slot.time.size
                        font.weight: leaseRow.slot.time.weight
                        font.letterSpacing: leaseRow.slot.time.spacing
                        font.features: { "tnum": 1 }
                    }
                }
            }

            IslandPart {
                id: sendingPart
                shown: island.part === "sending"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.sending[0]
                height: island.sizes.sending[1]
                readonly property var look: island.sendingLook
                // What the parts other than the machine's name take, so that one elides into what is left; an inline bar keeps 40 px.
                readonly property real fixed: 2 * look.pad + (look.mark ? look.mark.size + look.gap : 0) + (look.pct ? sendingPct.implicitWidth + look.gap : 0) + (look.bar.at === "inline" ? 40 + look.gap : 0) + sendingParts.fixedWidth

                // The mark and the words from the left, the percent at the right edge, and the bar after the words or along the bottom, as each board draws the slot.
                Row {
                    id: sendingRow
                    x: sendingPart.look.pad
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: sendingPart.look.bar.at === "bottom" ? -sendingPart.look.bar.height / 2 : 0
                    spacing: sendingPart.look.gap

                    Item {
                        visible: sendingPart.look.mark !== null
                        anchors.verticalCenter: parent.verticalCenter
                        width: sendingPart.look.mark?.size ?? 0
                        height: width

                        Rectangle {
                            visible: sendingPart.look.mark?.shape !== "upload"
                            anchors.fill: parent
                            color: sendingPart.look.mark?.color || box.style.text
                        }

                        // Artboard's board draws an arrow up out of a tray.
                        Shape {
                            visible: sendingPart.look.mark?.shape === "upload"
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: sendingPart.look.mark?.color || box.style.text
                                strokeWidth: 1.6
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin
                                scale: Qt.size((sendingPart.look.mark?.size ?? 16) / 16, (sendingPart.look.mark?.size ?? 16) / 16)
                                PathSvg {
                                    path: "M8 11.5V3.5m-3.2 3.2L8 3.5l3.2 3.2M3 13.5h10"
                                }
                            }
                        }
                    }

                    Repeater {
                        id: sendingParts
                        model: sendingPart.look.parts
                        readonly property real fixedWidth: widthOf(false)
                        readonly property real nameWidth: widthOf(true)

                        function widthOf(name) {
                            let w = 0;
                            for (let i = 0; i < count; i++) {
                                const t = itemAt(i);
                                if (t && t.modelData.name === name)
                                    w += name ? t.width : t.implicitWidth + sendingPart.look.gap;
                            }
                            return w;
                        }

                        // The machine's name comes from the tailnet: one line, and its part elides before the rest.
                        Text {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            width: modelData.name ? Math.max(0, Math.min(implicitWidth, sendingPart.width - sendingPart.fixed)) : implicitWidth
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: modelData.text(island.sending?.count ?? 0, island.sending?.to ?? "", island.sending?.pct ?? 0)
                            color: modelData.color || box.style.text
                            font.family: modelData.font
                            font.pixelSize: modelData.size
                            font.weight: modelData.weight
                            font.letterSpacing: modelData.spacing
                        }
                    }

                    Rectangle {
                        id: sendingInline
                        visible: sendingPart.look.bar.at === "inline"
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? Math.max(40, 40 + sendingPart.width - sendingPart.fixed - sendingParts.nameWidth) : 0
                        height: sendingPart.look.bar.height
                        radius: sendingPart.look.bar.radius
                        color: sendingPart.look.bar.track
                    }
                }

                Text {
                    id: sendingPct
                    visible: sendingPart.look.pct !== null
                    anchors.right: parent.right
                    anchors.rightMargin: sendingPart.look.pad
                    anchors.verticalCenter: sendingRow.verticalCenter
                    textFormat: Text.PlainText
                    text: sendingPart.look.pct ? sendingPart.look.pct.text(island.sending?.pct ?? 0) : ""
                    color: sendingPart.look.pct?.color || box.style.text
                    font.family: sendingPart.look.pct?.font ?? ""
                    font.pixelSize: sendingPart.look.pct?.size ?? 12
                    font.weight: sendingPart.look.pct?.weight ?? Font.Normal
                    font.letterSpacing: sendingPart.look.pct?.spacing ?? 0
                    font.features: { "tnum": 1 }
                }

                Rectangle {
                    id: sendingBottom
                    visible: sendingPart.look.bar.at === "bottom"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: sendingPart.look.bar.height
                    color: sendingPart.look.bar.track
                }

                // The fill sits on whichever track this theme draws.
                Rectangle {
                    id: sendingFill
                    readonly property Item track: sendingPart.look.bar.at === "inline" ? sendingInline : sendingBottom
                    x: track.mapToItem(sendingPart, 0, 0).x
                    y: track.mapToItem(sendingPart, 0, 0).y
                    width: track.width * (island.sending?.pct ?? 0) / 100
                    height: track.height
                    radius: sendingPart.look.bar.radius
                    color: sendingPart.look.bar.fill
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

                // One card in three layouts, each as its board draws it: Paper's print, Artboard's card, Blueprint's sheet.
                Column {
                    id: leaseColumn
                    // Not named card: the notification's id: card would win the lookup.
                    readonly property var look: island.leaseLook.card
                    readonly property string layout: look.layout
                    readonly property color ink: look.ink || box.style.text
                    readonly property color muted: island.theme.tokens?.color.muted ?? ink
                    readonly property color accent: island.theme.tokens?.color.accent ?? ink
                    readonly property color timeColor: island.leaseWarning ? island.leaseLook.warning.time : layout === "sheet" ? accent : ink
                    readonly property string font: island.theme.tokens?.type.ui ?? ""
                    readonly property string display: island.theme.tokens?.type.display ?? ""
                    readonly property real share: island.lease && island.lock.leaseUntil > island.lock.unlockedAt ? Math.min(1, island.lease.left / (island.lock.leaseUntil - island.lock.unlockedAt)) : 0
                    width: parent.width

                    // The head: Paper's square, AGENT and LEASE; Blueprint's [ AGENT ], LEASE and its title.
                    Item {
                        visible: leaseColumn.layout !== "card"
                        width: parent.width
                        height: visible ? headColumn.implicitHeight + (leaseColumn.layout === "print" ? 23 : 24) : 0

                        Column {
                            id: headColumn
                            x: leaseColumn.layout === "print" ? 15 : 18
                            y: leaseColumn.layout === "print" ? 11 : 12
                            width: parent.width - 2 * x
                            spacing: 4

                            Item {
                                width: parent.width
                                height: headLeft.implicitHeight

                                Row {
                                    id: headLeft
                                    spacing: 8

                                    Rectangle {
                                        visible: leaseColumn.layout === "print"
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 8
                                        height: 8
                                        color: leaseColumn.accent
                                    }

                                    Text {
                                        textFormat: Text.PlainText
                                        text: leaseColumn.layout === "print" ? "AGENT" : "[ AGENT ]"
                                        color: leaseColumn.look.headColor || leaseColumn.muted
                                        font.family: leaseColumn.font
                                        font.pixelSize: 10
                                        font.letterSpacing: leaseColumn.layout === "print" ? 1.4 : 1.6
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    textFormat: Text.PlainText
                                    text: "LEASE"
                                    color: leaseColumn.look.headColor || leaseColumn.muted
                                    font.family: leaseColumn.font
                                    font.pixelSize: 10
                                    font.letterSpacing: leaseColumn.layout === "print" ? 1.4 : 1.6
                                }
                            }

                            Text {
                                id: cardTitle
                                visible: leaseColumn.layout === "sheet"
                                width: parent.width
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                text: leaseColumn.layout === "sheet" ? leaseColumn.look.title(island.lease?.who ?? "") : ""
                                color: leaseColumn.accent
                                font.family: leaseColumn.font
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                font.letterSpacing: 0.6
                            }

                            // Paper: the name in serif with when it unlocked, and LEFT with the time large at the right.
                            Item {
                                visible: leaseColumn.layout === "print"
                                width: parent.width
                                height: visible ? Math.max(printLeft.implicitHeight, printRight.implicitHeight) + 4 : 0

                                Column {
                                    id: printLeft
                                    anchors.bottom: parent.bottom
                                    width: parent.width - printRight.width - 16
                                    spacing: 4

                                    Text {
                                        id: cardWhoPrint
                                        width: parent.width
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        text: leaseColumn.look.who(island.lease?.who ?? "")
                                        color: leaseColumn.ink
                                        font.family: leaseColumn.display
                                        font.pixelSize: 24
                                    }

                                    Text {
                                        id: cardUnlockedPrint
                                        textFormat: Text.PlainText
                                        text: leaseColumn.look.unlocked(Qt.formatTime(new Date(island.lock.unlockedAt), "HH:mm"))
                                        color: leaseColumn.look.unlockedColor || leaseColumn.muted
                                        font.family: leaseColumn.font
                                        font.pixelSize: 12
                                    }
                                }

                                Row {
                                    id: printRight
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    spacing: 8

                                    Text {
                                        anchors.baseline: printTime.baseline
                                        textFormat: Text.PlainText
                                        text: leaseColumn.look.left ?? ""
                                        color: leaseColumn.look.headColor || leaseColumn.muted
                                        font.family: leaseColumn.font
                                        font.pixelSize: 10
                                        font.letterSpacing: 1.4
                                    }

                                    Text {
                                        id: printTime
                                        textFormat: Text.PlainText
                                        text: island.leaseLook.time(island.lease?.left ?? 0)
                                        color: leaseColumn.timeColor
                                        font.family: leaseColumn.display
                                        font.pixelSize: 44
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }
                        }
                    }

                    // Artboard: a lock tile, the head, name and unlock time, the time at the right, and the bar.
                    Item {
                        visible: leaseColumn.layout === "card"
                        width: parent.width
                        height: visible ? cardRow.implicitHeight + 14 + 6 + 30 : 0

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

                    // Blueprint: WHO, SINCE and LEFT rows and a bar of blocks, between dashed rules.
                    Item {
                        visible: leaseColumn.layout === "sheet"
                        width: parent.width
                        height: visible ? sheetRows.implicitHeight + 24 : 0

                        Root.Dashed {
                            width: parent.width
                            height: 1
                            color: island.theme.tokens?.color.line ?? leaseColumn.muted
                        }

                        Column {
                            id: sheetRows
                            x: 18
                            y: 12
                            width: parent.width - 36
                            spacing: 8

                            Repeater {
                                id: sheetRepeater
                                model: leaseColumn.layout === "sheet" ? [["WHO", "who"], ["SINCE", "since"], ["LEFT", "left"]] : []

                                Item {
                                    required property var modelData
                                    readonly property string value: rowValue.text
                                    readonly property bool elided: rowValue.truncated
                                    readonly property color valueColor: rowValue.color
                                    width: sheetRows.width
                                    height: rowValue.implicitHeight

                                    Text {
                                        anchors.baseline: rowValue.baseline
                                        textFormat: Text.PlainText
                                        text: parent.modelData[0]
                                        color: leaseColumn.muted
                                        font.family: leaseColumn.font
                                        font.pixelSize: 10
                                        font.letterSpacing: 1.6
                                    }

                                    Text {
                                        id: rowValue
                                        anchors.right: parent.right
                                        width: Math.min(implicitWidth, parent.width - 60)
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        readonly property string kind: parent.modelData[1]
                                        text: kind === "who" ? leaseColumn.look.who(island.lease?.who ?? "") : kind === "since" ? leaseColumn.look.unlocked(Qt.formatTime(new Date(island.lock.unlockedAt), "HH:mm")) : island.leaseLook.time(island.lease?.left ?? 0)
                                        color: kind === "left" ? leaseColumn.timeColor : leaseColumn.ink
                                        font.family: leaseColumn.font
                                        font.pixelSize: 12
                                        font.weight: kind === "left" ? Font.Bold : Font.Normal
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }

                            Row {
                                readonly property int lit: Math.ceil(leaseColumn.share * 20)

                                Text {
                                    textFormat: Text.PlainText
                                    text: "▮".repeat(parent.lit)
                                    color: island.leaseWarning ? island.leaseLook.warning.time : leaseColumn.accent
                                    font.family: leaseColumn.font
                                    font.pixelSize: 12
                                    font.letterSpacing: 0.6
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    text: "▮".repeat(20 - parent.lit)
                                    color: island.theme.tokens?.color.line ?? leaseColumn.muted
                                    font.family: leaseColumn.font
                                    font.pixelSize: 12
                                    font.letterSpacing: 0.6
                                }
                            }
                        }
                    }

                    // The keys, under a rule: Paper's paper-coloured line, Artboard's chips, Blueprint's dashes.
                    Item {
                        width: parent.width
                        height: keysRow.implicitHeight + (leaseColumn.layout === "print" ? 18 : 22)

                        Rectangle {
                            visible: leaseColumn.layout !== "sheet"
                            width: parent.width
                            height: 1
                            color: leaseColumn.layout === "print" ? leaseColumn.ink : leaseColumn.look.tile ?? "transparent"
                        }

                        Root.Dashed {
                            visible: leaseColumn.layout === "sheet"
                            width: parent.width
                            height: 1
                            color: island.theme.tokens?.color.line ?? leaseColumn.muted
                        }

                        Row {
                            id: keysRow
                            x: leaseColumn.layout === "print" ? 15 : 18
                            y: leaseColumn.layout === "print" ? 9 : 10
                            spacing: leaseColumn.layout === "card" ? 8 : 14

                            Repeater {
                                model: leaseColumn.look.keys

                                Rectangle {
                                    required property var modelData
                                    readonly property bool tiled: leaseColumn.layout === "card"
                                    width: keyText.implicitWidth + (tiled ? 14 : 0)
                                    height: keyText.implicitHeight + (tiled ? 6 : 0)
                                    radius: 6
                                    color: tiled ? leaseColumn.look.tile : "transparent"

                                    // The key bold in ink, or Blueprint's accent, then what it does.
                                    Row {
                                        id: keyText
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            textFormat: Text.PlainText
                                            text: parent.parent.modelData[0]
                                            color: leaseColumn.layout === "sheet" ? leaseColumn.accent : leaseColumn.ink
                                            font.family: leaseColumn.font
                                            font.pixelSize: parent.parent.tiled ? 11 : 10
                                            font.weight: parent.parent.tiled ? Font.Medium : Font.Bold
                                        }

                                        Text {
                                            textFormat: Text.PlainText
                                            text: parent.parent.modelData[1]
                                            color: leaseColumn.look.headColor || leaseColumn.muted
                                            font.family: leaseColumn.font
                                            font.pixelSize: parent.parent.tiled ? 11 : 10
                                            font.letterSpacing: parent.parent.tiled ? 0 : 1.2
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
                id: osdPart
                shown: island.part === "osd"
                key: ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.osd[0]
                height: island.sizes.osd[1]

                // The word or glyph, the bar and the value, as each theme's volume board draws them.
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: island.osdLook.voice === "caps" ? 14 : 16
                    anchors.rightMargin: anchors.leftMargin
                    spacing: island.osdLook.voice === "plain" ? 12 : 10

                    Text {
                        id: osdWord
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: island.osdLook.word(island.heldOsd?.kind ?? "volume")
                        color: island.osdLook.label?.color || box.style.text
                        font.family: island.osdLook.label?.font ?? ""
                        font.pixelSize: island.osdLook.label?.size ?? 10
                        font.letterSpacing: island.osdLook.label?.spacing ?? 0
                    }

                    // A speaker for volume, a sun for brightness, drawn as 16 px strokes in the text colour.
                    Shape {
                        visible: island.osdLook.word("volume") === ""
                        implicitWidth: 16
                        implicitHeight: 16

                        ShapePath {
                            strokeColor: box.style.text
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin

                            PathSvg {
                                path: island.heldOsd?.kind === "brightness"
                                    ? "M 11 8 A 3 3 0 1 1 5 8 A 3 3 0 1 1 11 8 M 8 1 L 8 2.5 M 8 13.5 L 8 15 M 1 8 L 2.5 8 M 13.5 8 L 15 8 M 3 3 L 4 4 M 12 12 L 13 13 M 3 13 L 4 12 M 12 4 L 13 3"
                                    : "M 2 6 L 5 6 L 9 2.5 L 9 13.5 L 5 10 L 2 10 Z M 11.5 5.5 Q 13 8 11.5 10.5 M 13.5 3.5 Q 16 8 13.5 12.5"
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 14
                        readonly property int lit: island.osdLook.litCount(island.heldOsd?.value ?? 0)

                        // Paper: 20 bars, the lit ones tall in the accent.
                        Row {
                            visible: island.osdLook.bars === "bars"
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Repeater {
                                id: barRepeater
                                model: 20

                                Rectangle {
                                    required property int index
                                    readonly property bool on: index < parent.parent.lit
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 4
                                    height: on ? 14 : 8
                                    color: on ? island.osdLook.lit.color : island.osdLook.unlit.color
                                }
                            }
                        }

                        // Blueprint: a run of ▮ blocks, the unlit ones in the line colour.
                        Row {
                            visible: island.osdLook.bars === "blocks"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: litBlocks
                                textFormat: Text.PlainText
                                text: "▮".repeat(parent.parent.lit)
                                color: island.osdLook.lit.color
                                font.family: island.osdLook.value.font
                                font.pixelSize: 12
                                font.letterSpacing: 0.6
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: "▮".repeat(20 - parent.parent.lit)
                                color: island.osdLook.unlit.color
                                font.family: island.osdLook.value.font
                                font.pixelSize: 12
                                font.letterSpacing: 0.6
                            }
                        }

                        // Artboard: one rounded bar.
                        Rectangle {
                            id: roundTrack
                            visible: island.osdLook.bars === "round"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: island.osdLook.unlit.color

                            Rectangle {
                                id: roundFill
                                width: parent.width * Math.min(Math.max(island.heldOsd?.value ?? 0, 0), 100) / 100
                                height: parent.height
                                radius: parent.radius
                                color: island.osdLook.lit.color
                            }
                        }
                    }

                    Text {
                        id: osdValue
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignRight
                        text: island.heldOsd ? island.osdLook.valueText(island.heldOsd.value) : ""
                        color: island.osdLook.value.color || box.style.text
                        font.family: island.osdLook.value.font
                        font.pixelSize: island.osdLook.value.size
                        font.weight: island.osdLook.value.weight
                    }
                }
            }

            IslandPart {
                id: notePart
                shown: island.part === "notification"
                key: island.notification?.key ?? ""
                swap: island.motion?.swap ?? null
                x: Math.round((parent.width - width) / 2)
                width: island.sizes.notification[0]
                height: island.sizes.notification[1]

                // Artboard's icon tile, then the app and its age over the summary and body.
                Row {
                    id: card
                    x: island.noteLook.pad.x
                    y: island.noteLook.pad.top
                    width: parent.width - 2 * x
                    spacing: 14

                    Rectangle {
                        id: tile
                        visible: island.noteLook.tile !== null
                        width: island.noteLook.tile?.size ?? 0
                        height: width
                        radius: island.noteLook.tile?.radius ?? 0
                        // Artboard's board fills the tile with a picked colour, ringed in white at 28 %.
                        color: island.heldNotification?.swatch ?? island.noteLook.tile?.fill ?? "transparent"
                        border.width: island.heldNotification?.swatch ? 1.5 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.28)
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            id: icon
                            anchors.centerIn: parent
                            visible: source != ""
                            source: tile.visible ? island.heldNotification?.icon ?? "" : ""
                            sourceSize.width: 24
                            sourceSize.height: 24
                        }

                        Text {
                            id: glyph
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            // An icon that is missing or fails to load leaves the letter.
                            visible: icon.status !== Image.Ready && !island.heldNotification?.swatch
                            text: island.noteLook.glyph(island.heldNotification?.app ?? "")
                            color: box.style.text
                            font.family: island.theme.tokens?.type.mono ?? ""
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                    }

                    Column {
                        width: parent.width - (tile.visible ? tile.width + parent.spacing : 0) - (columnChip.visible ? columnChip.width + parent.spacing : 0)
                        spacing: island.noteLook.voice === "plain" ? 2 : 4

                        Item {
                            width: parent.width
                            height: age.implicitHeight

                            // Blueprint's brackets stay drawn around a long name, which elides inside them.
                            Row {
                                id: appRow
                                readonly property real room: parent.width - age.implicitWidth - 12

                                HeadText {
                                    id: openBracket
                                    visible: island.noteLook.brackets && appName.text !== ""
                                    text: "[ "
                                }
                                HeadText {
                                    id: appName
                                    width: Math.min(implicitWidth, Math.max(0, appRow.room - (openBracket.visible ? openBracket.implicitWidth + closeBracket.implicitWidth : 0)))
                                    elide: Text.ElideRight
                                    text: island.noteLook.appText(island.heldNotification?.app ?? "")
                                }
                                HeadText {
                                    id: closeBracket
                                    visible: openBracket.visible
                                    text: " ]"
                                }
                            }

                            HeadText {
                                id: age
                                anchors.right: parent.right
                                // Blueprint's board says DRAGGING here, bold in the accent, while the chip is out.
                                readonly property bool dragWord: island.noteDragging && island.chipLook.dragAge !== ""
                                text: dragWord ? island.chipLook.dragAge : island.noteLook.age
                                color: dragWord ? island.theme.tokens.color.accent : island.noteLook.head.color
                                font.bold: dragWord
                            }
                        }

                        Text {
                            id: summary
                            textFormat: Text.PlainText
                            width: parent.width - (noteSwatch.visible ? noteSwatch.width + 10 : 0)
                            text: island.noteLook.summaryText(island.heldNotification?.summary ?? "")
                            elide: Text.ElideRight
                            lineHeight: island.noteLook.voice === "caps" ? 1.1 : 1
                            color: island.noteLook.summary.color || box.style.text
                            font.family: island.noteLook.summary.font
                            font.pixelSize: island.noteLook.summary.size
                            font.weight: island.noteLook.summary.weight
                            font.letterSpacing: island.noteLook.summary.spacing

                            // With no tile, Blueprint's board draws a picked colour 10 px after the summary.
                            Rectangle {
                                id: noteSwatch
                                visible: island.noteLook.tile === null && !!island.heldNotification?.swatch
                                x: Math.min(summary.implicitWidth, summary.width) + 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                height: 16
                                color: island.heldNotification?.swatch ?? "transparent"
                                border.width: 1
                                border.color: box.style.text
                            }
                        }

                        // Paper and Blueprint draw the chip at the right of the body line.
                        Item {
                            width: parent.width
                            visible: body.text !== "" || bodyChip.visible
                            height: Math.max(body.visible ? body.implicitHeight : 0, bodyChip.visible ? bodyChip.implicitHeight + 2 : 0)

                            Text {
                                width: parent.width - (bodyChip.visible ? bodyChip.width + 12 : 0)
                                visible: text !== ""
                                id: body
                                text: island.noteLook.bodyText(island.heldNotification?.body ?? "")
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                color: island.noteLook.body.color || box.style.text
                                font.family: island.noteLook.body.font
                                font.pixelSize: island.noteLook.body.size
                            }

                            FileChip {
                                id: bodyChip
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: implicitWidth
                                height: implicitHeight
                                look: island.chipLook.toastPlace === "body" ? island.chipLook : null
                                at: island.chipLook.toast
                                files: island.heldNotification?.files ?? []
                                empty: island.noteDragging
                            }
                        }

                        Row {
                            visible: island.noteChips.length > 0
                            topPadding: 6
                            spacing: island.keyLook.legend("").chips ? 8 : 14

                            Repeater {
                                id: actionRepeater
                                model: island.noteChips

                                Rectangle {
                                    id: actionChip
                                    required property var modelData
                                    readonly property string drawn: actionKey.text + " " + actionWord.text
                                    width: actionPair.implicitWidth + (island.keyLook.legend("").chips ? 14 : 0)
                                    height: actionPair.implicitHeight + (island.keyLook.legend("").chips ? 6 : 0)
                                    radius: 6
                                    color: island.keyLook.chip.fill

                                    Row {
                                        id: actionPair
                                        anchors.centerIn: parent
                                        spacing: island.keyLook.legend("").chips ? 6 : 5

                                        Text {
                                            id: actionKey
                                            textFormat: Text.PlainText
                                            text: island.keyLook.keyText(actionChip.modelData.key)
                                            color: island.keyLook.chip.key
                                            font.family: island.theme.tokens?.type.mono ?? ""
                                            font.pixelSize: island.keyLook.small.size
                                            font.letterSpacing: island.keyLook.small.spacing
                                            font.bold: true
                                        }
                                        Text {
                                            id: actionWord
                                            textFormat: Text.PlainText
                                            text: island.keyLook.tabText(V.line(actionChip.modelData.text))
                                            color: island.noteLook.head.color
                                            font.family: island.keyLook.small.font
                                            font.pixelSize: island.keyLook.small.size
                                            font.letterSpacing: island.keyLook.small.spacing
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Artboard's chip is a column of its own at the card's right.
                    FileChip {
                        id: columnChip
                        anchors.verticalCenter: parent.verticalCenter
                        width: implicitWidth
                        height: implicitHeight
                        look: island.chipLook.toastPlace === "column" ? island.chipLook : null
                        at: island.chipLook.toast
                        files: island.heldNotification?.files ?? []
                        empty: island.noteDragging
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

                    // Blueprint heads the whole card: its name at the left, the month at the right.
                    Item {
                        visible: island.clockLook.grid.header !== ""
                        width: parent.width
                        height: headerName.implicitHeight

                        Text {
                            id: headerName
                            textFormat: Text.PlainText
                            text: island.clockLook.grid.header
                            color: island.clockLook.grid.title.left.color || box.style.text
                            font.family: island.clockLook.grid.title.left.font
                            font.pixelSize: island.clockLook.grid.title.left.size
                            font.letterSpacing: island.clockLook.grid.title.left.spacing
                        }

                        Text {
                            id: headerMonth
                            anchors.right: parent.right
                            textFormat: Text.PlainText
                            text: island.clockLook.grid.title.place === "header" ? island.titleParts.join(" ") : ""
                            color: island.clockLook.grid.title.left.color || box.style.text
                            font.family: island.clockLook.grid.title.left.font
                            font.pixelSize: island.clockLook.grid.title.left.size
                            font.letterSpacing: island.clockLook.grid.title.left.spacing
                        }
                    }

                    // The month at the theme's width, a rule, then the city column.
                    Row {
                        width: parent.width

                        Column {
                            id: monthGrid
                            width: island.clockLook.gridWidth
                            spacing: island.clockLook.grid.gap

                            // Paper heads the month as it heads the city column, after an accent square.
                            Item {
                                visible: island.clockLook.grid.head !== ""
                                width: parent.width
                                height: gridHead.implicitHeight

                                Rectangle {
                                    anchors.verticalCenter: gridHead.verticalCenter
                                    width: 8
                                    height: 8
                                    color: island.theme.tokens?.color.accent ?? box.style.text
                                }

                                Text {
                                    id: gridHead
                                    x: 16
                                    textFormat: Text.PlainText
                                    text: island.clockLook.grid.head
                                    color: box.style.text
                                    font.family: island.clockLook.offset.font
                                    font.pixelSize: island.clockLook.offset.size
                                    font.letterSpacing: island.clockLook.offset.spacing
                                }
                            }

                            Item {
                                visible: island.clockLook.grid.title.place !== "header"
                                width: parent.width
                                height: island.clockLook.grid.title.place === "line" ? 24 : titleLeft.implicitHeight

                                Text {
                                    id: titleLeft
                                    readonly property var at: island.clockLook.grid.title.left
                                    anchors.verticalCenter: island.clockLook.grid.title.place === "line" ? parent.verticalCenter : undefined
                                    textFormat: Text.PlainText
                                    text: island.titleParts[0] ?? ""
                                    color: at.color || box.style.text
                                    font.family: at.font
                                    font.pixelSize: at.size
                                    font.weight: at.weight
                                    font.letterSpacing: at.spacing
                                }

                                Text {
                                    id: titleRight
                                    readonly property var at: island.clockLook.grid.title.right
                                    visible: island.clockLook.grid.title.place === "split"
                                    anchors.right: parent.right
                                    anchors.baseline: titleLeft.baseline
                                    textFormat: Text.PlainText
                                    text: visible ? island.titleParts[1] ?? "" : ""
                                    color: at?.color || box.style.text
                                    font.family: at?.font ?? ""
                                    font.pixelSize: at?.size ?? 12
                                    font.italic: at?.italic ?? false
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

                        Item {
                            readonly property color ink: island.clockLook.rule.color || box.style.text
                            width: 2 * island.clockLook.gap + 1
                            height: Math.max(monthGrid.height, cityColumn.height)

                            Rectangle {
                                visible: !island.clockLook.rule.dashed
                                x: island.clockLook.gap
                                width: 1
                                height: parent.height
                                color: parent.ink
                            }

                            Root.Dashed {
                                visible: island.clockLook.rule.dashed
                                x: island.clockLook.gap + 1
                                width: parent.height
                                height: 1
                                rotation: 90
                                transformOrigin: Item.TopLeft
                                color: parent.ink
                            }
                        }

                        Column {
                            id: cityColumn
                            width: month.width - monthGrid.width - 2 * island.clockLook.gap - 1

                            // Paper heads the column as it heads its cards, after an accent square.
                            Item {
                                visible: island.clockLook.head !== ""
                                width: parent.width
                                height: cityHead.implicitHeight + 8

                                Rectangle {
                                    anchors.verticalCenter: cityHead.verticalCenter
                                    width: 8
                                    height: 8
                                    color: island.theme.tokens?.color.accent ?? box.style.text
                                }

                                Text {
                                    id: cityHead
                                    x: 16
                                    textFormat: Text.PlainText
                                    text: island.clockLook.head
                                    color: box.style.text
                                    font.family: island.clockLook.offset.font
                                    font.pixelSize: island.clockLook.offset.size
                                    font.letterSpacing: island.clockLook.offset.spacing
                                }
                            }

                            Repeater {
                                id: cityRepeater
                                model: island.cities

                                Item {
                                    id: cityRow
                                    required property var modelData
                                    readonly property var look: island.clockLook
                                    readonly property bool home: modelData.home
                                    // One of three offset texts is drawn, by where the theme puts it.
                                    readonly property Text offsetShown: look.place === "right" ? offsetRight : look.place === "under" ? offsetUnder : offsetBeside
                                    width: cityColumn.width
                                    height: Math.max(cityNames.height, cityTime.implicitHeight) + (home ? 8 : 18)

                                    function drawn() {
                                        return {
                                            city: cityName.text,
                                            time: cityTime.text,
                                            offset: offsetShown.visible ? offsetShown.text : "",
                                            day: cityDay.visible ? cityDay.text : ""
                                        };
                                    }

                                    Rectangle {
                                        visible: !cityRow.home && !cityRow.look.rule.dashed
                                        width: parent.width
                                        height: 1
                                        color: cityRow.look.rule.color || box.style.text
                                    }

                                    Root.Dashed {
                                        visible: !cityRow.home && cityRow.look.rule.dashed
                                        width: parent.width
                                        height: 1
                                        color: cityRow.look.rule.color || box.style.text
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

                                            Rectangle {
                                                readonly property bool boxed: cityRow.look.mark.boxed
                                                visible: cityRow.home
                                                anchors.left: cityName.right
                                                anchors.leftMargin: boxed ? 10 : 0
                                                anchors.verticalCenter: cityName.verticalCenter
                                                width: cityMark.implicitWidth + (boxed ? 10 : 0)
                                                height: cityMark.implicitHeight + (boxed ? 2 : 0)
                                                color: "transparent"
                                                border.width: boxed ? 1 : 0
                                                border.color: box.style.text

                                                Text {
                                                    id: cityMark
                                                    readonly property var at: parent.boxed ? cityRow.look.offset : cityRow.look.homeLabel
                                                    anchors.centerIn: parent
                                                    textFormat: Text.PlainText
                                                    text: cityRow.look.mark.text
                                                    color: at.color || box.style.text
                                                    font.family: at.font
                                                    font.pixelSize: at.size
                                                    font.letterSpacing: at.spacing
                                                }
                                            }

                                            Text {
                                                id: offsetBeside
                                                visible: !cityRow.home && cityRow.look.place === "name"
                                                anchors.left: cityName.right
                                                anchors.leftMargin: 10
                                                anchors.baseline: cityName.baseline
                                                textFormat: Text.PlainText
                                                text: cityRow.look.offsetText(cityRow.modelData.offset)
                                                color: cityRow.look.offset.color || box.style.text
                                                font.family: cityRow.look.offset.font
                                                font.pixelSize: cityRow.look.offset.size
                                                font.letterSpacing: cityRow.look.offset.spacing
                                            }
                                        }

                                        // The day word shows only when the city's day is not home's. A child's visible is false while this row is hidden, so this reads their conditions.
                                        Row {
                                            visible: (!cityRow.home && cityRow.look.place === "under") || cityRow.modelData.day !== ""
                                            spacing: 6

                                            Text {
                                                id: offsetUnder
                                                visible: !cityRow.home && cityRow.look.place === "under"
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
                                        anchors.right: offsetRight.visible ? offsetRight.left : parent.right
                                        anchors.rightMargin: offsetRight.visible ? 10 : 0
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

                                    Text {
                                        id: offsetRight
                                        visible: !cityRow.home && cityRow.look.place === "right"
                                        anchors.right: parent.right
                                        anchors.baseline: cityTime.baseline
                                        width: cityRow.look.offsetWidth
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.PlainText
                                        text: cityRow.look.offsetText(cityRow.modelData.offset)
                                        color: cityRow.look.offset.color || box.style.text
                                        font.family: cityRow.look.offset.font
                                        font.pixelSize: cityRow.look.offset.size
                                        font.letterSpacing: cityRow.look.offset.spacing
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

                Column {
                    id: ask
                    x: 20
                    y: 16
                    width: parent.width - 40
                    spacing: 12

                    Item {
                        width: parent.width
                        height: where.implicitHeight

                        Text {
                            id: where
                            textFormat: Text.PlainText
                            width: parent.width - hint.implicitWidth - 12
                            elide: Text.ElideRight
                            text: [island.heldQuestion?.project, island.heldQuestion?.machine].filter(p => p).join(" · ")
                            color: Qt.alpha(box.style.text, 0.65)
                            font.family: island.theme.tokens?.type.mono ?? ""
                            font.pixelSize: 11
                        }

                        Text {
                            id: hint
                            textFormat: Text.PlainText
                            anchors.right: parent.right
                            text: island.heldQuestion?.pairing ? "" : island.focused ? "1-9 pick · r reply · Esc" : "Mod+I to answer"
                            color: Qt.alpha(box.style.text, 0.65)
                            font.family: island.theme.tokens?.type.mono ?? ""
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        width: parent.width
                        text: island.heldQuestion?.text ?? ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: 6
                        elide: Text.ElideRight
                        lineHeight: 1.3
                        color: box.style.text
                        font.family: island.theme.tokens?.type.ui ?? ""
                        font.pixelSize: 15
                    }

                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: !island.replying

                        Repeater {
                            // A pairing request names the keys that answer it in place of options.
                            model: island.heldQuestion?.pairing ? island.heldQuestion.keys.map(k => k.join(" ")) : (island.heldQuestion?.options ?? []).slice(0, 9).concat(["Reply…"])

                            Rectangle {
                                required property string modelData
                                required property int index
                                readonly property bool isReply: !island.heldQuestion?.pairing && index === Math.min(island.heldQuestion?.options.length ?? 0, 9)
                                width: Math.min(chip.implicitWidth + 24, ask.width)
                                height: chip.implicitHeight + 12
                                radius: 8
                                color: index === 0 && !isReply ? box.style.text : "transparent"
                                border.width: index === 0 && !isReply ? 0 : 1
                                border.color: Qt.alpha(box.style.text, 0.35)

                                Text {
                                    id: chip
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width - 24)
                                    elide: Text.ElideRight
                                    text: island.heldQuestion?.pairing ? parent.modelData : (parent.isReply ? "r" : parent.index + 1) + " · " + parent.modelData
                                    color: parent.index === 0 && !parent.isReply ? box.style.fill : box.style.text
                                    font.family: island.theme.tokens?.type.ui ?? ""
                                    font.pixelSize: 13
                                }
                            }
                        }
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

        // A click opens a notification and a right click puts it away; the keyboard does the same through Mod+I.
        MouseArea {
            id: noteArea
            anchors.fill: parent
            enabled: island.mode === "notification"
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => mouse.button === Qt.RightButton ? island.putAway() : island.openNotification()
            // A file notification drags from its chip only; one with no file drags its body from anywhere.
            property bool onChip: false
            onPressed: mouse => {
                const chip = bodyChip.visible ? bodyChip : columnChip;
                onChip = chip.visible && chip.contains(chip.mapFromItem(noteArea, mouse.x, mouse.y));
                if (onChip)
                    noteFace.grab();
            }
            drag.target: noteOffer
        }

        Item {
            id: noteOffer
            readonly property var payload: N.dragPayload(island.heldNotification ?? { body: "" })
            Drag.active: noteArea.drag.active && (noteArea.onChip || payload.mime === "text/plain")
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: ({ [payload.mime]: payload.data })
            Drag.imageSource: payload.mime === "text/uri-list" ? noteFace.url : ""
            Drag.hotSpot.x: -14
            Drag.hotSpot.y: -18
            Drag.onDragStarted: island.noteDragging = true
            Drag.onDragFinished: island.noteDragging = false
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
                if (event.key === Qt.Key_Escape) {
                    island.questions.putAway(q.id);
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
