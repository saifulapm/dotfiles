import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"
import "../../components/PickerModel.js" as PickerModel

// Wallhaven picker — same filmstrip UI as the local wallpaper picker, but
// backed by wallhaven.cc instead of the on-disk theme + ~/Pictures/Wallpapers
// directories. The list is paginated: opening lands on the toplist page 1,
// ←/→ still walk items, type-to-filter still narrows the current page (the
// Background picker's invisible search), and the bottom chrome now carries
// Prev/Next + "Page N / M" controls that re-fetch with a new page number.
//
// Apply downloads the full-resolution image into ~/Pictures/Wallpapers/
// via bin/wallhaven-fetch --download (so the file is permanent and the next
// time the Background picker opens, the local directory lists it too), then
// calls bin/background-next --set with the same atomic write the local
// picker uses. Net result: the user's wallhaven browse becomes a wallpaper
// they can re-pick later from the regular picker.
//
// LazyLoader-gated — the whole tree (HTTP, thumbs cache, processes) exists
// only between first summon and the eviction grace window.
Scope {
    id: pickerRoot

    required property var theme

    readonly property alias open: strip.open
    // Page state lives on the caller, not the strip: a page change has to
    // refetch without dropping the selection, and the strip's prepared()
    // resets it on every show.
    property int currentPage: 1
    property int totalPages: 1
    property bool isLoading: false

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin"

    function show() {
        strip.prepare();
        fetchPage(currentPage);
        strip.open = true;
    }

    function hide() {
        strip.open = false;
    }

    function toggle() {
        if (strip.open)
            hide();
        else
            show();
    }

    // wallhaven-fetch --list ends its stdout with a `__META__\tpage\ttotal`
    // sentinel; split it off so loadWallhavenRows sees only real rows.
    function loadRows(rows) {
        var text = String(rows || "");
        var lines = text.split("\n");
        // The script's terminating newline leaves a trailing empty entry —
        // drop empties before locating the sentinel so a flush at the end
        // does not swallow the meta we just emitted.
        while (lines.length > 0 && lines[lines.length - 1] === "")
            lines.pop();

        var meta = null;
        if (lines.length > 0) {
            var last = lines[lines.length - 1];
            if (last.indexOf("__META__") === 0) {
                var parts = last.split("\t");
                meta = {
                    page: parseInt(parts[1] || "1", 10),
                    total: parseInt(parts[2] || "1", 10)
                };
                lines.pop();
            }
        }
        if (meta) {
            if (meta.page > 0)
                currentPage = meta.page;
            totalPages = Math.max(1, meta.total);
        }
        const items = PickerModel.loadWallhavenRows(lines.join("\n"));
        strip.setItems(items, 0);
    }

    function apply(index) {
        const item = strip.items[index];
        if (!item || !item.imageUrl || !item.wallhavenId)
            return;
        // Run a single download Process so we can pipe its stdout (the saved
        // path) into background-next --set. execDetached would fire-and-forget
        // and the race would set the wallpaper before the file finished writing.
        downloadProc.command = [binDir + "/wallhaven-fetch", "--download", item.imageUrl, item.wallhavenId, item.ext || "jpg"];
        downloadProc.running = true;
    }

    function fetchPage(page) {
        if (page < 1)
            page = 1;
        if (page > totalPages)
            page = totalPages;
        currentPage = page;
        isLoading = true;
        // Quickshell.Io.Process restarts when command changes; setting running
        // false first avoids the "already running, no-op" trap on the same page.
        listProc.running = false;
        listProc.command = [binDir + "/wallhaven-fetch", "--list", "--page", String(page)];
        listProc.running = true;
    }

    function prevPage() {
        if (currentPage > 1)
            fetchPage(currentPage - 1);
    }

    function nextPage() {
        if (currentPage < totalPages)
            fetchPage(currentPage + 1);
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                pickerRoot.isLoading = false;
                pickerRoot.loadRows(String(text || ""));
            }
        }
    }

    Process {
        id: downloadProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const savedPath = String(text || "").trim();
                if (!savedPath)
                    return;
                Quickshell.execDetached([pickerRoot.binDir + "/background-next", "--set", savedPath]);
            }
        }
    }

    FilmstripPicker {
        id: strip
        theme: pickerRoot.theme
        layerNamespace: "qshell-wallhaven"
        // The text doubles as the empty-state copy during the brief gap
        // before the first page lands — clearer than a bare scrim.
        emptyText: pickerRoot.isLoading ? "Loading…" : "No wallpapers found"
        extraChromeHeight: 36
        extraChromeComponent: footerComponent
        onApplied: index => pickerRoot.apply(index)
    }

    // The Prev / Page N of M / Next row. Lives in the bottom chrome slot
    // FilmstripPicker grows when extraChromeComponent is set. Hover and
    // disabled states use the same alpha-blended theme tokens the rest of
    // the shell surfaces use, so the buttons read as part of the same UI.
    Component {
        id: footerComponent
        Item {
            id: footer
            implicitWidth: row.implicitWidth
            implicitHeight: 36

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 12

                Rectangle {
                    id: prevButton
                    width: 76
                    height: 30
                    radius: 15
                    opacity: pickerRoot.currentPage > 1 ? 1.0 : 0.35
                    color: prevMa.containsMouse ? pickerRoot.theme.alpha(pickerRoot.theme.accent, 0.22) : pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.6)
                    border.color: pickerRoot.theme.alpha(pickerRoot.theme.textPrimary, 0.2)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "‹ Prev"
                        color: pickerRoot.theme.textPrimary
                        font.family: pickerRoot.theme.fontUi
                        font.pixelSize: pickerRoot.theme.fontPx(1.0)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: pickerRoot.currentPage > 1
                        onClicked: pickerRoot.prevPage()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `Page ${pickerRoot.currentPage} / ${pickerRoot.totalPages}`
                    color: pickerRoot.theme.textPrimary
                    font.family: pickerRoot.theme.fontUi
                    font.pixelSize: pickerRoot.theme.fontPx(1.1)
                    font.weight: Font.DemiBold
                    style: Text.Outline
                    styleColor: pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.7)
                }

                Rectangle {
                    id: nextButton
                    width: 76
                    height: 30
                    radius: 15
                    opacity: pickerRoot.currentPage < pickerRoot.totalPages ? 1.0 : 0.35
                    color: nextMa.containsMouse ? pickerRoot.theme.alpha(pickerRoot.theme.accent, 0.22) : pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.6)
                    border.color: pickerRoot.theme.alpha(pickerRoot.theme.textPrimary, 0.2)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Next ›"
                        color: pickerRoot.theme.textPrimary
                        font.family: pickerRoot.theme.fontUi
                        font.pixelSize: pickerRoot.theme.fontPx(1.0)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: pickerRoot.currentPage < pickerRoot.totalPages
                        onClicked: pickerRoot.nextPage()
                    }
                }
            }
        }
    }
}
