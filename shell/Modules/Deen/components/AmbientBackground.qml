import QtQuick

// Dekho's page glow, itself omakade's: two enormous soft discs bleeding in from
// opposite corners, one accent and one green. It is what keeps a design like
// this from reading as a flat sheet, and it is two rectangle nodes.
//
// SCOPED TO THE HEADER BAND, not the whole page — the same call Dekho makes,
// for a different reason. There it is poster corners; here it is Arabic. The
// ayah is the one thing on this hub you are meant to read closely, at a size
// where the marks above and below the line are already dense, and a coloured
// wash behind it costs contrast exactly where the module can least afford to
// spend it. So the glow lives in the chrome and stops before the text does.
//
// `clip: true` is what that scoping needs, and `pageWidth`/`pageHeight`/`pageY`
// are why it works: the discs are sized and placed against the WHOLE window, so
// a band shows the true slice of the composition the full page would have
// shown, rather than a squashed copy of it.
Item {
    id: ambient

    required property var style
    required property real pageWidth
    required property real pageHeight
    property real pageY: 0

    clip: true

    Rectangle {
        width: ambient.pageWidth * 0.52
        height: width
        radius: width / 2
        x: ambient.pageWidth * 0.62
        y: -height * 0.62 - ambient.pageY
        color: ambient.style.alpha(ambient.style.accent, 0.10)
    }

    Rectangle {
        width: ambient.pageWidth * 0.42
        height: width
        radius: width / 2
        x: -width * 0.48
        y: ambient.pageHeight * 0.48 - ambient.pageY
        color: ambient.style.alpha(ambient.style.green, 0.055)
    }

    // The clip has to become a dissolve. Scoping the discs to a band means
    // cutting them off, and a disc cut off is a HARD HORIZONTAL EDGE across the
    // page, which reads as an artifact rather than as a glow. Landing the
    // band's bottom on the page colour over a fixed depth is one more gradient
    // node.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(parent.height * 0.45)
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: ambient.style.alpha(ambient.style.bg, 0.0)
            }
            GradientStop {
                position: 1.0
                color: ambient.style.bg
            }
        }
    }
}
