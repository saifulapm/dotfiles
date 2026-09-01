import QtQuick

// omakade's page background, minus the part of it that cannot mean anything
// here: two enormous soft discs bleeding in from opposite corners, one accent
// and one green. It is what keeps that design from reading as a flat sheet, and
// it is two rectangle nodes.
//
// THE GRADIENT IS DELIBERATELY NOT PORTED. omakade's is three stops of its page
// colour at `surfaceAlpha` down to `surfaceAlpha * 0.88` and back, over a
// `color: "transparent"` window — it is window translucency, not shading. This
// window is opaque surface0 on purpose (doc §10: a cinema is a room with the
// lights off), so the same three stops composite to exactly the flat colour
// already underneath them: three gradient nodes per band that draw nothing.
//
// AND IT CANNOT GO BEHIND THE GRID, which is the one place this port diverges
// from omakade by choice. PosterCard's corner cover is a stroke painted in the
// colour behind the card (see its header), so a poster drawn over a disc gets a
// visible page-coloured ring on all four corners — sixty of them. So this is
// scoped to the bands where no poster corner sits: the library's header strip
// and the title page's hero.
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
    // page — clearly visible in the first build, and reading as an artifact
    // rather than as a glow. Landing the band's bottom on the page colour over a
    // fixed depth is the same trick the old hero used for the same reason
    // (doc §13's "the bottom was a hard cut"), and it is one more gradient node.
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
