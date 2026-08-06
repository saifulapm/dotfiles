import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "PickerModel.js" as PickerModel

// The filmstrip picker — port of omarchy's image-picker plugin (CREDITS.md):
// a full-screen scrim over a skewed strip, the selection expanded to a wide
// preview with the rest of the set fanned out as dimmed slices to either
// side, ←/→ (and Tab) walking it, type-to-filter, Enter or a click on the
// preview applying, Escape clearing the filter and then cancelling.
//
// Omarchy's theme switcher IS their image selector — `omarchy-theme-switcher`
// builds a directory of per-theme preview images and hands it to
// `omarchy-menu-images` with the same --show-labels --filterable --selected
// flags the wallpaper switcher uses. So this is one component with two
// callers: it owns the window, the strip and the keyboard, and knows nothing
// about what a tile means.
//
// A tile is `{ key, label, imagePath, swatch }`. `imagePath` draws the image;
// with no image the optional `swatch` ({ background, dots: [] }) is rendered
// instead, which is how a theme with no preview file still gets a tile.
Scope {
    id: pickerRoot

    required property var theme

    // Distinct per caller so the compositor can tell the two pickers apart.
    property string layerNamespace: "qshell-picker"

    property var items: []
    property int selectedIndex: 0
    property string filterText: ""
    property bool open: false
    property bool loaded: false
    // Their layoutSettled: the strip is laid out one frame before it is
    // shown, so it never appears mid-arrangement.
    property bool layoutSettled: false
    property string emptyText: ""

    signal applied(int index)
    signal cancelled

    // Their carousel geometry, in raw pixels like theirs: the strip is sized
    // by the images it shows, not by the spacing scale.
    readonly property int expandedWidth: 768
    readonly property int expandedHeight: 475
    readonly property int sliceWidth: 108
    readonly property int sliceHeight: 432
    readonly property int sliceSpacing: -30
    readonly property int skewOffset: 28
    // Their Style.space(30) / bottom chrome for labels + filter line.
    readonly property int topPad: theme.space(8)
    readonly property int bottomChromeHeight: theme.space(26)

    function prepare() {
        filterText = "";
        layoutSettled = false;
        loaded = false;
    }

    function setItems(next, index) {
        items = Array.isArray(next) ? next : [];
        selectedIndex = Math.max(0, Math.min(items.length - 1, index || 0));
        loaded = true;
        Qt.callLater(() => {
            if (pickerRoot.open)
                pickerRoot.layoutSettled = true;
        });
    }

    function currentItem() {
        if (items.length === 0 || !itemMatches(selectedIndex))
            return null;
        return items[selectedIndex];
    }

    function currentLabel() {
        const item = currentItem();
        if (!item)
            return filterText ? "No matches" : "";
        return item.label || item.key || "";
    }

    function itemMatches(index) {
        return PickerModel.itemMatches(items, index, filterText);
    }

    function filteredPosition(index) {
        return PickerModel.filteredPosition(items, index, filterText);
    }

    function selectedFilteredPosition() {
        return PickerModel.selectedFilteredPosition(items, selectedIndex, filterText);
    }

    function select(index) {
        if (items.length === 0)
            return;
        if (index < 0)
            index = 0;
        else if (index >= items.length)
            index = items.length - 1;
        if (!itemMatches(index))
            return;
        selectedIndex = index;
    }

    function selectAdjacent(direction) {
        const count = items.length;
        if (count === 0)
            return;
        let index = selectedIndex;
        for (let i = 0; i < count; i++) {
            index = (index + direction + count) % count;
            if (itemMatches(index)) {
                select(index);
                return;
            }
        }
    }

    function updateFilter(next) {
        filterText = next;
        if (!itemMatches(selectedIndex)) {
            const first = PickerModel.nextSelectedIndexForFilter(items, selectedIndex, filterText);
            if (first >= 0)
                selectedIndex = first;
        }
    }

    function cancel() {
        open = false;
        cancelled();
    }

    function applySelection() {
        const index = selectedIndex;
        if (!currentItem()) {
            cancel();
            return;
        }
        open = false;
        applied(index);
    }

    OverlaySurface {
        id: surface

        theme: pickerRoot.theme
        opened: pickerRoot.open
        namespace: pickerRoot.layerNamespace
        // Chrome-less: the filmstrip draws straight on the scrim — no glass
        // fill, no border, and blur would frost the strip's own region.
        cardColor: "transparent"
        cardBorderWidth: 0
        cardRadius: 0
        blurable: false
        cardWidth: Math.min(width - pickerRoot.theme.space(20), pickerRoot.expandedWidth + 13 * (pickerRoot.sliceWidth + pickerRoot.sliceSpacing) + pickerRoot.theme.space(10))
        cardHeight: pickerRoot.expandedHeight + pickerRoot.topPad + pickerRoot.bottomChromeHeight
        // The overlays' shared entrance, gated behind the same layout-settled
        // guard that used to hard-flip visible — the strip still never
        // appears mid-arrangement, it just eases in once arranged.
        cardShown: pickerRoot.open && pickerRoot.loaded && pickerRoot.layoutSettled && pickerRoot.items.length > 0
        onDismissed: pickerRoot.cancel()

        Item {
            id: carousel
            anchors.top: parent.top
            anchors.topMargin: pickerRoot.topPad
            anchors.bottom: parent.bottom
            anchors.bottomMargin: pickerRoot.bottomChromeHeight
            anchors.horizontalCenter: parent.horizontalCenter
            // Theirs is a fixed 13-slice strip, which assumes a screen wide
            // enough to hold it; this display is 1706 logical px, so the
            // strip is capped at the card and the preview re-centres inside
            // what is actually there. Identical to theirs where it fits.
            width: Math.min(surface.cardWidth, pickerRoot.expandedWidth + 13 * (pickerRoot.sliceWidth + pickerRoot.sliceSpacing))
            clip: false
            focus: true

            readonly property real itemStep: pickerRoot.sliceWidth + pickerRoot.sliceSpacing
            readonly property real previewX: (width - pickerRoot.expandedWidth) / 2

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (pickerRoot.filterText)
                        pickerRoot.updateFilter("");
                    else
                        pickerRoot.cancel();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    pickerRoot.applySelection();
                    event.accepted = true;
                } else if (PickerModel.editsFilter(event, pickerRoot.filterText)) {
                    pickerRoot.updateFilter(PickerModel.editedFilter(event, pickerRoot.filterText));
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
                    pickerRoot.selectAdjacent(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                    pickerRoot.selectAdjacent(1);
                    event.accepted = true;
                } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                    pickerRoot.updateFilter(pickerRoot.filterText + event.text);
                    event.accepted = true;
                }
            }

            Repeater {
                model: pickerRoot.items.length

                delegate: Item {
                    id: slice

                    required property int index

                    readonly property var itemData: pickerRoot.items[index]
                    readonly property string imagePath: itemData && itemData.imagePath ? itemData.imagePath : ""
                    readonly property var swatch: itemData && itemData.swatch ? itemData.swatch : null

                    readonly property bool matched: pickerRoot.itemMatches(index)
                    readonly property int relativeIndex: pickerRoot.filteredPosition(index) - pickerRoot.selectedFilteredPosition()
                    readonly property bool selected: matched && index === pickerRoot.selectedIndex
                    readonly property bool nearby: matched && Math.abs(relativeIndex) <= 16
                    // Keep a decoded image once it has been near the
                    // selection, so walking the strip never re-decodes.
                    property bool sourceActivated: nearby
                    onNearbyChanged: if (nearby)
                        sourceActivated = true

                    visible: nearby
                    x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + pickerRoot.expandedWidth + pickerRoot.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
                    y: selected ? 0 : (pickerRoot.expandedHeight - pickerRoot.sliceHeight) / 2
                    width: selected ? pickerRoot.expandedWidth : pickerRoot.sliceWidth
                    height: selected ? pickerRoot.expandedHeight : pickerRoot.sliceHeight
                    z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

                    // The parallelogram every slice is cut to.
                    readonly property real skAbs: Math.abs(pickerRoot.skewOffset)
                    readonly property real topLeft: pickerRoot.skewOffset >= 0 ? skAbs : 0
                    readonly property real topRight: pickerRoot.skewOffset >= 0 ? width : width - skAbs
                    readonly property real bottomRight: pickerRoot.skewOffset >= 0 ? width - skAbs : width
                    readonly property real bottomLeft: pickerRoot.skewOffset >= 0 ? 0 : skAbs

                    Item {
                        id: maskShape
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true

                        Shape {
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                fillColor: "white"
                                strokeColor: "transparent"
                                startX: slice.topLeft
                                startY: 0

                                PathLine {
                                    x: slice.topRight
                                    y: 0
                                }
                                PathLine {
                                    x: slice.bottomRight
                                    y: slice.height
                                }
                                PathLine {
                                    x: slice.bottomLeft
                                    y: slice.height
                                }
                                PathLine {
                                    x: slice.topLeft
                                    y: 0
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: maskShape
                            maskThresholdMin: 0.3
                            maskSpreadAtMin: 0.3
                        }

                        // No preview image on disk: the theme paints its own
                        // tile instead — its surface holding its accent ramp,
                        // the swatch row the list-style switcher used to show.
                        Rectangle {
                            id: swatchTile
                            anchors.fill: parent
                            visible: !slice.imagePath && slice.swatch !== null
                            color: slice.swatch && slice.swatch.background ? slice.swatch.background : "transparent"

                            readonly property real dotSize: Math.max(8, Math.min(width, height) * 0.09)

                            Row {
                                anchors.centerIn: parent
                                spacing: swatchTile.dotSize * 0.6

                                Repeater {
                                    model: slice.swatch && slice.swatch.dots ? slice.swatch.dots : []

                                    Rectangle {
                                        required property var modelData
                                        width: swatchTile.dotSize
                                        height: width
                                        radius: width / 2
                                        color: modelData || "transparent"
                                    }
                                }
                            }
                        }

                        Image {
                            anchors.fill: parent
                            source: slice.sourceActivated && slice.imagePath ? "file://" + slice.imagePath.split("/").map(encodeURIComponent).join("/") : ""
                            fillMode: Image.PreserveAspectCrop
                            // Their rows carry ImageMagick-rendered
                            // thumbnails, which they can afford to decode
                            // synchronously; we have no `magick` here, so
                            // these are the originals decoded off-thread
                            // and downscaled to the widest size the strip
                            // ever draws them at.
                            sourceSize.width: pickerRoot.expandedWidth
                            asynchronous: true
                            cache: true
                            smooth: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: pickerRoot.theme.alpha(pickerRoot.theme.surface0, slice.selected ? 0 : 0.42)
                        }
                    }

                    Shape {
                        anchors.fill: parent
                        antialiasing: true
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: slice.selected ? pickerRoot.theme.accent : pickerRoot.theme.alpha(pickerRoot.theme.textPrimary, 0.28)
                            strokeWidth: slice.selected ? 3 : 1
                            startX: slice.topLeft
                            startY: 0

                            PathLine {
                                x: slice.topRight
                                y: 0
                            }
                            PathLine {
                                x: slice.bottomRight
                                y: slice.height
                            }
                            PathLine {
                                x: slice.bottomLeft
                                y: slice.height
                            }
                            PathLine {
                                x: slice.topLeft
                                y: 0
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: slice.selected ? pickerRoot.applySelection() : pickerRoot.select(slice.index)
                    }
                }
            }
        }

        Text {
            id: selectedLabel
            anchors.top: carousel.bottom
            anchors.topMargin: pickerRoot.theme.space(4)
            anchors.horizontalCenter: carousel.horizontalCenter
            width: pickerRoot.expandedWidth
            text: pickerRoot.currentLabel()
            color: pickerRoot.theme.textPrimary
            // Outlined because the label sits over the strip's own
            // spill, not over a card.
            style: Text.Outline
            styleColor: pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.7)
            font.family: pickerRoot.theme.fontUi
            font.pixelSize: pickerRoot.theme.fontPx(2.0)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            visible: pickerRoot.filterText !== ""
            anchors.top: selectedLabel.bottom
            anchors.topMargin: pickerRoot.theme.space(2)
            anchors.horizontalCenter: carousel.horizontalCenter
            width: pickerRoot.expandedWidth
            text: pickerRoot.filterText
            color: pickerRoot.theme.textPrimary
            opacity: 0.85
            style: Text.Outline
            styleColor: pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.7)
            font.family: pickerRoot.theme.fontUi
            font.pixelSize: pickerRoot.theme.fontPx(1.167)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        // Theirs shows a bare scrim when a directory turns up empty. Say so
        // instead — there is nothing else on screen to explain it. On the
        // scrim slot, not in the card: it shows exactly when the card is
        // hidden.
        scrimContent: Text {
            anchors.centerIn: parent
            visible: pickerRoot.open && pickerRoot.loaded && pickerRoot.items.length === 0 && pickerRoot.emptyText !== ""
            text: pickerRoot.emptyText
            color: pickerRoot.theme.textMuted
            font.family: pickerRoot.theme.fontUi
            font.pixelSize: pickerRoot.theme.fontPx(1.167)
        }

        // Focus has to be taken every time the window is shown; the carousel
        // is only created once.
        Connections {
            target: pickerRoot
            function onOpenChanged() {
                if (pickerRoot.open)
                    Qt.callLater(() => carousel.forceActiveFocus());
            }
        }
    }
}
