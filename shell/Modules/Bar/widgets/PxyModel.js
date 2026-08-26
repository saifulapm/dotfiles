// pxy panel helpers — kept out of the QML the way AiModel.js is.

// "opencode-go-github/minimax-m3" -> "minimax-m3"; the provider is shown
// separately, and zenmux-style ids keep their vendor path ("deepseek/…").
function modelName(id) {
    const raw = String(id || "");
    const slash = raw.indexOf("/");
    return slash >= 0 ? raw.slice(slash + 1) : raw;
}

function providerOf(id) {
    const raw = String(id || "");
    const slash = raw.indexOf("/");
    return slash >= 0 ? raw.slice(0, slash) : "";
}

// Does every character of `needle` appear in `hay`, in order? PassModel's
// subsequence matcher, so "mmx3" finds "opencode-go-github/minimax-m3" the
// way "ghb" finds "web/github.com" in the password panel.
function subsequence(hay, needle) {
    let h = 0;
    for (let n = 0; n < needle.length; n++) {
        let found = -1;
        while (h < hay.length) {
            if (hay.charAt(h) === needle.charAt(n)) {
                found = h;
                h++;
                break;
            }
            h++;
        }
        if (found === -1)
            return 0;
    }
    return 1;
}

// PassModel's bands, on ids: exact > model-name prefix > full-id prefix >
// substring > subsequence. 0 = no match. Bands rather than gap scoring, for
// the same reason as there — a couple hundred ids, and exact/prefix on top
// is all the ordering anyone can perceive.
function searchScore(id, needle) {
    const full = String(id).toLowerCase();
    const leaf = modelName(id).toLowerCase();
    if (leaf === needle || full === needle)
        return 500;
    if (leaf.indexOf(needle) === 0)
        return 400;
    if (full.indexOf(needle) === 0)
        return 300;
    if (full.indexOf(needle) !== -1)
        return 200;
    return subsequence(full, needle) * 100;
}

// The picker's rows. Without a query: the auto chain in walk order (that IS
// the eligibility view). With one: a fuzzy filter over the whole catalog —
// anything `pxy models` knows is pinnable, chain member or not — best
// matches first, catalog order breaking ties inside a band.
function pickerRows(chain, models, query, maxRows) {
    const q = String(query || "").trim().toLowerCase();
    if (q === "") {
        return {
            rows: (chain || []).slice(0, maxRows),
            hidden: Math.max(0, (chain || []).length - maxRows)
        };
    }
    const byId = {};
    for (let i = 0; i < (chain || []).length; i++)
        byId[chain[i].id] = chain[i];
    const scored = [];
    for (let i = 0; i < (models || []).length; i++) {
        const id = String(models[i]);
        const s = searchScore(id, q);
        if (s === 0)
            continue;
        // A chain member keeps its verdict; the rest are plain catalog rows.
        scored.push({
            score: s,
            order: i,
            row: byId[id] || { id: id, eligible: true, pinned: false, skips: [], notes: [] }
        });
    }
    scored.sort((a, b) => (b.score - a.score) || (a.order - b.order));
    const rows = scored.map(e => e.row);
    return {
        rows: rows.slice(0, maxRows),
        hidden: Math.max(0, rows.length - maxRows)
    };
}

function rowCaption(row) {
    if (!row)
        return "";
    if ((row.skips || []).length > 0)
        return row.skips.join(" · ");
    return (row.notes || []).join(" · ");
}

function formatSeconds(s) {
    const n = Number(s || 0);
    if (n <= 0)
        return "now";
    if (n >= 3600)
        return Math.floor(n / 3600) + "h " + Math.floor((n % 3600) / 60) + "m";
    if (n >= 60)
        return Math.floor(n / 60) + "m " + (n % 60) + "s";
    return n + "s";
}
