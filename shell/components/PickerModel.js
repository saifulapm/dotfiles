// Port of omarchy's shell/plugins/image-picker/ImagePickerModel.js
// (CREDITS.md) — the picker's whole non-visual half: row parsing with the
// basename dedup that merges two directories, the basename → spaced → title
// case label, the substring filter and the filtered-position math the
// carousel lays itself out with.
//
// Shared by both pickers built on FilmstripPicker (wallpapers, themes), so
// the filter reads a tile's precomputed `key`/`label` rather than re-deriving
// them from a file path — a theme tile has a name but no image of its own.

function nameForPath(path) {
    return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "");
}

function labelForPath(path) {
    return nameForPath(path).replace(/[-_]+/g, " ").replace(/\b\w/g, function (match) {
        return match.toUpperCase();
    });
}

// Their tab-separated `<image>\t<thumbnail>` rows → picker tiles.
function loadRows(rows) {
    var images = [];
    var seen = {};
    var paths = String(rows || "").split("\n");

    for (var i = 0; i < paths.length; i++) {
        var row = paths[i];
        if (!row)
            continue;

        var columns = row.split("\t");
        var path = columns[0];
        if (!path)
            continue;

        var fileName = path.split("/").pop();
        if (seen[fileName])
            continue;
        seen[fileName] = true;

        images.push({
            key: nameForPath(path),
            label: labelForPath(path),
            filePath: path,
            fileName: fileName,
            imagePath: columns[1] || path
        });
    }

    return images;
}

function itemMatches(items, index, filterText) {
    if (!Array.isArray(items) || index < 0 || index >= items.length)
        return false;
    var needle = String(filterText || "").toLowerCase();
    if (!needle)
        return true;

    var item = items[index] || {};
    return String(item.key || "").toLowerCase().indexOf(needle) !== -1 || String(item.label || "").toLowerCase().indexOf(needle) !== -1;
}

function firstMatchingIndex(items, filterText) {
    var values = Array.isArray(items) ? items : [];
    for (var i = 0; i < values.length; i++) {
        if (itemMatches(values, i, filterText))
            return i;
    }

    return -1;
}

function filteredPosition(items, index, filterText) {
    if (!filterText)
        return index;

    var position = 0;
    for (var i = 0; i < index; i++) {
        if (itemMatches(items, i, filterText))
            position++;
    }

    return position;
}

function selectedFilteredPosition(items, selectedIndex, filterText) {
    if (!filterText)
        return selectedIndex;
    return itemMatches(items, selectedIndex, filterText) ? filteredPosition(items, selectedIndex, filterText) : 0;
}

function indexForSelectedImage(items, selectedImage) {
    var values = Array.isArray(items) ? items : [];
    for (var i = 0; i < values.length; i++) {
        if (values[i].filePath === selectedImage)
            return i;
    }

    return 0;
}

// Their --selected, addressed by name instead of by file: the theme switcher
// hands them a preview image whose basename IS the theme name.
function indexForKey(items, key) {
    var values = Array.isArray(items) ? items : [];
    for (var i = 0; i < values.length; i++) {
        if (values[i].key === key)
            return i;
    }

    return 0;
}

function nextSelectedIndexForFilter(items, selectedIndex, filterText) {
    if (itemMatches(items, selectedIndex, filterText))
        return selectedIndex;
    return firstMatchingIndex(items, filterText);
}

// Their Util.editsFilter / Util.editedFilter, kept next to the filter they
// edit: backspace (char / word) and Ctrl+U, never with Alt or Meta held.
function editsFilter(event, text) {
    if (!text)
        return false;
    if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
        return false;
    if (event.key === Qt.Key_U)
        return event.modifiers === Qt.ControlModifier;
    return event.key === Qt.Key_Backspace;
}

function editedFilter(event, text) {
    if (event.key === Qt.Key_U)
        return "";
    if (event.modifiers & Qt.ControlModifier)
        return text.replace(/\s+$/, "").replace(/\S+$/, "");
    return text.slice(0, -1);
}
