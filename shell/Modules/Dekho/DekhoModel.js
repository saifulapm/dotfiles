// Pure helpers for the dekho hub — no QML types, so they are unit-checkable
// and the QML stays layout. Same split as MenuModel.js / WeatherModel.js.
.pragma library

// The posters a listing needs, deduplicated and with the empties dropped —
// what gets handed to `dekho api prefetch` as one argv.
function posterArgs(items, field) {
    const seen = {};
    const out = [];
    for (let i = 0; i < items.length; i++) {
        const p = items[i] && items[i][field];
        if (!p || seen[p])
            continue;
        seen[p] = true;
        out.push(p);
    }
    return out;
}

// One list out of two, alternating. `dekho api discover` cannot take
// kind=all — TMDB's discover endpoint is per-kind and so is dekho's flag — so
// the library's ALL is a movie page and a series page fetched together and
// zipped. Alternating rather than concatenating is the whole point: a
// concatenated list is a page of films followed by a page of series, which is
// the two rails this design replaced with extra steps.
function interleave(a, b) {
    const left = a || [];
    const right = b || [];
    const out = [];
    for (let i = 0; i < Math.max(left.length, right.length); i++) {
        if (i < left.length)
            out.push(left[i]);
        if (i < right.length)
            out.push(right[i]);
    }
    return out;
}

// ------------------------------------------------------------------ labels

function ratingLabel(vote) {
    const v = Number(vote);
    if (!isFinite(v) || v <= 0)
        return "";
    return v.toFixed(1);
}

function kindLabel(kind) {
    return kind === "tv" ? "Series" : "Movie";
}

// "2026 · Series · ★ 8.2" — the one summary line, shared by the hero and the
// detail header so a title reads the same wherever it is summarized.
function metaLine(item) {
    if (!item)
        return "";
    const bits = [];
    if (item.year)
        bits.push(String(item.year));
    if (item.kind)
        bits.push(kindLabel(item.kind));
    const r = ratingLabel(item.vote);
    if (r)
        bits.push("★ " + r);
    return bits.join("  ·  ");
}

// "S02E05" — the shorthand every episode row and resume line uses.
function episodeCode(season, episode) {
    if (season === null || season === undefined || episode === null || episode === undefined)
        return "";
    return "S" + pad2(season) + "E" + pad2(episode);
}

function pad2(n) {
    const s = String(Math.max(0, Math.floor(Number(n) || 0)));
    return s.length >= 2 ? s : "0" + s;
}

// Runtime in seconds to "2h 19m" / "48m". Zero and unknown collapse to "".
function durationLabel(secs) {
    const s = Math.floor(Number(secs) || 0);
    if (s <= 0)
        return "";
    const h = Math.floor(s / 3600);
    const m = Math.round((s % 3600) / 60);
    if (h <= 0)
        return m + "m";
    return m > 0 ? h + "h " + m + "m" : h + "h";
}

// What is left of a title you are part-way through: "48m left".
function remainingLabel(position, duration) {
    const left = Math.floor(Number(duration) || 0) - Math.floor(Number(position) || 0);
    if (left <= 0)
        return "";
    return durationLabel(left) + " left";
}

// The line under a Continue-watching poster: the episode you are in the
// middle of, or how much of the film is left.
function resumeLabel(entry) {
    if (!entry)
        return "";
    if (entry.kind === "tv" && entry.season !== null && entry.season !== undefined) {
        const code = episodeCode(entry.season, entry.episode);
        return entry.episode_name ? code + " · " + entry.episode_name : code;
    }
    return remainingLabel(entry.position, entry.duration);
}

// The short pill in a card's top-left corner. omakade puts a completion state
// there ("PLAYING", "COMPLETED"); the useful fact here is where you stopped —
// the episode for a series, and for a film just that there is something to pick
// up. A catalog row has neither and gets no pill, which is what keeps the pill
// meaning something when it appears.
function statusPill(entry) {
    if (!entry)
        return "";
    if (entry.kind === "tv" && entry.season !== null && entry.season !== undefined)
        return episodeCode(entry.season, entry.episode);
    return progressOf(entry) > 0.01 ? "RESUME" : "";
}

// 0..1, clamped. Anything without a duration reads as "not started" rather
// than as a full bar.
function progressOf(entry) {
    if (!entry)
        return 0;
    const p = Number(entry.progress);
    if (isFinite(p) && p > 0)
        return Math.max(0, Math.min(1, p));
    const pos = Number(entry.position) || 0;
    const dur = Number(entry.duration) || 0;
    if (dur <= 0)
        return 0;
    return Math.max(0, Math.min(1, pos / dur));
}

// ------------------------------------------------------------------- bytes

function formatBytes(n) {
    const b = Number(n) || 0;
    if (b <= 0)
        return "";
    const units = ["B", "KB", "MB", "GB", "TB"];
    let v = b;
    let i = 0;
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024;
        i++;
    }
    return (v >= 10 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
}

// Bits per second the way the CLI prints it, so the panel and a terminal run
// describe the same swarm identically.
function formatBps(bps) {
    const v = Number(bps) || 0;
    if (v <= 0)
        return "";
    if (v >= 1000000)
        return (v / 1000000).toFixed(1) + " Mbps";
    return Math.round(v / 1000) + " kbps";
}

// ------------------------------------------------------- playback events
// One NDJSON line from `dekho play --json` to the two things the playback
// view draws: a headline and, while a swarm is being measured, a meter.
// Unknown events return null so a newer dekho can add one without this
// having to know about it.
function describeEvent(ev) {
    if (!ev || !ev.event)
        return null;
    switch (ev.event) {
    case "status":
        return {
            text: String(ev.text || ""),
            kind: "status"
        };
    case "releases":
        return {
            text: ev.found + " releases · " + (ev.dual || 0) + " dual audio",
            kind: "status"
        };
    case "title-guard":
        // Releases filed under this title's IMDB id whose names say they are
        // a different production entirely — dekho drops them before ranking.
        return {
            text: "Ignoring " + ev.dropped + " release" + (ev.dropped === 1 ? "" : "s") + " named like a different title",
            kind: "warn"
        };
    case "trying":
        return {
            text: "Trying " + ev.quality + " · " + (ev.size || "size unknown") + " · " + ev.seeders + " seeder" + (ev.seeders === 1 ? "" : "s") + (ev.audio ? " · " + ev.audio : ""),
            kind: "status"
        };
    case "buffer":
        return {
            // The first ticks of a swarm carry zero bytes at zero rate, and
            // formatBytes/formatBps collapse zeros to "" — which rendered as
            // the literal "Buffering  at ". Say what is true instead.
            text: Number(ev.buffered) > 0 && Number(ev.rate_bps) > 0 ? "Buffering " + formatBytes(ev.buffered) + " at " + formatBps(ev.rate_bps) : "Buffering — waiting for the first pieces…",
            kind: "buffer",
            // The gate dekho itself applies: 1.25x the release's own bitrate.
            // Showing the ratio is what makes a slow swarm legible rather
            // than just slow.
            ratio: ev.needed_bps > 0 ? Number(ev.rate_bps) / Number(ev.needed_bps) : 0,
            peers: Number(ev.live_peers) || 0,
            // Carried as numbers as well as inside `text`, because the playback
            // screen now states them as their own tiles — omakade's 3-up fact
            // grid — and slicing them back out of a display string would break
            // the first time the wording changed. Same reason `playing` carries
            // its title.
            rate: Number(ev.rate_bps) || 0,
            buffered: Number(ev.buffered) || 0
        };
    case "ready":
        return {
            text: "Ready · " + formatBytes(ev.buffered) + " buffered at " + formatBps(ev.rate_bps),
            kind: "ok"
        };
    case "downgrade":
        return {
            text: "Too slow at " + formatBps(ev.rate_bps) + " — trying a lighter release",
            kind: "warn"
        };
    case "playing":
        return {
            text: "Playing " + String(ev.title || ""),
            kind: "playing",
            // Carried separately, not sliced back out of `text`, because a run
            // this panel ADOPTED rather than started has no label of its own —
            // play() is where that is normally set, and a panel reopened
            // mid-film never ran it. The trail is the only place the title
            // survives, and prefix-stripping a display string to recover it
            // would break the first time the wording changed.
            title: String(ev.title || "")
        };
    case "queued":
        return {
            text: "Queued " + episodeCode(ev.season, ev.episode) + (ev.name ? " · " + ev.name : ""),
            kind: "status"
        };
    case "dry-run":
        return {
            text: "Would play " + String(ev.title || ""),
            kind: "ok"
        };
    case "error":
        return {
            text: String(ev.text || "playback failed"),
            kind: "error"
        };
    case "exit":
        return {
            text: "",
            kind: "exit",
            code: Number(ev.code) || 0
        };
    default:
        return null;
    }
}

// The playback screen's fact tiles — omakade's 3-up grid, over the numbers the
// buffer events carry. Empty while there is nothing measured yet and empty once
// the run is over, because a swarm nobody is downloading from has no rate and
// stating its last one as a fact would be the frozen-meter bug the ended state
// exists to prevent.
function swarmTiles(session, ended) {
    if (!session || ended)
        return [];
    const out = [];
    if (Number(session.buffered) > 0)
        out.push({
            label: "BUFFERED",
            value: formatBytes(session.buffered)
        });
    if (Number(session.rate) > 0)
        out.push({
            label: "RATE",
            value: formatBps(session.rate)
        });
    if (Number(session.peers) > 0)
        out.push({
            label: "PEERS",
            value: String(session.peers)
        });
    return out;
}

// ---------------------------------------------------------------- people
// TMDB has no photo for a great many people, and a broken-image mark for a
// third of a cast shelf is worse than no shelf. The fallback is the initials,
// which is also what every contacts app does with the same problem.
function initials(name) {
    const parts = String(name || "").trim().split(/\s+/).filter(p => p !== "");
    if (parts.length === 0)
        return "?";
    if (parts.length === 1)
        return parts[0].charAt(0).toUpperCase();
    return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
}

// The crew rows worth naming above a film, in the order a poster credits them.
// `crew` arrives deduplicated by dekho but a person can hold two of these jobs
// (Nolan writes and directs), so the same id is kept once with both jobs
// joined rather than twice.
const CREW_ORDER = ["Creator", "Director", "Writer", "Screenplay", "Composer"];

function leadCrew(crew) {
    const byId = {};
    const out = [];
    for (let i = 0; i < (crew || []).length; i++) {
        const c = crew[i];
        if (!c || !c.name)
            continue;
        const rank = CREW_ORDER.indexOf(String(c.job || ""));
        if (rank < 0)
            continue;
        const key = String(c.id);
        if (byId[key] !== undefined) {
            const seen = out[byId[key]];
            if (seen.job.indexOf(c.job) < 0)
                seen.job += " · " + c.job;
            seen.rank = Math.min(seen.rank, rank);
            continue;
        }
        byId[key] = out.length;
        out.push({
            id: c.id,
            name: c.name,
            profile: c.profile || "",
            job: String(c.job || ""),
            rank: rank
        });
    }
    out.sort((a, b) => a.rank - b.rank);
    return out;
}

// "1970–2014", "1963–" or "" — one line, because two InfoPairs for a birth and
// a death that most people only have one of reads as a form.
function lifeLabel(person) {
    if (!person)
        return "";
    const born = yearOf(person.birthday);
    const died = yearOf(person.deathday);
    if (!born && !died)
        return "";
    if (died)
        return (born || "?") + "–" + died;
    return born + "–";
}

function yearOf(iso) {
    const m = String(iso || "").match(/^(\d{4})/);
    return m ? m[1] : "";
}

// ----------------------------------------------------------------- facts
// TMDB dates are ISO. Rendering them as ISO in a cinematic page reads as a
// database row, and Qt.formatDate would need a QML type in here.
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function dateLabel(iso) {
    const m = String(iso || "").match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!m)
        return String(iso || "");
    const month = MONTHS[Number(m[2]) - 1] || m[2];
    return Number(m[3]) + " " + month + " " + m[1];
}

// "$165M", "$2.9B". Budgets and revenues are the two TMDB numbers nobody reads
// digit by digit, and the raw figure is nine characters of noise in a pair.
function moneyLabel(n) {
    const v = Math.floor(Number(n) || 0);
    if (v <= 0)
        return "";
    if (v >= 1e9)
        return "$" + (v / 1e9).toFixed(1) + "B";
    if (v >= 1e6)
        return "$" + Math.round(v / 1e6) + "M";
    if (v >= 1e3)
        return "$" + Math.round(v / 1e3) + "K";
    return "$" + v;
}

// studios[], countries[], languages[], networks[] — dekho may answer with
// plain strings or with {name}/{english_name} objects depending on what TMDB
// gave it, and a page that renders "[object Object]" is worse than one that
// renders nothing.
function nameList(arr, limit) {
    const out = [];
    for (let i = 0; i < (arr || []).length; i++) {
        const v = arr[i];
        if (v === null || v === undefined)
            continue;
        const name = typeof v === "object" ? String(v.name || v.english_name || v.title || "") : String(v);
        if (name !== "" && out.indexOf(name) < 0)
            out.push(name);
    }
    const capped = limit > 0 ? out.slice(0, limit) : out;
    return capped.join(", ");
}

// The StatTile grid on a title page: {label, value} in the order a person asks
// for them, three across. Anything TMDB left empty simply is not a tile — a
// grid of "—" says nothing and costs a card each.
//
// IT LIVES HERE RATHER THAN IN THE BINDING THAT USES IT, and not only because
// this module keeps its arithmetic out of its layout. qmlformat in this Qt
// build ABORTS on a `function` declared inside a binding block — measured
// 2026-09-01, SIGABRT with a core dump on a six-line reduction — and `just fmt`
// runs `qmlformat -i`, so writing this loop where it is read would have
// truncated the file the first time anyone formatted the tree.
function titleFacts(t) {
    if (!t)
        return [];
    const out = [];
    const add = function (label, value) {
        if (value !== undefined && value !== null && String(value) !== "")
            out.push({
                label: label,
                value: String(value).toUpperCase()
            });
    };
    add("RUNTIME", durationLabel(t.runtime));
    const rating = ratingLabel(t.vote);
    add("RATING", rating ? "★ " + rating : "");
    add("STATUS", t.status || (t.in_production === true ? "In production" : ""));
    if (t.kind === "tv") {
        const seasons = Number(t.season_count) || 0;
        const eps = Number(t.episode_count) || 0;
        add("SEASONS", seasons > 0 ? seasons + (eps > 0 ? "  ·  " + eps + " episodes" : "") : "");
        add("NETWORK", nameList(t.networks, 2));
        add("FIRST AIRED", dateLabel(t.first_air));
        add("LAST AIRED", dateLabel(t.last_air));
    } else {
        add("RELEASED", dateLabel(t.release_date));
        add("BUDGET", moneyLabel(t.budget));
        add("REVENUE", moneyLabel(t.revenue));
    }
    add("STUDIO", nameList(t.studios, 2));
    add("LANGUAGE", nameList(t.languages, 2));
    add("COUNTRY", nameList(t.countries, 3));
    return out;
}

// ---------------------------------------------------------------- browse
// The filter vocabulary, in one place because the sidebar renders it and the
// discover argv is built from it. `key` is what `dekho api discover` is given
// verbatim; "" means the facet is not constrained and the flag is omitted.
const SORT_CHOICES = [
    {
        key: "popular",
        label: "Popular"
    },
    {
        key: "top-rated",
        label: "Top rated"
    },
    {
        key: "newest",
        label: "Newest"
    },
    {
        key: "oldest",
        label: "Oldest"
    },
    {
        key: "box-office",
        label: "Box office"
    }
];

const RATING_CHOICES = [
    {
        key: "",
        label: "Any"
    },
    {
        key: "6",
        label: "6+"
    },
    {
        key: "7",
        label: "7+"
    },
    {
        key: "8",
        label: "8+"
    }
];

// Decades rather than years: a year picker is a scroll of eighty rows for a
// question nobody asks that precisely. `--year` takes YYYY or YYYY-YYYY.
const YEAR_CHOICES = [
    {
        key: "",
        label: "Any"
    },
    {
        key: "2020-2029",
        label: "2020s"
    },
    {
        key: "2010-2019",
        label: "2010s"
    },
    {
        key: "2000-2009",
        label: "2000s"
    },
    {
        key: "1990-1999",
        label: "1990s"
    },
    {
        key: "1980-1989",
        label: "1980s"
    },
    {
        key: "1970-1979",
        label: "1970s"
    }
];

// `--genre` takes a name or an id, and this module hands it both: the browse
// sidebar knows the ids (it fetched the list) while a genre chip on a detail
// page only ever had the name TMDB printed on the title. Normalising to the id
// as soon as the list is available means one filter value, one comparison, and
// a sidebar that shows the arriving genre as chosen instead of as a stranger.
function genreValue(genres, value) {
    const v = String(value || "");
    if (v === "")
        return "";
    for (let i = 0; i < (genres || []).length; i++) {
        const g = genres[i];
        if (String(g.id) === v || String(g.name).toLowerCase() === v.toLowerCase())
            return String(g.id);
    }
    return v;
}

function genreLabel(genres, value) {
    const v = String(value || "");
    if (v === "")
        return "";
    for (let i = 0; i < (genres || []).length; i++) {
        const g = genres[i];
        if (String(g.id) === v || String(g.name).toLowerCase() === v.toLowerCase())
            return String(g.name);
    }
    return v;
}

function languageLabel(languages, code) {
    const v = String(code || "");
    if (v === "")
        return "";
    for (let i = 0; i < (languages || []).length; i++)
        if (String(languages[i].code) === v)
            return String(languages[i].name);
    return v;
}

function choiceLabel(choices, key) {
    for (let i = 0; i < choices.length; i++)
        if (choices[i].key === key)
            return choices[i].label;
    return key === "" ? "Any" : String(key);
}

// The argv after `dekho api discover`. Every facet is omitted when unset, so a
// browse with nothing chosen is exactly the call the hub's catalog rails make.
function discoverArgs(f) {
    const args = ["discover", "--kind", f.kind === "tv" ? "tv" : "movie", "--sort", f.sort || "popular"];
    if (f.genre)
        args.push("--genre", String(f.genre));
    if (f.lang)
        args.push("--lang", String(f.lang));
    if (f.minRating)
        args.push("--min-rating", String(f.minRating));
    if (f.year)
        args.push("--year", String(f.year));
    if (f.cast)
        args.push("--cast", String(f.cast));
    if (f.page > 1)
        args.push("--page", String(f.page));
    return args;
}

// What the header says the results are, in the same voice as the hub's rail
// captions: "Movies · Top rated · Action · 2010s". A person scope leads,
// because "Edward Norton · Movies · 1990s" is the sentence, not a facet.
function browseCaption(f, genreName, langName, castName) {
    const bits = [];
    if (castName)
        bits.push(castName);
    bits.push(f.kind === "tv" ? "Series" : "Movies", choiceLabel(SORT_CHOICES, f.sort));
    if (genreName)
        bits.push(genreName);
    if (langName)
        bits.push(langName);
    if (f.minRating)
        bits.push("★ " + f.minRating + "+");
    if (f.year)
        bits.push(choiceLabel(YEAR_CHOICES, f.year));
    return bits.join("  ·  ");
}

// ------------------------------------------------------------ navigation
// Grid arithmetic shared by the search grid and the rails. Kept here because
// the off-by-one at the row edges is the part worth testing.

function gridStep(index, delta, count, columns) {
    if (count <= 0)
        return 0;
    const next = index + delta * columns;
    if (next < 0 || next >= count)
        return index;
    return next;
}

function clampIndex(index, count) {
    if (count <= 0)
        return 0;
    return Math.max(0, Math.min(count - 1, index));
}

// TAB IS "THE NEXT THING", on every screen in this module: +1 forward, -1
// back, 0 for anything else. The arrows keep their 2D meaning — along a rail,
// across a row, between bands — and Tab flattens whatever the screen is into
// one order, so it can be walked without knowing its shape.
//
// Both spellings, because Shift+Tab is not one key: Qt normally delivers it as
// Key_Backtab, but a Key_Tab carrying ShiftModifier reaches here on some
// paths, and a Tab that silently went forwards when shifted would be worse
// than no Tab at all. Every other modifier is somebody else's chord.
function tabDelta(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        return 0;
    if (event.key === Qt.Key_Backtab)
        return -1;
    if (event.key !== Qt.Key_Tab)
        return 0;
    return (event.modifiers & Qt.ShiftModifier) ? -1 : 1;
}
