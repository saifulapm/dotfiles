// Near-verbatim port of omarchy's bar TrayModel.js: the rule that
// a tray item belonging to an app the bar already has a dedicated widget for
// is suppressed, so Dropbox is not on the bar twice.
//
// Only the widget id differs — theirs is the plugin id "omarchy.dropbox", ours
// is the registry id "dropbox".
//
// Since 2026-08-10 that widget is the rclone-backed one and no Dropbox daemon
// is installed anywhere, so nothing publishes a Dropbox tray item to suppress.
// The rule stays: it costs one string compare, and it is what keeps a desktop
// client — should one ever be run by hand — off the bar twice.

var DEDICATED_WIDGET_ID = "dropbox";

function text(value) {
    return String(value || "").toLowerCase();
}

function isDropboxTrayItem(item) {
    if (!item)
        return false;
    return text(item.id).indexOf("dropbox") !== -1 || text(item.title).indexOf("dropbox") !== -1 || text(item.tooltipTitle).indexOf("dropbox") !== -1;
}

function entryId(entry) {
    if (typeof entry === "string")
        return entry;
    if (entry && typeof entry === "object") {
        var id = entry.id;
        if (id !== undefined && id !== null && String(id) !== "")
            return String(id);
    }
    return "";
}

function layoutHasWidget(layout, id) {
    var sections = ["left", "center", "right"];
    for (var s = 0; s < sections.length; s++) {
        var entries = layout && layout[sections[s]];
        if (!Array.isArray(entries))
            continue;
        for (var i = 0; i < entries.length; i++) {
            if (entryId(entries[i]) === id)
                return true;
        }
    }
    return false;
}

function ownedByDedicatedWidget(item, layout) {
    return layoutHasWidget(layout, DEDICATED_WIDGET_ID) && isDropboxTrayItem(item);
}

if (typeof module !== "undefined") {
    module.exports = {
        isDropboxTrayItem: isDropboxTrayItem,
        entryId: entryId,
        layoutHasWidget: layoutHasWidget,
        ownedByDedicatedWidget: ownedByDedicatedWidget
    };
}
