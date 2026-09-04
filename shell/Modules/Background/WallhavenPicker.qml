import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"
import "../../components/PickerModel.js" as PickerModel

// Remote wallpaper picker — same filmstrip UI as the local wallpaper
// picker, but backed by bin/wallpaper-fetch's sources (wallhaven, bing's
// daily gallery, picsum, pexels when a key exists) instead of the on-disk
// theme + ~/Pictures/Wallpapers directories. Historically wallhaven-only —
// the IPC target and file name keep that name.
//
// Sources: the footer draws one chip per available source (clickable), and
// Ctrl+S cycles them from the keyboard. Typing into a source that cannot
// search (bing, picsum) hops to the first searchable source instead of
// silently ignoring the query.
//
// Type-to-filter is wired to a wallhaven search: a keystroke updates
// `currentQuery`, a 500ms debounce fires fetchPage(1) with q=currentQuery,
// and the API returns 24 results for the typed phrase (sorted by relevance;
// an empty query falls back to wallhaven's curated toplist). The strip runs
// in `externalQueryMode` so its built-in substring filter is bypassed —
// wallhaven IDs and resolutions are random strings and would never match a
// phrase like "spiderman" anyway. ←/→ still walk items, Prev/Next paginate,
// and Enter / preview-click apply.
//
// Results are cached in-memory per (query, page) for 10 minutes: re-typing
// the same phrase, clicking Next then Back, and re-opening the picker within
// the TTL all skip the HTTP round trip. Each (query, page) entry holds the
// parsed items plus totalPages so pagination works without an extra call.
//
// Apply downloads the full-resolution image into ~/Pictures/Wallpapers/
// via bin/wallpaper-fetch --download (so the file is permanent and the next
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
    // The search query driving the current items. Mirrors strip.filterText,
    // updated through Connections on the strip — the picker never writes to
    // strip.filterText directly; keystrokes flow through FilmstripPicker's
    // own key handler (so Escape-to-clear, Ctrl+U word-kill, backspace all
    // keep working).
    property string currentQuery: ""
    // Available sources, from `wallpaper-fetch --sources` (probed on first
    // show): [{name, searchable, label}]. wallhaven/pexels appear only when
    // their pass(1) key exists.
    property var sources: []
    property int sourceIndex: 0
    readonly property var currentSource: sources[sourceIndex] || ({
            name: "wallhaven",
            searchable: true,
            label: "Wallhaven"
        })
    property bool sourcesProbed: false
    // "{query|page -> { items, totalPages, ts }}". Bounded by maxCacheEntries
    // with LRU eviction so a long browsing session doesn't grow without limit.
    // The cap is generous (100 entries = 2400 items) — typical use stays well
    // under 20: a handful of queries × a few pages each.
    property var itemCache: ({})
    property int cacheTtlMs: 600000
    property int maxCacheEntries: 100
    // Set to "query|page" when a fetch is in flight; loadRows compares the
    // meta line's echoed query+page against this and drops the response if
    // they don't match — protects against a slow first response being
    // clobbered by a faster second one when the user types through a pause.
    property string pendingKey: ""

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin"

    function show() {
        strip.prepare();
        if (!sourcesProbed) {
            isLoading = true;
            sourcesProc.running = true;
        } else {
            fetchPage(currentPage);
        }
        strip.open = true;
    }

    function setSourceIndex(i) {
        if (sources.length === 0)
            return;
        const next = ((i % sources.length) + sources.length) % sources.length;
        if (next === sourceIndex)
            return;
        sourceIndex = next;
        currentPage = 1;
        totalPages = 1;
        debounceTimer.stop();
        fetchPage(1);
    }

    function cycleSource() {
        setSourceIndex(sourceIndex + 1);
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

    function getCached(query, page) {
        const key = currentSource.name + "|" + query + "|" + String(page);
        const entry = itemCache[key];
        if (!entry)
            return null;
        if (Date.now() - entry.ts > cacheTtlMs)
            return null;
        return entry;
    }

    function putCached(query, page, items, totalPages) {
        const key = currentSource.name + "|" + query + "|" + String(page);
        const next = Object.assign({}, itemCache);
        next[key] = {
            items: items,
            totalPages: totalPages,
            ts: Date.now()
        };
        // Evict the oldest entries if over cap. Object key order is
        // insertion order, so a timestamp sort is enough — newer entries
        // land at the tail.
        const keys = Object.keys(next);
        if (keys.length > maxCacheEntries) {
            keys.sort(function (a, b) {
                return next[a].ts - next[b].ts;
            });
            const drop = keys.length - maxCacheEntries;
            for (let i = 0; i < drop; i++)
                delete next[keys[i]];
        }
        itemCache = next;
    }

    // wallpaper-fetch --list ends its stdout with a
    // `__META__\tpage\ttotal\tquery` sentinel; split it off so
    // loadWallhavenRows sees only real rows.
    function loadRows(rows) {
        isLoading = false;

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
                    total: parseInt(parts[2] || "1", 10),
                    query: parts[3] || "",
                    source: parts[4] || "wallhaven"
                };
                lines.pop();
            }
        }
        // Stale-response guard: the script echoes the query it ran with,
        // and we captured the same query|page in pendingKey when fetchPage
        // started. A mismatch means a newer fetch has superseded this one
        // (the user kept typing) — drop without touching items so the
        // superseding fetch's response wins the race.
        if (meta) {
            const actualKey = meta.source + "|" + meta.query + "|" + String(meta.page);
            if (actualKey !== pendingKey)
                return;
        }
        if (meta) {
            if (meta.page > 0)
                currentPage = meta.page;
            totalPages = Math.max(1, meta.total);
        }

        if (lines.length === 0) {
            // Empty response (API failure or genuine empty result set) —
            // keep the previous items visible so a transient blip doesn't
            // blank the strip. Don't cache an empty page either.
            pendingKey = "";
            return;
        }

        const items = PickerModel.loadWallhavenRows(lines.join("\n"));
        strip.setItems(items, 0);
        putCached(currentQuery, currentPage, items, totalPages);
        pendingKey = "";
    }

    function apply(index) {
        const item = strip.items[index];
        if (!item || !item.imageUrl || !item.wallhavenId)
            return;
        // Run a single download Process so we can pipe its stdout (the saved
        // path) into background-next --set. execDetached would fire-and-forget
        // and the race would set the wallpaper before the file finished writing.
        downloadProc.command = [binDir + "/wallpaper-fetch", "--download", "--source", currentSource.name, item.imageUrl, item.wallhavenId, item.ext || "jpg"];
        downloadProc.running = true;
    }

    // Shift+Enter — downloads then runs bin/theme-from-image. The script
    // owns the WHOLE fan-out (flock + IPC themeTransition for synchronized
    // wipe + theme.toml atomic publish + background-next --set + exec
    // theme-apply). Don't background-next --set here: that would race the
    // script's own --set and steal the old_bg the wipe reveal wants.
    function applyAsTheme(index) {
        const item = strip.items[index];
        if (!item || !item.imageUrl || !item.wallhavenId)
            return;
        themeDownloadProc.command = [binDir + "/wallpaper-fetch", "--download", "--source", currentSource.name, item.imageUrl, item.wallhavenId, item.ext || "jpg"];
        themeDownloadProc.running = true;
    }

    function fetchPage(page) {
        if (page < 1)
            page = 1;
        if (page > totalPages && totalPages > 0)
            page = totalPages;

        const cached = getCached(currentQuery, page);
        if (cached) {
            currentPage = page;
            totalPages = cached.totalPages;
            pendingKey = "";
            strip.setItems(cached.items, 0);
            return;
        }

        currentPage = page;
        pendingKey = currentSource.name + "|" + currentQuery + "|" + String(page);
        isLoading = true;
        // Quickshell.Io.Process restarts when command changes; setting running
        // false first avoids the "already running, no-op" trap on the same page.
        listProc.running = false;
        listProc.command = [binDir + "/wallpaper-fetch", "--list", "--source", currentSource.name, "--query", currentQuery, "--page", String(page)];
        listProc.running = true;
    }

    function prevPage() {
        // Cancels an in-flight debounce: the user just clicked Next with a
        // clear intent, so don't reset to page 1 of whatever they were
        // half-typing.
        debounceTimer.stop();
        if (currentPage > 1)
            fetchPage(currentPage - 1);
    }

    function nextPage() {
        debounceTimer.stop();
        if (currentPage < totalPages)
            fetchPage(currentPage + 1);
    }

    // One probe per picker lifetime: which sources have what they need
    // (keys in pass, nothing for bing/picsum). Rows: name\tsearchable\tlabel.
    Process {
        id: sourcesProc
        command: [pickerRoot.binDir + "/wallpaper-fetch", "--sources"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const rows = String(text || "").split("\n").filter(l => l.length > 0).map(l => {
                    const c = l.split("\t");
                    return {
                        name: c[0],
                        searchable: c[1] === "1",
                        label: c[2] || c[0]
                    };
                });
                if (rows.length > 0)
                    pickerRoot.sources = rows;
                pickerRoot.sourcesProbed = true;
                pickerRoot.fetchPage(1);
            }
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
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

    // Shift+Enter download path — same wallpaper-fetch call, then hand
    // the saved path to bin/theme-from-image. That script runs the full
    // fan-out (theme.toml + IPC transition + background-next --set +
    // theme-apply). We do NOT background-next --set here: the script's
    // own --set is sequenced inside its flock so the wipe reveal reads
    // a consistent old_bg.
    Process {
        id: themeDownloadProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const savedPath = String(text || "").trim();
                if (!savedPath)
                    return;
                Quickshell.execDetached([pickerRoot.binDir + "/theme-from-image", savedPath]);
            }
        }
    }

    // 500ms debounce on type-to-filter — coalesces a typing burst into one
    // wallhaven query (otherwise "spiderman" would fire 8 searches). Fires
    // fetchPage(1) so every new query restarts pagination from page 1.
    Timer {
        id: debounceTimer
        interval: 500
        repeat: false
        onTriggered: pickerRoot.fetchPage(1)
    }

    // Hook the strip's keystroke-driven filterText and treat it as a search
    // query: copy it into currentQuery and (re)start the debounce. Also
    // stop the debounce when the picker closes so a half-typed query that
    // never paused doesn't fire a fetch after the user picked something
    // and moved on.
    Connections {
        target: strip
        function onFilterTextChanged() {
            pickerRoot.currentQuery = strip.filterText;
            // A query needs a source that can search: typing while on
            // bing/picsum hops to the first searchable one rather than
            // debouncing into a fetch that ignores the words.
            if (pickerRoot.currentQuery !== "" && !pickerRoot.currentSource.searchable) {
                const idx = pickerRoot.sources.findIndex(s => s.searchable);
                if (idx >= 0) {
                    pickerRoot.sourceIndex = idx;
                    pickerRoot.currentPage = 1;
                }
            }
            debounceTimer.restart();
        }
        function onOpenChanged() {
            if (!strip.open)
                debounceTimer.stop();
        }
    }

    FilmstripPicker {
        id: strip
        theme: pickerRoot.theme
        layerNamespace: "qshell-wallhaven"
        // Treat the typed filter as a wallhaven query, not a local substring
        // match — wallhaven IDs are random strings ("lydkg2") and resolutions
        // ("1920x1080") so local matching against them would always miss.
        // Item selection is managed by fetchPage's results, not by the
        // strip's substring filter.
        externalQueryMode: true
        // Query-aware empty text: while loading, say so; on a real empty
        // result, quote the query so the user knows what they searched for.
        emptyText: {
            if (pickerRoot.isLoading)
                return "Loading " + pickerRoot.currentSource.label + "…";
            if (pickerRoot.currentQuery)
                return "No " + pickerRoot.currentSource.label + " results for \"" + pickerRoot.currentQuery + "\"";
            return "No wallpapers found";
        }
        // Ctrl+S cycles the source from the keyboard (the footer chips are
        // the pointer path). Claimed here so the strip's own key handling
        // never sees it.
        onChord: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                pickerRoot.cycleSource();
                event.accepted = true;
            }
        }
        extraChromeHeight: 36
        extraChromeComponent: footerComponent
        onApplied: index => pickerRoot.apply(index)
        onAppliedAsTheme: index => pickerRoot.applyAsTheme(index)
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

                // One chip per source; the active one wears the accent.
                // Ctrl+S cycles the same list from the keyboard.
                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pickerRoot.sources.length > 1

                    Repeater {
                        model: pickerRoot.sources

                        Rectangle {
                            required property var modelData
                            required property int index

                            readonly property bool active: index === pickerRoot.sourceIndex
                            width: chipLabel.implicitWidth + 18
                            height: 26
                            radius: 13
                            color: active ? pickerRoot.theme.alpha(pickerRoot.theme.accent, 0.3) : (chipMa.containsMouse ? pickerRoot.theme.alpha(pickerRoot.theme.accent, 0.15) : pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.6))
                            border.color: active ? pickerRoot.theme.alpha(pickerRoot.theme.accent, 0.7) : pickerRoot.theme.alpha(pickerRoot.theme.textPrimary, 0.2)
                            border.width: 1

                            Text {
                                id: chipLabel
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: pickerRoot.theme.textPrimary
                                font.family: pickerRoot.theme.fontUi
                                font.pixelSize: pickerRoot.theme.fontPx(0.9)
                                font.weight: parent.active ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pickerRoot.setSourceIndex(parent.index)
                            }
                        }
                    }
                }

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
                        textFormat: Text.PlainText
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

                // Page position, or the loading state while a fetch is in
                // flight — pagination with items already on screen used to
                // give no sign anything was happening.
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        textFormat: Text.PlainText
                        visible: pickerRoot.isLoading
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰑓" // md-refresh, spun below
                        color: pickerRoot.theme.accent
                        font.pixelSize: pickerRoot.theme.fontPx(1.3)

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                            running: pickerRoot.isLoading
                        }
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: pickerRoot.isLoading ? "Loading…" : `Page ${pickerRoot.currentPage} / ${pickerRoot.totalPages}`
                        color: pickerRoot.theme.textPrimary
                        font.family: pickerRoot.theme.fontUi
                        font.pixelSize: pickerRoot.theme.fontPx(1.1)
                        font.weight: Font.DemiBold
                        style: Text.Outline
                        styleColor: pickerRoot.theme.alpha(pickerRoot.theme.surface0, 0.7)
                    }
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
                        textFormat: Text.PlainText
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
