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

// One picker row, merging what routing knows about a model (its verdict in
// the chain being viewed) with what the catalogue knows (provider, context
// window, price, which chains route to it). `entry` is the `pxy models --json`
// record and may be missing for a model no longer in the catalogue.
function decorated(row, entry) {
    return {
        id: row.id,
        // Multi-account providers expand into one row per account; the
        // account name is what keeps two same-model rows distinguishable.
        account: row.account || "",
        eligible: row.eligible !== false,
        pinned: row.pinned === true,
        skips: row.skips || [],
        notes: row.notes || [],
        provider: (entry && entry.provider) || providerOf(row.id),
        context: entry ? Number(entry.context || 0) : 0,
        free: entry ? entry.free : null,
        groups: (entry && entry.groups) || []
    };
}

function indexById(models) {
    const out = {};
    for (let i = 0; i < (models || []).length; i++)
        out[String(models[i].id)] = models[i];
    return out;
}

// The picker's rows. Without a query: the selected group's chain in walk
// order (that IS the eligibility view). With one: a fuzzy filter over the
// whole catalog — anything `pxy models` knows is pinnable, chain member or
// not — best matches first, catalog order breaking ties inside a band.
function pickerRows(chain, models, query, maxRows) {
    const q = String(query || "").trim().toLowerCase();
    const meta = indexById(models);
    if (q === "") {
        const rows = (chain || []).slice(0, maxRows).map(r => decorated(r, meta[r.id]));
        return { rows: rows, hidden: Math.max(0, (chain || []).length - maxRows) };
    }
    const byId = {};
    for (let i = 0; i < (chain || []).length; i++)
        byId[chain[i].id] = chain[i];
    const scored = [];
    for (let i = 0; i < (models || []).length; i++) {
        const id = String(models[i].id);
        const s = searchScore(id, q);
        if (s === 0)
            continue;
        // A chain member keeps its verdict; the rest are plain catalog rows.
        scored.push({
            score: s,
            order: i,
            row: decorated(byId[id] || { id: id }, models[i])
        });
    }
    scored.sort((a, b) => (b.score - a.score) || (a.order - b.order));
    const rows = scored.map(e => e.row);
    return {
        rows: rows.slice(0, maxRows),
        hidden: Math.max(0, rows.length - maxRows)
    };
}

// Context window, compact: 1M / 256K / 8K. Providers quote windows in both
// bases — 131072 and 128000 are BOTH sold as "128k" — so divide by whichever
// one the number is an exact multiple of, decimal first. Plain /1000 would
// print a 32768 window as "33K" and a 262144 one as "262K", numbers that
// appear on no spec sheet. The decimal AiModel's formatTokenCount keeps (it
// counts arbitrary usage) is noise on a round window, but stays above the
// megatoken or 1M and 1.5M would read alike.
function contextLabel(n) {
    const v = Number(n || 0);
    if (v <= 0)
        return "";
    const k = v % 1000 === 0 ? 1000 : (v % 1024 === 0 ? 1024 : 1000);
    if (v >= k * k) {
        const m = (v / (k * k)).toFixed(1);
        return (m.slice(-2) === ".0" ? m.slice(0, -2) : m) + "M";
    }
    if (v >= k)
        return Math.round(v / k) + "K";
    return String(v);
}

// Under a row: why it would be skipped beats what it costs. A chain member
// always carries routing notes; a plain catalog hit has none, so it falls
// back to the facts that decide whether you want it at all.
function rowCaption(row) {
    if (!row)
        return "";
    if ((row.skips || []).length > 0)
        return row.skips.join(" · ");
    if ((row.notes || []).length > 0)
        return row.notes.join(" · ");
    const bits = [];
    if (row.free === true)
        bits.push("free");
    else if (row.free === false)
        bits.push("paid");
    if ((row.groups || []).length > 0)
        bits.push("in " + row.groups.join(", "));
    return bits.join(" · ");
}

// The whole line under a model: what it IS (provider, context window) before
// how it is doing (skip reason, price, chains). The two stable facts lead so
// the column reads down consistently while verdicts change underneath.
function rowSubtitle(row) {
    if (!row)
        return "";
    const bits = [];
    const provider = row.provider || providerOf(row.id);
    if (provider)
        bits.push(provider);
    const ctx = contextLabel(row.context);
    if (ctx)
        bits.push(ctx);
    const caption = rowCaption(row);
    if (caption)
        bits.push(caption);
    return bits.join("  ·  ");
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
