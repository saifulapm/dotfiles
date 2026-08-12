import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// In-scene stand-in for compositor blur behind cards that animate in and
// out. niri cannot animate layer-shell surfaces (layer-rules are
// continuous-only), and ext-background-effect blur is binary — full
// strength the frame it's committed — so a protocol blur region pops
// somewhere in every entrance no matter how it's gated (tried: a settle
// gate, DankMaterialShell's growing region, an opaque shutter). But niri's
// xray blur composites only the cached blurred wallpaper, never windows,
// so the scene can reproduce it exactly: the same wallpaper file, cropped
// to the card's place on screen and blurred (LockView's backdrop,
// card-shaped), riding the card's own fade and scale. The frost is simply
// part of the card — present from the first frame of the entrance to the
// last frame of the exit. Surfaces that never animate (the bar, polkit)
// keep the real protocol blur.
ClippingRectangle {
    id: root

    required property var theme
    // The card this backdrop sits under: geometry, radius and the
    // fade/scale entrance are mirrored from it.
    required property Item card
    // The window's size, for aligning the wallpaper crop to the screen.
    required property real windowWidth
    required property real windowHeight
    // Entrance offsets for cards that slide via a Translate transform —
    // invisible in card.x/y for the same reason it was invisible to the
    // protocol Region: transforms are not geometry.
    property real offsetX: 0
    property real offsetY: 0
    // The protocol blur sat under the whole window, so a fullscreen scrim
    // tinted it too; drawn in-scene the frost occludes the scrim and must
    // re-apply that tint itself. Transparent for scrimless surfaces.
    property color tint: "transparent"

    // Decode, blur and store at a third of the screen, upscaled back by
    // the shader: the blur can't show the detail this loses, and it cuts
    // the effect's working textures 9x (a 4K frost drops ~30 MB of GPU
    // textures to ~3.5 MB per window).
    readonly property int downscale: 3

    x: card.x + offsetX
    y: card.y + offsetY
    width: card.width
    height: card.height
    radius: card.radius
    opacity: card.opacity
    scale: card.scale
    color: "transparent"

    // The whole body hangs off the blur switch, not this item's
    // visibility: with blur off the frost must cost nothing (Blur.qml's
    // rule — not even a wallpaper decode), while flipping on visibility
    // alone would drop and re-decode the textures on every open.
    Loader {
        id: frostLoader

        active: root.theme.blurActive

        sourceComponent: Item {
            // Gates the tint below: without a rendered wallpaper there is
            // nothing to occlude the scrim, and tinting anyway would paint
            // a card-shaped double-dim the protocol blur never had.
            readonly property bool ready: wallpaper.status === Image.Ready

            // Window-aligned: the frost sits at (root.x, root.y) in the
            // window, so the crop starts that far into the wallpaper.
            x: -root.x
            y: -root.y

            Item {
                scale: root.downscale
                transformOrigin: Item.TopLeft
                width: Math.ceil(root.windowWidth / root.downscale)
                height: Math.ceil(root.windowHeight / root.downscale)

                Image {
                    id: wallpaper

                    anchors.fill: parent
                    source: root.theme.wallpaperPath ? "file://" + String(root.theme.wallpaperPath).split("/").map(encodeURIComponent).join("/") : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.ceil(root.windowWidth / root.downscale)
                    sourceSize.height: Math.ceil(root.windowHeight / root.downscale)
                    // Synchronous: an async decode races the first entrance
                    // of each lazily-created window and the frost would pop
                    // in mid-animation — the artifact this component exists
                    // to remove. The decode is small, happens at window
                    // creation (blur-toggle time, not open time), and the
                    // pixmap cache shares it across every window after the
                    // first.
                    asynchronous: false
                    visible: false
                }

                // Tuned by eye against niri's own blur (defaults: passes 3,
                // offset 3) so the fake frost and the bar's real frost read
                // as one material. blurMax counts effect-texture pixels, so
                // it is a third of the full-resolution value it replaces.
                MultiEffect {
                    anchors.fill: wallpaper
                    source: wallpaper
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 21
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.tint
        visible: frostLoader.item ? frostLoader.item.ready : false
    }
}
