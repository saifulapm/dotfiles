// Search over emojis.json. Port of omarchy's plugins/emojis/EmojiSearch.js
// — their semantics exactly, and they are deliberately blunt:
//
//   * every record is {e: "<emoji>", k: "<name and keywords, space separated>"}
//   * the query is trimmed and lowercased, nothing else — no tokenizing
//   * a record matches when the query is a SUBSTRING of its whole `k` text,
//     so "smiling face" matches across the name/keyword boundary and "ing fa"
//     matches too
//   * no ranking: results keep the file's order, which is Unicode group order
//     (faces, people, animals, food, …)
//   * the scan stops at `limit` (1000 by default), so an empty query shows the
//     first 1000 of the 1870 records — everything past that is reachable by
//     typing, exactly as upstream
//
// Whitespace restyled to house 4-space qmlformat; otherwise unchanged.

function parseEmojis(raw) {
    try {
        var data = JSON.parse(String(raw || ""));
        return Array.isArray(data) ? data : [];
    } catch (e) {
        return [];
    }
}

function normalizedQuery(query) {
    return String(query || "").trim().toLowerCase();
}

function keywordText(item) {
    return String((item && item.k) || "").toLowerCase();
}

function filterEmojis(emojis, query, limit) {
    var values = Array.isArray(emojis) ? emojis : [];
    var needle = normalizedQuery(query);
    var max = limit === undefined || limit === null ? 1000 : Number(limit);
    if (isNaN(max))
        max = 1000;
    max = Math.max(0, max);
    if (max === 0)
        return [];

    var out = [];

    for (var i = 0; i < values.length; i++) {
        var item = values[i];
        if (!item || !item.e)
            continue;
        if (!needle || keywordText(item).indexOf(needle) >= 0) {
            out.push(item);
            if (out.length >= max)
                break;
        }
    }

    return out;
}

if (typeof module !== "undefined") {
    module.exports = {
        parseEmojis: parseEmojis,
        normalizedQuery: normalizedQuery,
        filterEmojis: filterEmojis
    };
}
