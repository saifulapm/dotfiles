// Tree, visibility and search semantics for the command menu. Near-verbatim
// port of omarchy's plugins/menu/MenuModel.js (CREDITS.md), minus the parts
// that only make sense for their shell: JSONC parsing and source merging (our
// tree is a JS object in MenuTree.js), provider-backed rows, and desktop-app
// rows (our Apps entry hands off to the launcher instead of listing apps).
//
// Everything a caller needs to know about an item is derived here, never
// stored: depth, breadcrumb path, child count, visibility and search rank.

function normalizeAliases(value) {
    if (Array.isArray(value))
        return value.filter(function (v) {
            return v;
        });
    if (typeof value === "string" && value)
        return [value];
    return [];
}

// Kind is inferred like theirs: something to run -> action, a redirect to
// another id -> link, otherwise a submenu. `call` is ours — an action handled
// inside the shell (toggle the launcher, flip DND) rather than by bash.
function normalizeItem(id, raw) {
    var value = raw || {};
    var parent = value.parent;
    if (parent === undefined)
        parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root";
    if (id === "root")
        parent = "";

    var kind = (value.action || value.call) ? "action" : (value.target ? "link" : "menu");

    return {
        id: id,
        parent: parent,
        kind: kind,
        icon: value.icon || "",
        label: value.label || id,
        title: value.title || "",
        target: value.target || "",
        description: value.description || "",
        action: value.action || "",
        call: value.call || "",
        state: value.state || "",
        // Runtime submenu: a provider name from Menu.qml's registry. The row
        // keeps kind "menu" (it opens a list), the rows come from a script.
        provider: value.provider || "",
        aliases: normalizeAliases(value.aliases),
        when: value.when || "",
        checked: value.checked || "",
        order: 0
    };
}

// Declaration order is the display order, so the tree object reads top-down
// exactly as the menu does.
function buildItems(tree) {
    var items = {};
    var order = [];

    items.root = normalizeItem("root", {
        label: "Go"
    });
    order.push("root");

    for (var id in tree) {
        if (id === "root" || !tree[id])
            continue;
        items[id] = normalizeItem(id, tree[id]);
        order.push(id);
    }

    for (var i = 0; i < order.length; i++)
        items[order[i]].order = i;

    return {
        items: items,
        itemOrder: order
    };
}

function item(items, id) {
    return items && items[id] ? items[id] : null;
}

function depthFor(items, id) {
    var depth = 0;
    var current = item(items, id);
    var guard = 0;

    while (current && current.parent && current.parent !== "root" && guard < 32) {
        depth += 1;
        current = item(items, current.parent);
        guard += 1;
    }

    return depth;
}

function pathFor(items, id) {
    var labels = [];
    var current = item(items, id);
    var guard = 0;

    while (current && current.id !== "root" && guard < 32) {
        labels.unshift(current.label);
        current = item(items, current.parent);
        guard += 1;
    }

    return labels.join(" › ");
}

function parentPathFor(items, id) {
    var entry = item(items, id);
    if (!entry || !entry.parent || entry.parent === "root")
        return "";
    return pathFor(items, entry.parent);
}

function isDescendantOf(items, id, ancestorId) {
    if (ancestorId === "root")
        return id !== "root";

    var current = item(items, id);
    var guard = 0;
    while (current && current.parent && guard < 32) {
        if (current.parent === ancestorId)
            return true;
        current = item(items, current.parent);
        guard += 1;
    }

    return false;
}

function childCount(items, itemOrder, id) {
    var count = 0;
    var order = Array.isArray(itemOrder) ? itemOrder : [];
    for (var i = 0; i < order.length; i++) {
        var entry = item(items, order[i]);
        if (entry && entry.parent === id)
            count += 1;
    }
    return count;
}

// Guarded items are hidden when their `when:` evaluated false. A submenu is
// also hidden when none of its descendants survived their own guards, so a
// machine without `foot` never shows an empty Setup.
function isVisible(items, itemOrder, whenResults, entry, depth) {
    if (!entry)
        return false;
    if (entry.when && whenResults && whenResults[entry.id] === false)
        return false;
    if (entry.kind !== "menu" && entry.kind !== "link")
        return true;

    var guard = depth || 0;
    if (guard >= 32)
        return false;

    var target = entry.kind === "link" ? entry.target : entry.id;
    var order = Array.isArray(itemOrder) ? itemOrder : [];
    for (var i = 0; i < order.length; i++) {
        var child = item(items, order[i]);
        if (child && child.parent === target && isVisible(items, itemOrder, whenResults, child, guard + 1))
            return true;
    }

    return false;
}

// Label with the ✓ marker baked in when the row's checked state is truthy.
function labelFor(entry, checkedResults) {
    if (!entry)
        return "";
    if ((entry.checked || entry.state) && checkedResults && checkedResults[entry.id])
        return entry.label + " ✓";
    return entry.label;
}

function searchableToken(value) {
    return String(value || "").replace(/[._-]+/g, " ");
}

function leafIdFor(id) {
    var parts = String(id || "").split(".");
    return parts.length > 0 ? parts[parts.length - 1] : id;
}

// What a query is matched against: the label, the item's own id segment, and
// its aliases — descriptions are matched separately, by whole word only.
function nameSearchText(entry) {
    if (!entry)
        return "";
    var aliases = [];
    var values = Array.isArray(entry.aliases) ? entry.aliases : [];
    for (var i = 0; i < values.length; i++)
        aliases.push(searchableToken(values[i]));
    return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")].join(" ").toLowerCase();
}

function termInSearchWords(term, text) {
    var words = String(text || "").toLowerCase().split(/\s+/);
    for (var i = 0; i < words.length; i++) {
        if (words[i] === term)
            return true;
    }
    return false;
}

function descriptionTextMatches(query, text) {
    var terms = String(query || "").toLowerCase().trim().split(/\s+/);
    for (var i = 0; i < terms.length; i++) {
        if (terms[i] && !termInSearchWords(terms[i], text))
            return false;
    }
    return true;
}

// Every term must hit somewhere — as a substring of the name text, or as a
// whole word of the description. AND across terms, so "theme file" narrows.
function matchesQuery(entry, query, visible) {
    if (!entry || entry.id === "root")
        return false;
    if (!visible)
        return false;

    var nameText = nameSearchText(entry);
    var descriptionText = String(entry.description || "").toLowerCase();
    var terms = String(query || "").toLowerCase().trim().split(/\s+/);

    for (var i = 0; i < terms.length; i++) {
        if (!terms[i])
            continue;
        if (nameText.indexOf(terms[i]) >= 0)
            continue;
        if (termInSearchWords(terms[i], descriptionText))
            continue;
        return false;
    }

    return true;
}

// Lower is better. Tiers are an order of magnitude apart so the tiebreakers
// (shallower first, then declaration order) can never cross a tier.
function searchScore(items, entry, query) {
    var needle = String(query || "").toLowerCase().trim();
    var label = entry.label.toLowerCase();
    var nameText = nameSearchText(entry);
    var descriptionText = String(entry.description || "").toLowerCase();
    var score = 80;

    if (label === needle)
        score = entry.parent === "root" ? 2 : 0;
    else if (label.indexOf(needle) === 0)
        score = 10;
    else if (label.indexOf(needle) >= 0)
        score = 30;
    else if (nameText.indexOf(needle) >= 0)
        score = 40;
    else if (descriptionTextMatches(needle, descriptionText))
        score = 60;

    // A submenu that matches as well as a leaf is the more useful answer:
    // it carries everything under it.
    if (entry.kind === "menu" || entry.kind === "link")
        score -= 2;

    return score * 1000 + depthFor(items, entry.id) * 25 + entry.order;
}

function displayRow(items, itemOrder, checkedResults, entry, detail, score, section) {
    var target = entry.kind === "link" ? entry.target : entry.id;
    return {
        itemId: entry.id,
        kind: entry.kind,
        icon: entry.icon,
        label: labelFor(entry, checkedResults),
        target: target,
        detail: detail || "",
        path: pathFor(items, entry.id),
        childCount: (entry.kind === "menu" || entry.kind === "link") ? childCount(items, itemOrder, target) : 0,
        action: entry.action || "",
        call: entry.call || "",
        score: score || 0,
        section: section || ""
    };
}
