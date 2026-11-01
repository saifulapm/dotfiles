import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "." as Root
import "lib/hifi.mjs" as H
import "lib/needle.mjs" as N

// Hi-Fi's volume OSD as a VU meter: an arc from 0 to 100 with a red zone at the top end, an amber needle, and a strip reading VOLUME and the value.
Item {
    id: meter

    // osdLook's meter: the dial's geometry, colours and the value's angle.
    required property var look
    property real value: 0
    // Where a new meter's needle starts its first swing, the volume before this one.
    property real before: value
    // The value the needle draws now; it swings to `value`, off the wall clock.
    property real drawn: 0
    // The swing as `island state` reports it, in volume units: peak is the furthest value drawn past `to`, settleMs the ms from the start to rest, -1 while moving.
    property var swing: ({ from: 0, to: 0, peak: 0, settleMs: -1 })
    property real startedAt: 0
    property bool ready: false
    readonly property real angle: look.angle(drawn)
    readonly property alias needle: needleLine
    readonly property alias word: wordText
    readonly property alias valueText: valueLabel

    implicitWidth: look.width
    implicitHeight: look.height

    Component.onCompleted: {
        drawn = before;
        ready = true;
        swingTo(value);
    }
    onValueChanged: if (ready)
        swingTo(value)

    // A new value swings on from wherever the needle is drawn now.
    function swingTo(target) {
        const rest = drawn === target;
        swing = { from: drawn, to: target, peak: target, settleMs: rest ? 0 : -1 };
        startedAt = Date.now();
        if (rest)
            clock.stop();
        else
            clock.start();
    }

    // Each frame draws the needle from the wall clock, so a stalled frame neither eats nor stretches the swing.
    FrameAnimation {
        id: clock
        onTriggered: {
            const ms = Date.now() - meter.startedAt;
            const total = Math.round(N.SWING_MS * Root.State.slowdown);
            const s = meter.swing;
            meter.drawn = N.needleAt(s.from, s.to, ms, total);
            const past = s.to > s.from ? Math.max(s.peak, meter.drawn) : Math.min(s.peak, meter.drawn);
            meter.swing = { from: s.from, to: s.to, peak: past, settleMs: ms >= total ? ms : -1 };
            if (ms >= total)
                stop();
        }
    }

    // A point r px from the pivot at deg from upright, in the dial's pixels.
    function onDial(deg, r) {
        const a = deg * Math.PI / 180;
        return { x: look.pivot.x + r * Math.sin(a), y: look.pivot.y - r * Math.cos(a) };
    }

    // The scale's labels as drawn, each with its colour and its box in the window's pixels.
    function labels() {
        const out = [];
        for (let i = 0; i < labelList.count; i++) {
            const t = labelList.itemAt(i);
            const p = t.mapToItem(null, 0, 0);
            out.push({ text: t.text, color: t.color.toString(), box: { x: p.x, y: p.y, w: t.width, h: t.height } });
        }
        return out;
    }

    // The same point in the window's pixels, for the state's pixel reads.
    function inWindow(deg, r) {
        const p = onDial(deg, r);
        return dial.mapToItem(null, p.x, p.y);
    }

    // The pivot sits below the dial, so the clip shows only the arc's top 90 degrees and the needle's upper end.
    Item {
        id: dial
        y: 1
        width: meter.width
        height: meter.look.dial
        clip: true

        Shape {
            anchors.fill: parent

            // A ShapePath is no Item, so it reads the look by id.
            ShapePath {
                strokeColor: meter.look.scale.color
                strokeWidth: 1
                fillColor: "transparent"
                PathAngleArc {
                    centerX: meter.look.pivot.x
                    centerY: meter.look.pivot.y
                    radiusX: meter.look.radius
                    radiusY: meter.look.radius
                    // Qt counts from three o'clock, so upright is -90.
                    startAngle: -135
                    sweepAngle: 90
                }
            }

            ShapePath {
                strokeColor: meter.look.redColor
                strokeWidth: 3
                fillColor: "transparent"
                PathAngleArc {
                    centerX: meter.look.pivot.x
                    centerY: meter.look.pivot.y
                    radiusX: meter.look.radius
                    radiusY: meter.look.radius
                    startAngle: meter.look.angle(meter.look.red) - 90
                    sweepAngle: meter.look.angle(100) - meter.look.angle(meter.look.red)
                }
            }
        }

        // Eleven ticks from the arc inwards, every other one long, red from the red mark on.
        Repeater {
            model: meter.look.ticks

            Rectangle {
                id: tick
                required property int index
                readonly property bool major: index % 2 === 0
                x: meter.look.pivot.x - width / 2
                y: meter.look.pivot.y - meter.look.radius
                width: major ? 1.2 : 1
                height: major ? 10 : 6
                antialiasing: true
                color: index * 10 >= meter.look.red ? meter.look.redColor : meter.look.scale.color
                // A Rotation is no Item, so it reads the tick by id.
                transform: Rotation {
                    origin.x: tick.width / 2
                    origin.y: meter.look.radius
                    angle: meter.look.angle(tick.index * 10)
                }
            }
        }

        // Red is only ever a lamp or the zone in Hi-Fi, never text, so every label is muted.
        Repeater {
            id: labelList
            model: meter.look.labels

            Text {
                required property int modelData
                readonly property var at: meter.onDial(meter.look.angle(modelData), meter.look.radius + 14)
                textFormat: Text.PlainText
                x: at.x - width / 2
                y: at.y - height / 2
                text: String(modelData)
                color: meter.look.scale.color
                font.family: meter.look.scale.font
                font.pixelSize: meter.look.scale.size
            }
        }

        // The needle turns about its foot at the pivot to the angle of the value drawn.
        Rectangle {
            id: needleLine
            x: meter.look.pivot.x - width / 2
            y: meter.look.pivot.y - height
            width: meter.look.needle.width
            height: meter.look.needle.length
            antialiasing: true
            color: meter.look.needle.color
            transformOrigin: Item.Bottom
            rotation: meter.angle
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: meter.look.needle.color
                shadowOpacity: 0.8
                shadowBlur: 0.4
                blurMax: 8
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }
        }
    }

    Rectangle {
        x: 1
        y: dial.y + dial.height
        width: meter.width - 2
        height: meter.look.strip.height
        color: meter.look.strip.fill

        // An engraved groove between the dial and the strip.
        Rectangle {
            width: parent.width
            height: 1
            color: H.HIFI.groove
        }

        Text {
            id: wordText
            textFormat: Text.PlainText
            x: 13
            anchors.verticalCenter: parent.verticalCenter
            text: meter.look.word
            color: meter.look.label.color
            font.family: meter.look.label.font
            font.pixelSize: meter.look.label.size
            font.letterSpacing: meter.look.label.spacing
        }

        Text {
            id: valueLabel
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: meter.look.valueText(meter.value)
            color: meter.look.value.color
            font.family: meter.look.value.font
            font.pixelSize: meter.look.value.size
            font.weight: meter.look.value.weight
            font.letterSpacing: meter.look.value.spacing
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: meter.look.value.color
                shadowOpacity: 0.5
                shadowBlur: 0.5
                blurMax: 12
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }
        }
    }
}
