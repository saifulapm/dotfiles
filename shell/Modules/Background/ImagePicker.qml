import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "ImagePickerModel.js" as ImagePickerModel

// Wallpaper picker — port of omarchy's image-picker plugin (CREDITS.md):
// a full-screen scrim over a skewed filmstrip, the selection expanded to a
// wide preview with the rest of the set fanned out as dimmed slices to either
// side, ←/→ (and Tab) walking it, type-to-filter, Enter or a click on the
// preview applying, Escape cancelling.
//
// Their picker does not preview as you move, and neither does this one: the
// wallpaper only changes when a selection is applied, so Escape has nothing
// to restore. Applying goes through bin/background-next --set, the same
// atomic write bin/theme-set uses, which the Background module watches.
//
// LazyLoader-gated — nothing here exists until first summoned.
Scope {
    id: pickerRoot

    required property var theme

    property bool open: false
    property bool loaded: false
    // Their layoutSettled: the carousel is laid out one frame before it is
    // shown, so the strip never appears mid-arrangement.
    property bool layoutSettled: false
    property var images: []
    property int selectedIndex: 0
    property string filterText: ""
    // The live wallpaper, straight from the state file — this is what the
    // picker opens pre-selected on.
    property string currentPath: ""

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin"

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

    function show() {
        filterText = "";
        layoutSettled = false;
        listProc.running = true;
        open = true;
    }

    function hide() {
        open = false;
    }

    function toggle() {
        if (open)
            hide();
        else
            show();
    }

    function loadRows(rows) {
        const next = ImagePickerModel.loadRows(rows);
        images = next;
        selectedIndex = ImagePickerModel.indexForSelectedImage(next, currentPath);
        loaded = true;
        Qt.callLater(() => {
            if (pickerRoot.open)
                pickerRoot.layoutSettled = true;
        });
    }

    function currentImagePath() {
        if (images.length === 0 || !itemMatches(selectedIndex))
            return "";
        return images[selectedIndex].filePath;
    }

    function currentLabel() {
        const path = currentImagePath();
        if (!path)
            return filterText ? "No matches" : "";
        return ImagePickerModel.labelForPath(path);
    }

    function itemMatches(index) {
        return ImagePickerModel.itemMatches(images, index, filterText);
    }

    function filteredPosition(index) {
        return ImagePickerModel.filteredPosition(images, index, filterText);
    }

    function selectedFilteredPosition() {
        return ImagePickerModel.selectedFilteredPosition(images, selectedIndex, filterText);
    }

    function select(index) {
        if (images.length === 0)
            return;
        if (index < 0)
            index = 0;
        else if (index >= images.length)
            index = images.length - 1;
        if (!itemMatches(index))
            return;
        selectedIndex = index;
    }

    function selectAdjacent(direction) {
        const count = images.length;
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
            const first = ImagePickerModel.nextSelectedIndexForFilter(images, selectedIndex, filterText);
            if (first >= 0)
                selectedIndex = first;
        }
    }

    function apply() {
        const path = currentImagePath();
        if (!path) {
            hide();
            return;
        }
        Quickshell.execDetached([binDir + "/background-next", "--set", path]);
        hide();
    }

    Process {
        id: listProc
        command: [pickerRoot.binDir + "/background-next", "--list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: pickerRoot.loadRows(String(text || ""))
        }
    }

    // The picker's idea of "current" is the same file the wallpaper itself
    // comes from, so an external `background-next` moves the selection too.
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/qshell/background"
        watchChanges: true
        printErrors: false
        // A FileView stays unloaded until something reads it — without this,
        // neither onLoaded nor onLoadFailed ever fires.
        Component.onCompleted: reload()
        onLoaded: pickerRoot.currentPath = text().trim()
        onFileChanged: reload()
        onLoadFailed: pickerRoot.currentPath = ""
    }

    PanelWindow {
        visible: pickerRoot.open
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qshell-wallpaper"
        WlrLayershell.keyboardFocus: pickerRoot.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.5)

            MouseArea {
                anchors.fill: parent
                onClicked: pickerRoot.hide()
            }
        }

        Item {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - pickerRoot.theme.space(20), pickerRoot.expandedWidth + 13 * (pickerRoot.sliceWidth + pickerRoot.sliceSpacing) + pickerRoot.theme.space(10))
            height: pickerRoot.expandedHeight + pickerRoot.topPad + pickerRoot.bottomChromeHeight
            visible: pickerRoot.open && pickerRoot.loaded && pickerRoot.layoutSettled

            MouseArea {
                // Swallow clicks so they don't fall through to the scrim.
                anchors.fill: parent
            }

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
                width: Math.min(card.width, pickerRoot.expandedWidth + 13 * (pickerRoot.sliceWidth + pickerRoot.sliceSpacing))
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
                            pickerRoot.hide();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        pickerRoot.apply();
                        event.accepted = true;
                    } else if (ImagePickerModel.editsFilter(event, pickerRoot.filterText)) {
                        pickerRoot.updateFilter(ImagePickerModel.editedFilter(event, pickerRoot.filterText));
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
                    model: pickerRoot.images.length

                    delegate: Item {
                        id: slice

                        required property int index

                        readonly property var imageData: pickerRoot.images[index]
                        readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""

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

                            Image {
                                anchors.fill: parent
                                source: slice.sourceActivated && slice.thumbnailPath ? "file://" + slice.thumbnailPath.split("/").map(encodeURIComponent).join("/") : ""
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
                            onClicked: slice.selected ? pickerRoot.apply() : pickerRoot.select(slice.index)
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
        }

        // Theirs shows a bare scrim when a directory turns up empty. Say so
        // instead — with no theme backgrounds and no ~/Pictures/Wallpapers
        // there is nothing else on screen to explain it.
        Text {
            anchors.centerIn: parent
            visible: pickerRoot.open && pickerRoot.loaded && pickerRoot.images.length === 0
            text: "No wallpapers found"
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
