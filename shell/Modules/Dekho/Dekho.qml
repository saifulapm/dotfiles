import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "components"
import "screens"
import "DekhoModel.js" as Model

// The movie hub: what you are part-way through, what is trending, what to
// search for, and one keypress to put it in mpv. Every byte of it comes from
// `dekho api` (github.com/saifulapm/dekho) — the shell speaks no HTTP and holds
// no TMDB key, and the same binary answers the same questions from a terminal.
//
// Nothing here exists until the surface is summoned, and the loader in shell.qml
// marks it `evictable`: a hub that has been closed for the grace period releases
// its whole tree, which is what keeps sixty decoded posters from being a
// permanent line in the shell's RSS. That is also why every open re-fetches
// rather than caching in memory — the poster files are already on disk (dekho's
// own cache), so a warm reopen paints immediately.
//
// PLAYBACK IS NOT OUR CHILD. `dekho play` is started as a transient systemd user
// unit by bin/dekho-play, outside this process's cgroup, because qshell.service's
// KillMode=control-group would otherwise kill a film in progress every time the
// shell restarts. The panel follows the run by tailing the NDJSON it writes.
//
// AND IT IS AN ORDINARY WINDOW, not a layer-shell overlay — see the
// FloatingWindow below for what that bought and what it cost.
//
// ---------------------------------------------------------------- the design
//
// The presentation is a PORT of omakade (github.com/tsouth89/omakade, GPL-3.0),
// a game library built on the same Qt 6 + QML this shell runs — so its
// components arrived as code rather than as inspiration. The user's ask was
// exact: "I like omakade design so our design should be exactly same to same."
//
// What that deleted, knowingly: the backdrop hero that followed the cursor, the
// horizontal rails, and the whole separate Browse screen. What it brought: one
// grid, a toolbar that says what the grid is showing, and REAL QT FOCUS — every
// control is a QtQuick.Controls Button or TextField, so Tab walks a screen, the
// keyboard and the pointer cannot disagree about what is lit, and the module's
// hand-rolled cursor per screen is gone. Style.qml is the translation layer:
// omakade's literals stay at the call sites and go through ui() and type().
Scope {
    id: dekhoRoot

    required property var theme

    // OPEN IS THE WINDOW'S OWN VISIBILITY, not a flag kept beside it. niri's
    // close-window (Mod+Q) unmaps a toplevel by WRITING visible=false on it,
    // which would silently break a `visible: opened` binding the other way round
    // and strand `opened` at true for ever — the surface would then never satisfy
    // SurfaceLoader's "closed" test and its whole tree, sixty decoded posters
    // included, would stay resident (shell.qml's residency policy).
    readonly property bool opened: panel.visible
    // Whether the window has the keyboard. A layer surface with an exclusive grab
    // was either up and holding everything or not up at all; a toplevel has a
    // third state — mapped, but behind something or on another workspace — and
    // that is the state toggle() has to tell apart.
    readonly property bool focused: panel.visible && keyRoot.Window.active

    // omakade's theme singleton and its 1380x880 scale, spoken in this shell's
    // tokens. Read Style.qml before any other file here — it is the translation
    // layer every other file in the module depends on.
    readonly property var style: Style {
        theme: dekhoRoot.theme
        windowWidth: panel.width
        windowHeight: panel.height
    }

    // ------------------------------------------------------------ the stack
    // NAVIGATION IS A STACK, NOT A MODE, and it survived the redesign for the
    // reason doc §11 gives: a cast face opens a person, a person opens a title,
    // that title's genre filters the library, and there is no single "home" to
    // fall back to from four screens in. omakade has no back stack because it has
    // one screen and one dialog; this graph needs one, and it is invisible to the
    // design either way.
    //
    // Every entry is a plain object with a `view` and whatever identifies the
    // screen. The LIVE state of the screen on top stays in the ordinary
    // properties below, because that is what the screens bind to; push()
    // snapshots it into the entry being buried and pop() reads it back.
    property var navStack: [
        {
            view: "library"
        }
    ]
    readonly property var route: navStack.length > 0 ? navStack[navStack.length - 1] : ({
            view: "library"
        })
    // "library" | "title" | "person" | "playback". The search results replace the
    // grid's contents rather than being a view of their own — the toolbar stays
    // in the same place either way, so they are the same screen.
    readonly property string view: String(route.view || "library")

    function push(entry) {
        captureTop();
        navStack = navStack.concat([entry]);
    }

    function pop() {
        // The library is the bottom of the stack, and popping it is what closing
        // the panel means — Escape from the library has always closed.
        if (navStack.length <= 1) {
            hide();
            return;
        }
        navStack = navStack.slice(0, navStack.length - 1);
        restoreTop();
    }

    function goHome() {
        navStack = [
            {
                view: "library"
            }
        ];
    }

    function captureTop() {
        const r = navStack.length > 0 ? navStack[navStack.length - 1] : null;
        if (!r)
            return;
        switch (r.view) {
        case "library":
            r.mode = mode;
            r.kind = kind;
            r.query = library.query;
            r.sortKey = sortKey;
            r.genre = genre;
            r.year = year;
            r.minRating = minRating;
            r.language = language;
            r.castFilter = castFilter;
            r.castName = castName;
            r.gridIndex = library.grid.currentIndex;
            break;
        case "title":
            r.season = season;
            break;
        case "person":
            r.gridIndex = personScreen.filmographyIndex;
            break;
        }
    }

    // Coming back to a screen re-establishes it from its entry. Every request it
    // makes on the way is answered from the per-open memo, so a walk back down
    // four screens spawns no processes and shows no empty page.
    function restoreTop() {
        const r = navStack.length > 0 ? navStack[navStack.length - 1] : null;
        if (!r)
            return;
        switch (r.view) {
        case "library":
            mode = r.mode || "all";
            kind = r.kind || "all";
            sortKey = r.sortKey || "popular";
            genre = r.genre || "";
            year = r.year || "";
            minRating = r.minRating || "";
            language = r.language || "";
            castFilter = r.castFilter || "";
            castName = r.castName || "";
            library.query = r.query || "";
            library.grid.currentIndex = r.gridIndex === undefined ? 0 : r.gridIndex;
            break;
        case "title":
            loadTitle(r.id, r.kind, r.season || 0);
            break;
        case "person":
            loadPerson(r.id);
            personScreen.filmographyIndex = r.gridIndex || 0;
            break;
        }
    }

    // ------------------------------------------------------------ the memo
    // ONE PANEL-OPEN'S ANSWERS, KEPT. Every `dekho api` call is a process, and
    // walking back out of person → title → person would otherwise re-run every
    // one of them. Identical argv within one open answers from here instead,
    // synchronously, so Escape is instant and free.
    //
    // Opt-in per call site, because staleness is per verb: `title`, `episodes`,
    // `person`, `discover`, `genres`, `languages` and every `prefetch` describe
    // things that do not change while a panel is open, while `history` must NOT
    // be memoised — it is re-fetched precisely because a film just moved it.
    readonly property var memo: QtObject {
        readonly property int limit: 24
        property var store: ({})
        property var order: []

        function key(args) {
            return args.join("\u0000");
        }

        function lookup(args) {
            const v = store[key(args)];
            return v === undefined ? null : v;
        }

        function remember(args, data) {
            const k = key(args);
            if (store[k] === undefined) {
                order.push(k);
                while (order.length > limit)
                    delete store[order.shift()];
            }
            store[k] = data;
        }

        function clear() {
            store = ({});
            order = [];
        }
    }

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"
    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dekho"
    // Where bin/dekho-play parks THIS run's NDJSON. A NEW PATH PER RUN, chosen
    // here rather than by the wrapper: a fixed name races, because the tail below
    // starts the instant execDetached returns while the wrapper still has to stop
    // the previous unit, so `tail -n +1` would replay the LAST run's events into
    // this run's view.
    property string sessionFile: ""

    // ------------------------------------------------------------ open/close
    // show() and hide() only ever MAP and UNMAP the window; everything that has
    // to happen on the way in or out hangs off didOpen()/didClose(), which the
    // window's own visibleChanged drives. That indirection is what makes a
    // compositor close (Mod+Q) stop the tails and arm eviction exactly as Escape
    // does, rather than being a second, silent way to close.
    function show() {
        if (panel.visible) {
            raiseWindow();
            return;
        }
        panel.visible = true;
    }

    function hide() {
        panel.visible = false;
    }

    function didOpen() {
        refresh();
        resumeTail();
        statusProbe.running = true;
        Qt.callLater(focusCurrentScreen);
    }

    // ------------------------------------------------------ adopting a run
    // IS SOMETHING ALREADY PLAYING? The surface is EVICTABLE, so everything this
    // module believes about a film is destroyed 45 s after the panel closes.
    // Playback is not destroyed with it and must not be: it is a transient unit
    // in another slice, still going. systemd has the answer and `dekho-play
    // --status` asks it — one short-lived process per open.
    Process {
        id: statusProbe

        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", dekhoRoot.binDir + "dekho-play", "--status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: dekhoRoot.adoptRun(text)
        }
    }

    function adoptRun(line) {
        let d = null;
        try {
            d = JSON.parse(String(line || "").trim());
        } catch (e) {
            return;
        }
        if (!d || d.active !== true || !d.session) {
            // Nothing is running, so anything this panel still believes about a
            // film is stale by construction: an mpv closed while the panel was
            // away leaves no `exit` line to hear, because hide() stopped the tail
            // that would have heard it. The unit is the truth.
            if (playbackRunning) {
                playbackRunning = false;
                sessionTail.running = false;
            }
            return;
        }
        if (sessionFile === String(d.session) && sessionTail.running)
            return;
        sessionFile = String(d.session);
        session = null;
        playbackRunning = true;
        playbackStopped = false;
        // Cleared so the trail's own `playing` line can name this run — a label
        // left over from a previous one would fail the "not set yet" test in
        // appendSessionLine and the bar would name the wrong film.
        playbackLabel = "";
        sessionTail.running = false;
        Qt.callLater(() => sessionTail.running = true);
    }

    // The way back to a playback screen that Escape popped. Without it the run is
    // reachable only while you happen to be standing on it.
    function reopenPlayback() {
        if (view === "playback")
            return;
        push({
            view: "playback",
            trailer: false
        });
        if (!sessionTail.running)
            resumeTail();
    }

    function didClose() {
        // WHERE YOU WERE SURVIVES A TOGGLE — and survives it exactly as long as
        // the surface does. The old "closing means finished" rule is not lost, it
        // is delegated to the loader: the surface is `evictable` with a 45 s grace
        // window (shell.qml), so a panel closed and forgotten is DESTROYED, stack,
        // memo and decoded posters together.
        //
        // Playback is untouched by this — it is not ours to stop. Tailing an
        // NDJSON file nobody is looking at is the one background cost this module
        // could accidentally leave running, and there are two of them.
        sessionTail.running = false;
        trailerTail.running = false;
    }

    function resumeTail() {
        if (view !== "playback")
            return;
        if (route.trailer === true) {
            if (!trailerFile)
                return;
            trailerSession = null;
            trailerTail.running = false;
            Qt.callLater(() => trailerTail.running = true);
            return;
        }
        if (!sessionFile)
            return;
        session = null;
        sessionTail.running = false;
        Qt.callLater(() => sessionTail.running = true);
    }

    // TOGGLE MEANS THREE THINGS. A toplevel has a state a layer surface never
    // could: mapped, but behind the mpv it started, or scrolled off, or on a
    // workspace you left. Hiding in that state is the wrong answer to
    // Mod+Ctrl+Alt+M — you pressed it to LOOK at the thing.
    //
    //   not open                          → open it
    //   open but not focused / elsewhere  → focus it, bringing its workspace
    //   open and focused                  → hide it
    function toggle() {
        if (!panel.visible) {
            panel.visible = true;
            return;
        }
        if (!focused) {
            raiseWindow();
            return;
        }
        hide();
    }

    // The window's own name, and the only handle that identifies it to the
    // compositor. Every Quickshell toplevel in this session is app-id
    // `org.quickshell` — Qt sets app_id per PROCESS, not per window — so app-id
    // says "the shell" and only the title says "the hub". niri's window rule
    // matches on the pair, and the two spellings have to stay in step: change
    // this and change home/dot_config/niri/config.kdl's dekho rule with it.
    readonly property string windowTitle: "Movies & TV"

    // Bring the window forward without remapping it. Qt's requestActivate() is
    // not an option: activating a Wayland toplevel needs an xdg-activation token
    // minted from a recent input event, and the input that triggers this went to
    // niri's keybind or to the menu's layer surface, never to this window.
    function raiseWindow() {
        if (raiser.running)
            return;
        raiser.running = true;
    }

    Process {
        id: raiser

        running: false
        command: ["bash", "-c", "id=$(niri msg --json windows | jq -r --arg t \"$1\" '[.[] | select(.app_id == \"org.quickshell\" and .title == $t)] | sort_by(.id) | last | .id // empty')\n[ -n \"$id\" ] && exec niri msg action focus-window --id \"$id\"", "qshell-dekho-raise", dekhoRoot.windowTitle]
    }

    // `qs ipc call dekho search "the wire"` — open straight onto a query.
    function searchFor(text) {
        show();
        goHome();
        library.query = String(text || "");
    }

    // ------------------------------------------------------------- art paths
    // THREE CACHES, ONE PER TMDB SIZE, each a directory plus the set of files
    // known to be in it. Not one "ready" flag per listing, which is what this
    // module used to keep and what doc §12 and §13 both caught out: every w342
    // poster in the session lands in the SAME directory, so a path built from a
    // batch flag is a path built from another screen's answer. Worse, Qt's Image
    // caches a miss and will not retry, so a poster that was asked for one frame
    // early stayed blank until you navigated away and back.
    //
    // Per FILE it is right by construction, and it is what makes LOAD MORE free:
    // appending a page runs a second prefetch that cannot blank the page above it.
    // The maps are REASSIGNED rather than mutated-and-ticked — a fresh object is
    // what notifies, and a few hundred short keys is nothing to copy.
    property string w342Dir: ""
    property var w342Done: ({})
    property string w185Dir: ""
    property var w185Done: ({})
    property string w780Dir: ""
    property var w780Done: ({})

    // `args` is ["prefetch", "--size", "<size>", path…]; everything after the
    // size is now on disk.
    function recorded(map, args) {
        const next = {};
        for (const k in map)
            next[k] = map[k];
        for (let i = 3; i < args.length; i++)
            next[args[i]] = true;
        return next;
    }

    function artPath(dir, done, path) {
        if (!path || !dir)
            return "";
        return done[path] === true ? dir + "/" + String(path).replace(/^\/+/, "") : "";
    }

    // ----------------------------------------------------------------- library
    // "all" | "continue" | "trending", and "all" | "movie" | "tv".
    property string mode: "all"
    property string kind: "all"

    property string sortKey: "popular"
    // omakade cycles its sort through three values and so does this. The other
    // two `dekho api discover` offers (oldest, box office) are not on the chip
    // because a cycling control with five stops is a control you have to press
    // four times to undo.
    readonly property var sortKeys: ["popular", "top-rated", "newest"]

    property string genre: ""
    property string year: ""
    property string minRating: ""
    property string language: ""
    // A person scope rather than a facet: it arrives from a person page (the
    // `--cast` flag `dekho api discover` grew for exactly this), so it has no
    // chip of its own — it leads the caption and CLEAR is how you leave it.
    property string castFilter: ""
    property string castName: ""

    property var genreCache: ({})
    property var genreList: []
    property var languageList: []
    property bool facetsAsked: false

    property var historyItems: []
    property var trendingItems: []
    property var movieItems: []
    property var tvItems: []
    property var searchItems: []
    property int moviePage: 1
    property int movieTotalPages: 1
    property int tvPage: 1
    property int tvTotalPages: 1

    property bool historyLoading: false
    property bool listLoading: false
    property string errorText: ""

    readonly property bool searching: library.query.trim() !== ""

    // A kind chip filters the two lists this module does not fetch per kind.
    // `history` and `trending --kind all` both answer with a mixed list, so the
    // filter is arithmetic here rather than a second request.
    function ofKind(items) {
        if (kind === "all")
            return items;
        return items.filter(e => String(e.kind) === kind);
    }

    readonly property var libraryItems: {
        if (searching)
            return searchItems;
        if (mode === "continue")
            return ofKind(historyItems);
        if (mode === "trending")
            return ofKind(trendingItems);
        if (kind === "movie")
            return movieItems;
        if (kind === "tv")
            return tvItems;
        return Model.interleave(movieItems, tvItems);
    }

    // A `discover` page is twenty rows and TMDB has five hundred of them. The
    // bottom of the grid is therefore not the bottom of the catalog, and the
    // footer button says so — an infinite scroll would have been the same thing
    // with a way to run away.
    readonly property bool canLoadMore: {
        if (mode !== "all" || searching)
            return false;
        if (kind !== "tv" && moviePage < movieTotalPages)
            return true;
        return kind !== "movie" && tvPage < tvTotalPages;
    }

    function refresh() {
        errorText = "";
        historyLoading = true;
        // NOT memoised, and 24 rather than the rails' 12: the grid is a grid now
        // and a dozen rows fill a third of one.
        historyReq.fetch(["history", "--limit", "24"]);
        trendingReq.fetch(["trending", "--kind", "all", "--window", "week"]);
        reloadDiscover();
    }

    function reloadDiscover() {
        moviePage = 1;
        tvPage = 1;
        movieItems = [];
        tvItems = [];
        listLoading = true;
        if (kind !== "tv")
            movieReq.fetch(Model.discoverArgs(discoverFilter("movie", 1)));
        if (kind !== "movie")
            tvReq.fetch(Model.discoverArgs(discoverFilter("tv", 1)));
    }

    function discoverFilter(forKind, page) {
        return {
            kind: forKind,
            sort: sortKey,
            // A genre id means one thing for films and something else, or
            // nothing, for series (doc §9) — which is why the chip is disabled
            // while the kind is ALL and why the id is only ever sent with the
            // kind it was chosen under.
            genre: kind === forKind ? genre : "",
            lang: language,
            minRating: minRating,
            year: year,
            cast: castFilter,
            page: page
        };
    }

    function loadMore() {
        if (!canLoadMore)
            return;
        listLoading = true;
        if (kind !== "tv" && moviePage < movieTotalPages) {
            moviePage = moviePage + 1;
            movieReq.fetch(Model.discoverArgs(discoverFilter("movie", moviePage)));
        }
        if (kind !== "movie" && tvPage < tvTotalPages) {
            tvPage = tvPage + 1;
            tvReq.fetch(Model.discoverArgs(discoverFilter("tv", tvPage)));
        }
    }

    function setMode(next) {
        if (mode === next)
            return;
        mode = next;
        library.focusGrid();
    }

    function setKind(next) {
        if (kind === next)
            return;
        kind = next;
        // Genre ids do not survive a kind change, for the reason above.
        genre = "";
        if (next !== "all")
            ensureFacets();
        if (mode === "all")
            reloadDiscover();
        library.focusGrid();
    }

    function cycleSort() {
        const i = sortKeys.indexOf(sortKey);
        sortKey = sortKeys[(i + 1) % sortKeys.length];
        reloadDiscover();
    }

    // omakade's own `nextFilter`: step through the values and then back to
    // unset, so one control both chooses and clears.
    function nextValue(current, values) {
        if (!values || values.length === 0)
            return "";
        const index = values.indexOf(current);
        return index < 0 ? values[0] : index + 1 < values.length ? values[index + 1] : "";
    }

    function cycleFacet(facet) {
        ensureFacets();
        switch (facet) {
        case "genre":
            genre = nextValue(genre, genreList.map(g => String(g.id)));
            break;
        case "year":
            year = nextValue(year, Model.YEAR_CHOICES.map(c => c.key).filter(k => k !== ""));
            break;
        case "rating":
            minRating = nextValue(minRating, Model.RATING_CHOICES.map(c => c.key).filter(k => k !== ""));
            break;
        case "language":
            language = nextValue(language, languageList.map(l => String(l.code)));
            break;
        default:
            return;
        }
        reloadDiscover();
    }

    function clearFilters() {
        genre = "";
        year = "";
        minRating = "";
        language = "";
        castFilter = "";
        castName = "";
        reloadDiscover();
        toast.show("Filters cleared");
    }

    // Genres and languages are fetched the first time a facet is touched and not
    // before: an open must not grow two more processes for controls most opens
    // never use (doc §11's rule for the Browse screen this replaces).
    function ensureFacets() {
        if (kind !== "all") {
            const cached = genreCache[kind];
            if (cached !== undefined) {
                genreList = cached;
                genre = Model.genreValue(cached, genre);
            } else {
                genreList = [];
                genresReq.fetch(["genres", "--kind", kind]);
            }
        }
        if (!facetsAsked) {
            facetsAsked = true;
            languagesReq.fetch(["languages"]);
        }
    }

    // A genre button on a title page filters the library by it. The kind comes
    // from the title the button was on, because "Action" is a different genre for
    // films and series — which is also what makes the id legal to send.
    function filterByGenre(name) {
        goHome();
        mode = "all";
        kind = detail && detail.kind === "tv" ? "tv" : "movie";
        library.query = "";
        castFilter = "";
        castName = "";
        genre = name;
        ensureFacets();
        reloadDiscover();
        toast.show(name);
    }

    // The other half of a cast click. The person page answers "what else have
    // they done"; this answers "which of those, sorted and filtered".
    function filterByPerson() {
        if (!person || person.id === undefined)
            return;
        goHome();
        mode = "all";
        library.query = "";
        castFilter = String(person.id);
        castName = String(person.name || "");
        reloadDiscover();
        toast.show(castName);
    }

    // --------------------------------------------------------------- search
    // Typing is not a query yet. 250 ms is the shell's other debounce and is
    // comfortably under the point where a search field feels laggy.
    Timer {
        id: searchDebounce

        interval: 250
        repeat: false
        onTriggered: dekhoRoot.runSearch()
    }

    function runSearch() {
        const q = library.query.trim();
        if (!q) {
            searchItems = [];
            return;
        }
        listLoading = true;
        errorText = "";
        searchReq.fetch(["search", q]);
    }

    function queryEdited(text) {
        if (String(text || "").trim())
            searchDebounce.restart();
        else {
            searchDebounce.stop();
            searchItems = [];
        }
    }

    // ------------------------------------------------------------- requests
    ApiRequest {
        id: historyReq

        onLoaded: data => {
            const items = (data.items || []).map(function (e) {
                e.resume = Model.resumeLabel(e);
                e.progress = Model.progressOf(e);
                return e;
            });
            dekhoRoot.historyItems = items;
            dekhoRoot.historyLoading = false;
            historyPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(items, "poster")));
        }
        onFailed: message => {
            dekhoRoot.historyLoading = false;
            // A machine that has never played anything has no history file, and
            // that is not an error worth a red line across the page.
            dekhoRoot.historyItems = [];
        }
    }

    ApiRequest {
        id: trendingReq

        onLoaded: data => {
            dekhoRoot.trendingItems = data.items || [];
            trendingPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.trendingItems, "poster")));
        }
        onFailed: message => dekhoRoot.errorText = message
    }

    ApiRequest {
        id: movieReq

        memo: dekhoRoot.memo
        onLoaded: data => {
            const items = data.items || [];
            // The page number at load time is the page that was asked for.
            dekhoRoot.movieItems = dekhoRoot.moviePage > 1 ? dekhoRoot.movieItems.concat(items) : items;
            dekhoRoot.movieTotalPages = Number(data.total_pages) || 1;
            dekhoRoot.listLoading = false;
            moviePrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(items, "poster")));
        }
        onFailed: message => {
            dekhoRoot.listLoading = false;
            dekhoRoot.errorText = message;
        }
    }

    ApiRequest {
        id: tvReq

        memo: dekhoRoot.memo
        onLoaded: data => {
            const items = data.items || [];
            dekhoRoot.tvItems = dekhoRoot.tvPage > 1 ? dekhoRoot.tvItems.concat(items) : items;
            dekhoRoot.tvTotalPages = Number(data.total_pages) || 1;
            dekhoRoot.listLoading = false;
            tvPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(items, "poster")));
        }
        onFailed: message => {
            dekhoRoot.listLoading = false;
            dekhoRoot.errorText = message;
        }
    }

    ApiRequest {
        id: searchReq

        onLoaded: data => {
            dekhoRoot.searchItems = data.items || [];
            dekhoRoot.listLoading = false;
            searchPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.searchItems, "poster")));
        }
        onFailed: message => {
            dekhoRoot.listLoading = false;
            dekhoRoot.errorText = message;
        }
    }

    ApiRequest {
        id: titleReq

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.detail = data;
            dekhoRoot.detailError = "";
            titlePrefetch.fetch(["prefetch", "--size", "w342"].concat(data.poster ? [data.poster] : []));
            backdropPrefetch.fetch(["prefetch", "--size", "w780"].concat(data.backdrop ? [data.backdrop] : []));
            // Faces at w185 and the similar posters at w342: two more batches,
            // fired only because a title page is open. Nothing on the library
            // pays for them, which is the rule this module's request count lives
            // by — a screen fetches what it draws, when it is drawn.
            const faces = Model.posterArgs(data.cast || [], "profile");
            if (faces.length > 0)
                castPrefetch.fetch(["prefetch", "--size", "w185"].concat(faces));
            const similar = Model.posterArgs(data.similar || [], "poster");
            if (similar.length > 0)
                similarPrefetch.fetch(["prefetch", "--size", "w342"].concat(similar));
            if (data.kind === "tv") {
                const seasons = data.seasons || [];
                // Open on the season history is in, not on season 1 — for
                // anything you are already watching that is the only season you
                // want to see. A season carried back by the nav stack wins over
                // both: it is where you actually were.
                const r = dekhoRoot.resumeFor(data.id, data.kind);
                const remembered = dekhoRoot.pendingSeason;
                const wanted = remembered > 0 ? remembered : (r && r.season ? r.season : (seasons.length > 0 ? seasons[0].number : 1));
                dekhoRoot.pendingSeason = 0;
                dekhoRoot.loadSeason(wanted);
            }
        }
        onFailed: message => dekhoRoot.detailError = message
    }

    ApiRequest {
        id: episodesReq

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.episodes = data.items || [];
            dekhoRoot.episodesLoading = false;
            stillsPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.episodes, "still")));
        }
        onFailed: message => {
            dekhoRoot.episodes = [];
            dekhoRoot.episodesLoading = false;
            dekhoRoot.detailError = message;
        }
    }

    ApiRequest {
        id: personReq

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.person = data;
            dekhoRoot.personLoading = false;
            dekhoRoot.personError = "";
            if (data.profile)
                personPhotoPrefetch.fetch(["prefetch", "--size", "w185", data.profile]);
            const posters = Model.posterArgs(data.credits || [], "poster");
            if (posters.length > 0)
                creditsPrefetch.fetch(["prefetch", "--size", "w342"].concat(posters));
        }
        onFailed: message => {
            dekhoRoot.personLoading = false;
            dekhoRoot.personError = message;
        }
    }

    // Genres are KIND-SPECIFIC in TMDB, so each kind's list is fetched once and
    // kept for the visit.
    ApiRequest {
        id: genresReq

        memo: dekhoRoot.memo
        onLoaded: data => {
            const items = data.items || [];
            const forKind = String(lastArgs[2] || "movie");
            dekhoRoot.genreCache[forKind] = items;
            if (forKind !== dekhoRoot.kind)
                return;
            dekhoRoot.genreList = items;
            // A genre arriving from a title page is the NAME TMDB printed;
            // the chip speaks ids. Normalising here is what makes it show as the
            // chosen value rather than as a filter the list does not recognise.
            dekhoRoot.genre = Model.genreValue(items, dekhoRoot.genre);
        }
        // No onFailed: a facet list that did not come back leaves that chip with
        // nothing to cycle through, which is exactly what it can offer.
    }

    ApiRequest {
        id: languagesReq

        memo: dekhoRoot.memo
        onLoaded: data => dekhoRoot.languageList = data.items || []
    }

    // THE PREFETCHES, ONE PER CALL SITE — nine into w342, two into w185 and one
    // into w780. They all write the same three properties, so a single shared
    // instance per size is the obvious shape and is WRONG: ApiRequest queues at
    // most ONE argv while a call is in flight (see its header, where that is the
    // right answer for a debounced search field), so an open's four listings
    // firing at one shared prefetch would have silently dropped two of them and
    // left half the grid on its placeholder. Separate instances also run in
    // parallel, which is what a hub open wants.
    //
    // Each answers with the directory it wrote into and records ITS FILES into
    // that size's set — see the art paths above for why that is a set and not a
    // flag. None of them has an onFailed: art that did not arrive leaves the
    // card on its gradient placeholder, which is what PosterCard draws for a
    // title TMDB has no poster for anyway.
    ApiRequest {
        id: historyPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: trendingPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: moviePrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: tvPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: searchPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: titlePrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: similarPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: stillsPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: creditsPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w342Dir = String(data.dir || "");
            dekhoRoot.w342Done = dekhoRoot.recorded(dekhoRoot.w342Done, lastArgs);
        }
    }

    ApiRequest {
        id: castPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w185Dir = String(data.dir || "");
            dekhoRoot.w185Done = dekhoRoot.recorded(dekhoRoot.w185Done, lastArgs);
        }
    }

    ApiRequest {
        id: personPhotoPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w185Dir = String(data.dir || "");
            dekhoRoot.w185Done = dekhoRoot.recorded(dekhoRoot.w185Done, lastArgs);
        }
    }

    ApiRequest {
        id: backdropPrefetch

        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.w780Dir = String(data.dir || "");
            dekhoRoot.w780Done = dekhoRoot.recorded(dekhoRoot.w780Done, lastArgs);
        }
    }

    // ---------------------------------------------------------------- title
    property var detail: null
    property var episodes: []
    property int season: 1
    property bool episodesLoading: false
    property string detailError: ""
    // The season a restored nav entry wants, held across the title request
    // because the answer is what says whether the title even has seasons.
    property int pendingSeason: 0

    function resumeFor(id, forKind) {
        for (let i = 0; i < historyItems.length; i++) {
            const e = historyItems[i];
            if (e.id === id && e.kind === forKind)
                return e;
        }
        return null;
    }

    function openTitle(item) {
        if (!item || item.id === undefined)
            return;
        push({
            view: "title",
            id: item.id,
            kind: item.kind || "movie"
        });
        loadTitle(item.id, item.kind || "movie", 0);
    }

    function loadTitle(id, forKind, wantSeason) {
        detail = null;
        episodes = [];
        detailError = "";
        pendingSeason = wantSeason || 0;
        titleReq.fetch(["title", "--id", String(id), "--kind", String(forKind)]);
    }

    function loadSeason(number) {
        if (!detail)
            return;
        season = number;
        episodes = [];
        episodesLoading = true;
        episodesReq.fetch(["episodes", "--id", String(detail.id), "--season", String(number)]);
    }

    // ---------------------------------------------------------------- person
    property var person: null
    property bool personLoading: false
    property string personError: ""

    // A cast row, a crew button and a `person` payload all carry an id and a
    // name, so one entry point takes any of them.
    function openPerson(p) {
        if (!p || p.id === undefined)
            return;
        push({
            view: "person",
            id: p.id
        });
        loadPerson(p.id);
    }

    function loadPerson(id) {
        person = null;
        personError = "";
        personLoading = true;
        personReq.fetch(["person", "--id", String(id)]);
    }

    // -------------------------------------------------------------- playback
    property var session: null
    property bool playbackRunning: false
    property string playbackLabel: ""
    property string playbackPoster: ""
    property string playbackBackdrop: ""

    // A trailer is a second, independent run: its own transient unit
    // (dekho-trailer, see bin/dekho-play), its own NDJSON file, its own tail and
    // its own session state. All of that is one requirement — pressing Trailer
    // must not stop the film you are forty minutes into.
    property string trailerFile: ""
    property var trailerSession: null
    property bool trailerRunning: false
    property string trailerLabel: ""

    // ------------------------------------------------------ release choice
    // The release menu, as the CLI has it: play asks `dekho api releases`, shows
    // the list, and only then starts dekho-play — with `--release` when a row was
    // chosen, without it when the Auto row was. Resume skips the menu entirely:
    // the whole point of resuming is picking up the release whose pieces are
    // already on disk.
    property var releaseItems: []
    property bool releasesLoading: false
    property string releasesError: ""
    property int releasesDropped: 0
    property int releaseSeason: 0
    property int releaseEpisode: 0

    function openReleases(seasonNumber, episodeNumber) {
        if (!detail)
            return;
        releaseSeason = seasonNumber;
        releaseEpisode = episodeNumber;
        releaseItems = [];
        releasesError = "";
        releasesDropped = 0;
        releasesLoading = true;
        releaseSheet.open = true;
        const args = ["releases", "--id", String(detail.id), "--kind", String(detail.kind)];
        if (detail.kind === "tv" && seasonNumber > 0) {
            args.push("-s", String(seasonNumber));
            args.push("-e", String(episodeNumber));
        }
        releasesFetch.fetch(args);
    }

    ApiRequest {
        id: releasesFetch

        // No memo: seeder counts go stale in minutes, and a stale hash sent back
        // with --release is an error the panel would have caused itself.
        onLoaded: data => {
            dekhoRoot.releaseItems = data.items || [];
            dekhoRoot.releasesDropped = Number(data.dropped) || 0;
            dekhoRoot.releasesLoading = false;
        }
        onFailed: message => {
            dekhoRoot.releasesError = message;
            dekhoRoot.releasesLoading = false;
        }
    }

    function play(seasonNumber, episodeNumber, fromResume, releaseHash) {
        if (!detail)
            return;
        sessionFile = runtimeDir + "/session-" + Date.now() + ".ndjson";
        const args = [dekhoRoot.binDir + "dekho-play", "--session", sessionFile, "--id", String(detail.id), "--kind", String(detail.kind)];
        if (detail.kind === "tv" && seasonNumber > 0) {
            args.push("--season", String(seasonNumber));
            args.push("--episode", String(episodeNumber));
        }
        if (fromResume)
            args.push("--resume");
        if (releaseHash)
            args.push("--release", String(releaseHash));

        session = {
            events: [],
            headline: "Starting dekho…",
            kind: "status",
            ratio: 0,
            rate: 0,
            buffered: 0,
            peers: 0,
            playing: false,
            error: ""
        };
        playbackRunning = true;
        playbackStopped = false;
        playbackLabel = detail.title + (detail.year ? " (" + detail.year + ")" : "") + (detail.kind === "tv" && seasonNumber > 0 ? " — " + Model.episodeCode(seasonNumber, episodeNumber) : "");
        playbackPoster = artPath(w342Dir, w342Done, detail.poster);
        playbackBackdrop = artPath(w780Dir, w780Done, detail.backdrop);
        push({
            view: "playback",
            trailer: false
        });

        Quickshell.execDetached(args);
        // `tail -F` rather than a FileView watcher: the file does not exist yet
        // at this instant (bin/dekho-play creates it), -F waits for it to appear,
        // and re-reading a growing file on every inotify tick would re-parse
        // every line each time.
        //
        // The restart is split across two turns of the event loop. `running` set
        // false and true again in one turn is a single net change, so the second
        // film of a session would keep the FIRST film's tail.
        sessionTail.running = false;
        Qt.callLater(() => sessionTail.running = true);
    }

    function playTrailer() {
        if (!detail)
            return;
        trailerFile = runtimeDir + "/trailer-" + Date.now() + ".ndjson";
        trailerSession = {
            events: [],
            headline: "Fetching the trailer…",
            kind: "status",
            ratio: 0,
            rate: 0,
            buffered: 0,
            peers: 0,
            playing: false,
            error: ""
        };
        trailerRunning = true;
        trailerStopped = false;
        trailerLabel = detail.title + (detail.year ? " (" + detail.year + ")" : "") + " — trailer";
        playbackPoster = artPath(w342Dir, w342Done, detail.poster);
        playbackBackdrop = artPath(w780Dir, w780Done, detail.backdrop);
        push({
            view: "playback",
            trailer: true
        });

        Quickshell.execDetached([dekhoRoot.binDir + "dekho-play", "--trailer", "--session", trailerFile, "--id", String(detail.id), "--kind", String(detail.kind)]);
        trailerTail.running = false;
        Qt.callLater(() => trailerTail.running = true);
    }

    // STOPPING HAS TO SHOW. Both of these end the run by stopping the unit and
    // dropping the tail, which means the last line the screen ever saw is the
    // green "Playing …" one — so before these flags existed the whole screen
    // stayed exactly as it was and only the button vanished, which reads as a
    // click that did nothing (user, 2026-08-20).
    property bool playbackStopped: false
    property bool trailerStopped: false

    function stopPlayback() {
        // A tracked Process rather than execDetached, ONLY so that its exit is
        // observable: stopping a film moves it into Continue watching, and the
        // list has to agree. The `exit` NDJSON line that normally triggers that
        // re-fetch never arrives here. bin/dekho-play's --stop waits for the
        // unit's cgroup to drain before returning, which is what makes this
        // ordering true rather than a race: dekho writes the history on its way
        // out.
        //
        // Split across two turns of the event loop: false and true again in ONE
        // turn is a single net change to `running`, so a second Stop pressed
        // while the first was still draining the cgroup would silently do
        // nothing. Same trap the tails document.
        stopper.running = false;
        Qt.callLater(() => stopper.running = true);
        playbackRunning = false;
        playbackStopped = true;
        sessionTail.running = false;
    }

    Process {
        id: stopper

        running: false
        command: [dekhoRoot.binDir + "dekho-play", "--stop"]
        // NOT memoised and NOT conditional: what was watched has moved on.
        onExited: historyReq.fetch(["history", "--limit", "24"])
    }

    function stopTrailer() {
        // --trailer --stop: the OTHER unit. Without the flag this would stop the
        // film, which is the exact failure the two unit names exist to prevent.
        Quickshell.execDetached([dekhoRoot.binDir + "dekho-play", "--trailer", "--stop"]);
        trailerRunning = false;
        trailerStopped = true;
        trailerTail.running = false;
    }

    function parseSessionLine(line) {
        const text = String(line || "").trim();
        if (!text || text.charAt(0) !== "{")
            return null;
        let raw;
        try {
            raw = JSON.parse(text);
        } catch (e) {
            return null;
        }
        return Model.describeEvent(raw);
    }

    function foldEvent(prev, d) {
        const next = {
            events: prev ? prev.events.slice() : [],
            headline: prev ? prev.headline : "",
            kind: prev ? prev.kind : "status",
            ratio: 0,
            rate: 0,
            buffered: 0,
            peers: prev ? prev.peers : 0,
            playing: prev ? prev.playing : false,
            error: prev ? prev.error : ""
        };
        if (d.kind === "exit") {
            // A clean exit after mpv took over is just the film ending; anything
            // else has already put its reason in `error`.
            if (!next.playing && !next.error && d.code !== 0)
                next.error = "dekho exited with status " + d.code;
            return next;
        }
        next.events.push(d);
        next.headline = d.text;
        next.kind = d.kind;
        if (d.kind === "buffer") {
            next.ratio = d.ratio;
            next.peers = d.peers;
            next.rate = d.rate;
            next.buffered = d.buffered;
        }
        if (d.kind === "playing")
            next.playing = true;
        if (d.kind === "error")
            next.error = d.text;
        return next;
    }

    function appendSessionLine(line) {
        const d = parseSessionLine(line);
        if (!d)
            return;
        session = foldEvent(session, d);
        // A run adopted after eviction has no label — play() is where that is
        // normally set, and this panel never ran it. The trail carries the title
        // on its `playing` line, which is the only place it survives.
        if (d.kind === "playing" && d.title && !playbackLabel)
            playbackLabel = d.title;
        if (d.kind !== "exit")
            return;
        playbackRunning = false;
        sessionTail.running = false;
        // What was watched has moved on — Continue watching must agree.
        historyReq.fetch(["history", "--limit", "24"]);
    }

    function appendTrailerLine(line) {
        const d = parseSessionLine(line);
        if (!d)
            return;
        trailerSession = foldEvent(trailerSession, d);
        if (d.kind !== "exit")
            return;
        trailerRunning = false;
        trailerTail.running = false;
        // No history refresh: watching a trailer is not watching the film, and
        // dekho does not record it as one.
    }

    Process {
        id: sessionTail

        running: false
        // -n +1 reads from the start, so the whole trail is rebuilt even though
        // the tail is started before the file exists. -F waits for it to appear.
        command: ["setpriv", "--pdeathsig", "TERM", "--", "tail", "-n", "+1", "-F", dekhoRoot.sessionFile]
        stdout: SplitParser {
            onRead: line => dekhoRoot.appendSessionLine(line)
        }
    }

    Process {
        id: trailerTail

        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "tail", "-n", "+1", "-F", dekhoRoot.trailerFile]
        stdout: SplitParser {
            onRead: line => dekhoRoot.appendTrailerLine(line)
        }
    }

    // ----------------------------------------------------------------- keys
    // ESCAPE IS A CASCADE, omakade's exactly: close the sheet, then close the
    // screen you are on, then clear the query, then put the keyboard back on the
    // grid — and only when there is nothing left to undo does it close the panel,
    // which is what Escape from the hub has always meant here.
    function goBack() {
        if (releaseSheet.open) {
            releaseSheet.open = false;
            return;
        }
        if (navStack.length > 1) {
            pop();
            return;
        }
        if (library.query !== "") {
            library.query = "";
            library.focusGrid();
            return;
        }
        if (!library.gridFocused) {
            library.focusGrid();
            return;
        }
        hide();
    }

    // Where the keyboard goes when a screen arrives. omakade focuses its grid on
    // the library and its Play button on a details page; the same rule, plus the
    // one screen it does not have.
    function focusCurrentScreen() {
        switch (view) {
        case "title":
            titleScreen.focusPrimary();
            break;
        case "person":
            personScreen.focusGrid();
            break;
        case "playback":
            playbackScreen.focusPrimary();
            break;
        default:
            library.focusGrid();
            break;
        }
    }

    onViewChanged: Qt.callLater(focusCurrentScreen)

    // ---------------------------------------------------------------- layout
    // A REAL NIRI WINDOW, not a layer-shell overlay (doc §12). As an ordinary
    // toplevel the floating mpv is drawn above this window for free, niri manages
    // it like anything else, and the layer-shell keyboard-grab bug class goes
    // with it: a toplevel gets ordinary focus from the compositor.
    //
    // NOT FULLSCREEN, and that single word is the whole change. niri draws a
    // fullscreen window ABOVE the floating layer — measured 2026-08-20, a
    // fullscreen Quickshell window covered a floating mpv AND the bar, which is
    // precisely the situation being escaped. The window rule in
    // home/dot_config/niri/config.kdl opens it `open-maximized` instead.
    FloatingWindow {
        id: panel

        title: dekhoRoot.windowTitle
        color: dekhoRoot.theme.surface0
        // ASSIGNED, NEVER BOUND. show()/hide() write this and `opened` reads it
        // back; a binding the other way would be destroyed the first time niri's
        // close-window wrote to it — see `opened`.
        visible: false
        implicitWidth: panel.screen ? panel.screen.width : 1600
        implicitHeight: panel.screen ? panel.screen.height : 1000
        // A floor, not a size. Every dimension inside is a proportion of the
        // window, and niri honours a toplevel's minimum: measured 2026-08-20,
        // `set-window-width 300` gave 640.
        minimumSize: Qt.size(640, 400)

        onVisibleChanged: {
            if (panel.visible)
                dekhoRoot.didOpen();
            else
                dekhoRoot.didClose();
        }

        // GLOBAL KEYS ARE Shortcuts, which is what omakade uses and what a window
        // full of real focusable controls needs. A `Keys.onPressed` on an
        // ancestor only sees what the focused item did not accept, so Ctrl+F
        // inside the search field and Escape inside it would both have been
        // swallowed. Qt consults the shortcut map before delivering the key,
        // which is exactly the precedence these want — verified 2026-09-01 on a
        // bare Quickshell FloatingWindow before any of this was written.
        Shortcut {
            sequence: "Escape"
            onActivated: dekhoRoot.goBack()
        }

        Shortcut {
            sequence: "Ctrl+F"
            enabled: dekhoRoot.view === "library" && !releaseSheet.open
            onActivated: library.searchField.forceActiveFocus()
        }

        FocusScope {
            id: keyRoot

            anchors.fill: parent
            focus: true

            // Disabled rather than hidden while the sheet is up: Qt's focus chain
            // skips disabled items, so Tab cannot walk out of a modal and into
            // the page behind it — which is the containment omakade's
            // `focusWithin` is written to enforce by hand.
            Item {
                id: screens

                anchors.fill: parent
                enabled: !releaseSheet.open

                LibraryScreen {
                    id: library

                    anchors.fill: parent
                    visible: dekhoRoot.view === "library"
                    style: dekhoRoot.style

                    mode: dekhoRoot.mode
                    kind: dekhoRoot.kind
                    items: dekhoRoot.libraryItems
                    posterDir: dekhoRoot.w342Dir
                    posterDone: dekhoRoot.w342Done
                    loading: dekhoRoot.listLoading || dekhoRoot.historyLoading
                    errorText: dekhoRoot.errorText
                    canLoadMore: dekhoRoot.canLoadMore
                    sortKey: dekhoRoot.sortKey
                    genre: dekhoRoot.genre
                    year: dekhoRoot.year
                    minRating: dekhoRoot.minRating
                    language: dekhoRoot.language
                    castName: dekhoRoot.castName
                    genres: dekhoRoot.genreList
                    languages: dekhoRoot.languageList

                    onModePicked: next => dekhoRoot.setMode(next)
                    onKindPicked: next => dekhoRoot.setKind(next)
                    onQueryEdited: text => dekhoRoot.queryEdited(text)
                    onSortCycled: dekhoRoot.cycleSort()
                    onFacetCycled: facet => dekhoRoot.cycleFacet(facet)
                    onFiltersCleared: dekhoRoot.clearFilters()
                    onActivated: index => dekhoRoot.openTitle(dekhoRoot.libraryItems[index])
                    onLoadMoreRequested: dekhoRoot.loadMore()
                }

                TitleScreen {
                    id: titleScreen

                    anchors.fill: parent
                    visible: dekhoRoot.view === "title"
                    style: dekhoRoot.style

                    title: dekhoRoot.detail
                    episodes: dekhoRoot.episodes
                    season: dekhoRoot.season
                    loadingEpisodes: dekhoRoot.episodesLoading
                    resume: dekhoRoot.detail ? dekhoRoot.resumeFor(dekhoRoot.detail.id, dekhoRoot.detail.kind) : null
                    error: dekhoRoot.detailError
                    posterDir: dekhoRoot.w342Dir
                    posterDone: dekhoRoot.w342Done
                    faceDir: dekhoRoot.w185Dir
                    faceDone: dekhoRoot.w185Done
                    backdropDir: dekhoRoot.w780Dir
                    backdropDone: dekhoRoot.w780Done

                    onSeasonPicked: number => dekhoRoot.loadSeason(number)
                    // Resume skips the release menu — the whole point of resuming
                    // is picking up the release whose pieces are already on disk.
                    onPlayed: (s, e, fromResume) => fromResume ? dekhoRoot.play(s, e, true) : dekhoRoot.openReleases(s, e)
                    onTrailerRequested: dekhoRoot.playTrailer()
                    onPersonPicked: p => dekhoRoot.openPerson(p)
                    onGenrePicked: name => dekhoRoot.filterByGenre(name)
                    onTitlePicked: item => dekhoRoot.openTitle(item)
                    onDismissed: dekhoRoot.pop()
                }

                PersonScreen {
                    id: personScreen

                    anchors.fill: parent
                    visible: dekhoRoot.view === "person"
                    style: dekhoRoot.style

                    person: dekhoRoot.person
                    loading: dekhoRoot.personLoading
                    error: dekhoRoot.personError
                    posterDir: dekhoRoot.w342Dir
                    posterDone: dekhoRoot.w342Done
                    faceDir: dekhoRoot.w185Dir
                    faceDone: dekhoRoot.w185Done

                    onTitlePicked: item => dekhoRoot.openTitle(item)
                    onBrowseRequested: dekhoRoot.filterByPerson()
                    onDismissed: dekhoRoot.pop()
                }

                PlaybackScreen {
                    id: playbackScreen

                    anchors.fill: parent
                    visible: dekhoRoot.view === "playback"
                    style: dekhoRoot.style

                    // The trailer and the film are two runs with two sessions;
                    // which one this screen is describing is a property of the
                    // stack entry that opened it, not of the module.
                    session: dekhoRoot.route.trailer === true ? dekhoRoot.trailerSession : dekhoRoot.session
                    label: dekhoRoot.route.trailer === true ? dekhoRoot.trailerLabel : dekhoRoot.playbackLabel
                    posterPath: dekhoRoot.playbackPoster
                    backdropPath: dekhoRoot.playbackBackdrop
                    running: dekhoRoot.route.trailer === true ? dekhoRoot.trailerRunning : dekhoRoot.playbackRunning
                    wasStopped: dekhoRoot.route.trailer === true ? dekhoRoot.trailerStopped : dekhoRoot.playbackStopped
                    isTrailer: dekhoRoot.route.trailer === true

                    onStopped: {
                        if (dekhoRoot.route.trailer === true)
                            dekhoRoot.stopTrailer();
                        else
                            dekhoRoot.stopPlayback();
                    }
                    onDismissed: dekhoRoot.pop()
                }
            }

            // Rides above every screen while a run is live, so wherever you
            // wandered to the run is one click from over. Hidden on the playback
            // screen itself, which already is the run.
            NowPlayingBar {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: dekhoRoot.style.ui(16)
                visible: dekhoRoot.playbackRunning && dekhoRoot.view !== "playback"
                enabled: !releaseSheet.open
                style: dekhoRoot.style
                label: dekhoRoot.playbackLabel
                headline: dekhoRoot.session && dekhoRoot.session.headline ? dekhoRoot.session.headline : "Starting…"
                playing: dekhoRoot.session ? dekhoRoot.session.playing === true : false

                onOpened: dekhoRoot.reopenPlayback()
                onStopped: dekhoRoot.stopPlayback()
            }

            ReleaseSheet {
                id: releaseSheet

                style: dekhoRoot.style
                label: dekhoRoot.detail ? dekhoRoot.detail.title + (dekhoRoot.detail.kind === "tv" && dekhoRoot.releaseSeason > 0 ? " — " + Model.episodeCode(dekhoRoot.releaseSeason, dekhoRoot.releaseEpisode) : "") : ""
                items: dekhoRoot.releaseItems
                loading: dekhoRoot.releasesLoading
                error: dekhoRoot.releasesError
                dropped: dekhoRoot.releasesDropped

                onPicked: hash => {
                    releaseSheet.open = false;
                    dekhoRoot.play(dekhoRoot.releaseSeason, dekhoRoot.releaseEpisode, false, hash);
                }
                onDismissed: releaseSheet.open = false
            }

            Toast {
                id: toast

                style: dekhoRoot.style
            }
        }
    }
}
