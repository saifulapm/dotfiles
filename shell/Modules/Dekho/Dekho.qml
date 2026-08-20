import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../../components"
import "../../components/FilterKeys.js" as FilterKeys
import "DekhoModel.js" as Model

// The movie hub: what you are part-way through, what is trending, what to
// search for, and one keypress to put it in mpv. Every byte of it comes from
// `dekho api` (github.com/saifulapm/dekho) — the shell speaks no HTTP and
// holds no TMDB key, and the same binary answers the same questions from a
// terminal.
//
// Nothing here exists until the surface is summoned, and the loader in
// shell.qml marks it `evictable`: a hub that has been closed for the grace
// period releases its whole tree, which is what keeps sixty decoded posters
// from being a permanent line in the shell's RSS. That is also why every open
// re-fetches rather than caching in memory — the poster files are already on
// disk (dekho's own cache), so a warm reopen paints immediately and the four
// TMDB requests only refresh what is on screen.
//
// PLAYBACK IS NOT OUR CHILD. `dekho play` is started as a transient systemd
// user unit by bin/dekho-play, outside this process's cgroup, because
// qshell.service's KillMode=control-group would otherwise kill a film in
// progress every time the shell restarts (the same trap qshell-relaunch
// documents). The panel follows the run by tailing the NDJSON it writes.
//
// AND IT IS AN ORDINARY WINDOW, not a layer-shell overlay — see the
// FloatingWindow below for what that bought and what it cost.
Scope {
    id: dekhoRoot

    required property var theme

    // OPEN IS THE WINDOW'S OWN VISIBILITY, not a flag kept beside it. niri's
    // close-window (Mod+Q) unmaps a toplevel by WRITING visible=false on it,
    // which would silently break a `visible: opened` binding the other way
    // round and strand `opened` at true for ever — the surface would then
    // never satisfy SurfaceLoader's "closed" test and its whole tree, sixty
    // decoded posters included, would stay resident (shell.qml's residency
    // policy). Reading the window rather than shadowing it makes a compositor
    // close indistinguishable from our own hide(), which is what it should be.
    // Measured 2026-08-20 on a bare FloatingWindow: `niri msg action
    // close-window` leaves the process alive and logs visibleChanged -> false,
    // and a later write to the property the binding came from did nothing.
    readonly property bool opened: panel.visible
    // Whether the window has the keyboard. A layer surface with an exclusive
    // grab was either up and holding everything or not up at all; a toplevel
    // has a third state — mapped, but behind something or on another
    // workspace — and that is the state toggle() has to tell apart.
    readonly property bool focused: panel.visible && keyCatcher.Window.active

    // ------------------------------------------------------------ the stack
    // NAVIGATION IS A STACK, NOT A MODE. `view` used to be a string with three
    // values and Escape meant "go to the hub", which was correct while the hub
    // was the only place anything could be reached from. It stopped being
    // correct the moment a cast member opened a person, a person opened a
    // title, that title's genre opened Browse and Browse opened another title:
    // there is no single "home" to fall back to from four screens in, and
    // Escape has to undo the step you took, not the whole journey.
    //
    // Every entry is a plain object with a `view` and whatever identifies the
    // screen ({view: "detail", id, kind}). The LIVE state of the screen on top
    // — its cursor, its filters, its season — stays in the ordinary properties
    // below, because that is what the views bind to; push() snapshots it into
    // the entry being buried and pop() reads it back. So the stack is the
    // history and the properties are the present, rather than the views
    // reaching into a stack frame.
    //
    // Reassigning the array is what notifies; the per-entry snapshot mutates
    // the object in place, which nothing binds to and is therefore free.
    property var navStack: [
        {
            view: "hub"
        }
    ]
    readonly property var route: navStack.length > 0 ? navStack[navStack.length - 1] : ({
            view: "hub"
        })
    // "hub" | "detail" | "person" | "browse" | "playback". The search results
    // replace the rails inside "hub" rather than being a view of their own —
    // the query line stays in the same place either way, so they are the same
    // screen.
    readonly property string view: String(route.view || "hub")

    function push(entry) {
        captureTop();
        navStack = navStack.concat([entry]);
    }

    function pop() {
        // The hub is the bottom of the stack, and popping it is what closing
        // the panel means — Escape from the hub has always closed, and a stack
        // must not change that.
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
                view: "hub"
            }
        ];
    }

    function back() {
        if (view === "hub" && query) {
            clearQuery();
            return;
        }
        pop();
    }

    function captureTop() {
        const r = navStack.length > 0 ? navStack[navStack.length - 1] : null;
        if (!r)
            return;
        switch (r.view) {
        case "hub":
            r.railIndex = railIndex;
            r.itemIndex = itemIndex;
            r.gridIndex = gridIndex;
            break;
        case "detail":
            r.section = detailView.section;
            r.cursor = detailView.cursor;
            r.season = season;
            break;
        case "person":
            r.gridIndex = personView.gridIndex;
            break;
        case "browse":
            r.kind = browseKind;
            r.sort = browseSort;
            r.genre = browseGenre;
            r.lang = browseLang;
            r.minRating = browseMinRating;
            r.year = browseYear;
            r.cast = browseCast;
            r.castName = browseCastName;
            r.page = browsePage;
            r.gridIndex = browseView.gridIndex;
            r.pane = browseView.pane;
            break;
        }
    }

    // Coming back to a screen re-establishes it from its entry. Every request
    // it makes on the way is answered from the per-open memo (see `memo`), so
    // a walk back down four screens spawns no processes and shows no empty
    // page — which is the whole reason the memo exists.
    function restoreTop() {
        const r = navStack.length > 0 ? navStack[navStack.length - 1] : null;
        if (!r)
            return;
        switch (r.view) {
        case "hub":
            railIndex = r.railIndex || 0;
            itemIndex = r.itemIndex || 0;
            gridIndex = r.gridIndex === undefined ? -1 : r.gridIndex;
            break;
        case "detail":
            loadTitle(r.id, r.kind, r.season || 0);
            // After loadTitle, which resets both: this is where you WERE.
            detailView.section = r.section || "actions";
            detailView.cursor = r.cursor || 0;
            break;
        case "person":
            loadPerson(r.id);
            personView.gridIndex = r.gridIndex || 0;
            break;
        case "browse":
            browseKind = r.kind;
            browseSort = r.sort;
            browseGenre = r.genre;
            browseLang = r.lang;
            browseMinRating = r.minRating;
            browseYear = r.year;
            browseCast = r.cast || "";
            browseCastName = r.castName || "";
            browsePage = r.page;
            browseView.pane = r.pane || "results";
            ensureFacets();
            runDiscover();
            browseView.gridIndex = r.gridIndex || 0;
            break;
        }
    }

    // ------------------------------------------------------------ the memo
    // ONE PANEL-OPEN'S ANSWERS, KEPT. Every `dekho api` call is a process, and
    // walking back out of person → title → person → browse would otherwise
    // re-run every one of them — five for a detail page alone once its cast
    // and similar art are counted. Identical argv within one open answers from
    // here instead, synchronously, so Escape is instant and free.
    //
    // Opt-in per call site, because staleness is per verb: `title`, `episodes`,
    // `person`, `discover`, `genres`, `languages` and every `prefetch` describe
    // things that do not change while a panel is open, while `history` must
    // NOT be memoised — it is re-fetched precisely because a film just moved
    // it. Cleared on hide(), so a reopen is as live as it has always been.
    readonly property var memo: QtObject {
        // Bounded: a title payload with a cast and a similar list is tens of
        // kilobytes, and an unbounded map behind a long browse would be the
        // one place this module could grow without anyone noticing.
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
    // Where bin/dekho-play parks THIS run's NDJSON. Runtime, not state: a
    // session is meaningless after a reboot.
    //
    // A NEW PATH PER RUN, chosen here rather than by the wrapper. A fixed name
    // races: the tail below starts the instant execDetached returns, while the
    // wrapper still has to stop the previous unit before systemd truncates the
    // file — so `tail -n +1` would replay the LAST run's events into this run's
    // view first. An unused name cannot be stale, and `tail -F` is happy to
    // wait for it to appear. The wrapper sweeps the old ones.
    property string sessionFile: ""

    // ------------------------------------------------------------ open/close
    // show() and hide() only ever MAP and UNMAP the window; everything that
    // has to happen on the way in or out hangs off didOpen()/didClose() below,
    // which the window's own visibleChanged drives. That indirection is what
    // makes a compositor close (Mod+Q) stop the tails and arm eviction exactly
    // as Escape does, rather than being a second, silent way to close that
    // leaves both running.
    function show() {
        // Already mapped: bring it forward instead of remapping it. Unmapping
        // and remapping a toplevel is a NEW window as far as niri is
        // concerned — a freshly picked column, the open animation again, and
        // wherever you had put it lost. Raising costs one compositor call and
        // keeps the window where it is.
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
        // NOT goHome(). A summon lands where the last one left off — see
        // didClose(). A freshly instantiated surface has the hub at the bottom
        // of its stack and nothing above it, so a cold open is the hub anyway.
        refresh();
        resumeTail();
    }

    function didClose() {
        // WHERE YOU WERE SURVIVES A TOGGLE — and survives it exactly as long
        // as the surface does. Closing used to mean finished (the emoji and
        // clipboard pickers' rule, and the right one when the panel was three
        // screens deep at most): the query was dropped and the view went back
        // to the hub. Five screens and a back stack later that is the wrong
        // trade — you toggle the panel away to look at the trailer you just
        // started, and coming back to the top of the hub loses the page you
        // were reading.
        //
        // The old rule is not lost, it is delegated to the loader: the surface
        // is `evictable` with a 45 s grace window (shell.qml), so a panel
        // closed and forgotten is DESTROYED, stack, memo and decoded posters
        // together, and the next summon is a cold hub with an empty query.
        // Nothing here needs to enforce "finished" — staying closed already
        // does, and it does it for the pixmaps too. `opened` reads the window,
        // so an unmap from ANY source — Escape, the keybind, Mod+Q — is the
        // close the loader's grace timer starts counting from.
        //
        // Playback is untouched by this — it is not ours to stop. Tailing an
        // NDJSON file nobody is looking at is the one background cost this
        // module could accidentally leave running, and there are two of them
        // now, so both stop.
        sessionTail.running = false;
        trailerTail.running = false;
    }

    // A summon that lands back on a playback view has to start following the
    // run again — hide() stopped the tail. The NDJSON file holds the whole
    // trail and `tail -n +1` replays it, so the session is dropped first and
    // rebuilt from the file rather than folded a second time onto the events
    // it already has.
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

    // TOGGLE MEANS THREE THINGS NOW. As a layer surface it meant two, because
    // an Overlay-layer surface is either up and above everything or not up at
    // all — there was no state where it was open and you could not see it. A
    // toplevel has one: mapped, but behind the mpv it started, or scrolled off
    // to the side, or on a workspace you left. Hiding in that state is the
    // wrong answer to Mod+Ctrl+Alt+M — you pressed it to LOOK at the thing.
    //
    //   not open                          → open it
    //   open but not focused / elsewhere  → focus it, bringing its workspace
    //   open and focused                  → hide it
    //
    // The middle case is the one the window buys and the one that must never
    // be an unmap+remap: that would be a new window to niri, re-running the
    // open animation and re-picking a column every time you glanced at it.
    // Press it twice from another workspace and you get the hub, then nothing
    // — which is the same two presses the layer surface took, plus a stop on
    // the way for the case it could not represent.
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
    // `org.quickshell` — Qt sets app_id per PROCESS from
    // QGuiApplication::desktopFileName(), not per window (measured
    // 2026-08-20) — so app-id says "the shell" and only the title says "the
    // hub". niri's window rule matches on the pair for the same reason, and
    // the two spellings have to stay in step: change this and change
    // home/dot_config/niri/config.kdl's dekho rule with it.
    readonly property string windowTitle: "Movies & TV"

    // Bring the window forward without remapping it. Qt's requestActivate()
    // is not an option here: activating a Wayland toplevel needs an
    // xdg-activation token minted from a recent input event, and the input
    // that triggers this went to niri's keybind or to the menu's layer
    // surface, never to this window — so the compositor is asked directly
    // instead. Same two-step as the mail panel's Emacs raise
    // (Bar/widgets/MailService.qml): find the id, then focus it.
    //
    // One process, only on the raise branch of toggle() — not a poll, and
    // nothing runs while the panel is closed (doc §4).
    function raiseWindow() {
        if (raiser.running)
            return;
        raiser.running = true;
    }

    Process {
        id: raiser
        running: false
        // `last` on an id sort, like MailService's: if two ever match, the
        // newest is the one you just asked for. `// empty` so a missing
        // window is a silent no-op rather than `focus-window --id null`.
        command: ["bash", "-c", "id=$(niri msg --json windows | jq -r --arg t \"$1\" '[.[] | select(.app_id == \"org.quickshell\" and .title == $t)] | sort_by(.id) | last | .id // empty')\n[ -n \"$id\" ] && exec niri msg action focus-window --id \"$id\"", "qshell-dekho-raise", dekhoRoot.windowTitle]
    }

    // `qs ipc call dekho search "the wire"` — open straight onto a query.
    function searchFor(text) {
        show();
        goHome();
        query = String(text || "");
        runSearch();
    }

    // ----------------------------------------------------------------- data
    property var historyItems: []
    property var trendingItems: []
    property var movieItems: []
    property var tvItems: []
    property var searchItems: []
    property string query: ""
    property string errorText: ""

    // The catalog rails' sort, shared by both so one chip row explains both.
    property string sortKey: "popular"
    readonly property var sortChips: [
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
        }
    ]

    property bool historyLoading: false
    property bool trendingLoading: false
    property bool movieLoading: false
    property bool tvLoading: false
    property bool searchLoading: false

    property string historyDir: ""
    property string trendingDir: ""
    property string movieDir: ""
    property string tvDir: ""
    property string searchDir: ""
    property string detailPosterDir: ""
    property string detailBackdropDir: ""
    // The directory the DETAIL PAGE may build its backdrop path against, which
    // is "" until THIS title's own still is on disk.
    //
    // A per-directory guard cannot express that, and this is where doc §6's
    // bug came back wearing a different hat. Every title's w780 backdrop lands
    // in the SAME cache directory, and `detailBackdropDir` was never cleared on
    // navigation — so opening a second title built its path against the first
    // title's still-valid directory before its own prefetch had run. Worse than
    // a one-frame flicker: when the prefetch finally answers it assigns the
    // same directory string, nothing in the binding changes, and Qt's Image has
    // already cached the miss and will not retry (PosterTile's header says the
    // same thing). The hero was blank until you navigated away and back.
    // Seen live 2026-08-20 walking person → title → person → title.
    //
    // Guarding on the FILE fixes it by construction, and `heroDone` is already
    // exactly that map for the hub's own hero.
    readonly property string detailBackdropReadyDir: {
        void heroTick;
        const b = detail && detail.backdrop ? String(detail.backdrop) : "";
        if (!b || !detailBackdropDir)
            return "";
        return heroDone[b] === true ? detailBackdropDir : "";
    }
    // w185 is the third size this module fetches (after w342 posters and w780
    // backdrops), and it lands in its own cache directory like the other two —
    // so it needs its own directory guard for exactly the reason doc §6 gives:
    // a path built against "" resolves to the filesystem root.
    property string castDir: ""
    property string similarDir: ""
    property string personPhotoDir: ""
    property string creditsDir: ""
    property string browseDir: ""

    property bool historyReady: false
    property bool trendingReady: false
    property bool movieReady: false
    property bool tvReady: false
    property bool searchReady: false
    property bool detailReady: false
    property bool castReady: false
    property bool similarReady: false
    property bool personPhotoReady: false
    property bool creditsReady: false
    property bool browseReady: false

    function refresh() {
        errorText = "";
        historyLoading = true;
        historyReq.fetch(["history", "--limit", "12"]);
        trendingLoading = true;
        trendingReq.fetch(["trending", "--kind", "all", "--window", "week"]);
        reloadCatalog();
    }

    function reloadCatalog() {
        movieLoading = true;
        movieReq.fetch(["discover", "--kind", "movie", "--sort", sortKey]);
        tvLoading = true;
        tvReq.fetch(["discover", "--kind", "tv", "--sort", sortKey]);
    }

    function setSort(key) {
        if (sortKey === key)
            return;
        sortKey = key;
        movieReady = false;
        tvReady = false;
        reloadCatalog();
    }

    // The rails on screen, as KEYS rather than as built objects. A computed
    // array of row objects looked tidier and was wrong: it depends on eight
    // properties that land at eight different moments (four listings, four
    // prefetches), so every arrival replaced the whole model and Qt tore down
    // and re-incubated every delegate — twenty posters at a time, visible in
    // the log as "Object or context destroyed during incubation".
    //
    // Keyed, the model changes exactly once per open (when Continue watching
    // appears) and the per-rail lookups below are ordinary bindings: each one
    // reads only the property it needs, so a rail updates when ITS data lands
    // and the others are not touched.
    readonly property var railKeys: historyItems.length > 0 ? ["history", "trending", "movies", "tv"] : ["trending", "movies", "tv"]

    // ----------------------------------------------------- cinematic layout
    // Every dimension is a proportion of the screen with a floor. The desk is
    // 3490x1963 logical, the laptops ~1706x1066, and a layout tuned on one is
    // wrong on the other — the first version's fixed 144 px posters read as
    // stamps on the desk, and a desk-tuned poster would not leave the laptop
    // a second rail.
    readonly property int edgePad: Math.max(theme.space(10), Math.round(panel.width * 0.032))
    readonly property int tileGutter: Math.max(theme.space(4), Math.round(panel.width * 0.008))

    // ------------------------------------------------------ the hero shrinks
    // THE HUB IS ONE PAGE, NOT A HEADER WITH A LIST UNDER IT. The hero used to
    // be a fixed 52% band with the shelves scrolling in the ~48% left over,
    // which meant the biggest thing on screen never moved and the part you
    // were actually reading got half a screen to do it in. Scrolling now
    // collapses the hero to `heroMin` and then holds it there, so the shelves
    // get the room and the art stays as the page's backdrop.
    //
    // `heroFull` is also the LAYOUT budget — poster sizes are measured against
    // it and never against the live height. A tile size that changed while you
    // scrolled would re-lay-out and re-decode sixty cards mid-gesture, which is
    // the one thing this module has spent its whole life avoiding (doc §5).
    readonly property int heroFull: Math.round(panel.height * 0.52)
    // Collapsed: enough for the title and its meta line over a band of the
    // backdrop. The art survives the collapse rather than the hero becoming a
    // text bar, which is what keeps it feeling like the same page.
    readonly property int heroMin: Math.round(panel.height * 0.24)
    readonly property int heroRange: heroFull - heroMin

    // 0 at the top, 1 once the hero is fully collapsed. Driven straight off
    // contentY rather than by an animation of its own, so it tracks a wheel
    // step, a flick and a drag identically — the motion IS the scroll's, which
    // is the only way the two can stay in sync.
    //
    // The rail list's geometry deliberately does NOT depend on this. It is
    // anchored at `heroMin` and carries a spacer header of `heroRange`
    // instead, so a collapsing hero never resizes the Flickable. Resizing it
    // would move contentY's own maximum, which feeds straight back into this
    // expression — a loop that oscillates at the bottom of a short list.
    // Measured from originY, NOT from zero. A ListView with a header starts
    // its content ABOVE the origin — contentY is -headerHeight at the top and
    // only reaches 0 once the whole header has scrolled away — so dividing
    // contentY itself meant the shelves climbed the hero's entire height
    // before the hero began to shrink, and rode up over the title on the way.
    // Measured 2026-08-20: contentY -536 at rest against a 536 px header.
    readonly property real heroCollapse: searching ? 0 : Math.max(0, Math.min(1, (railList.contentY - railList.originY) / Math.max(1, heroRange)))
    readonly property int heroHeight: Math.round(heroFull - heroRange * heroCollapse)

    // The pinned plate the hero is a window onto. Page-sized, so the still is
    // cropped once — to the whole page, which for a 16:9 backdrop on this
    // 1.81 window is very nearly no crop at all — and then never again.
    readonly property int heroPlateHeight: panel.height
    // Offset so the RESTING band shows the plate's vertical centre, which is
    // where a backdrop's subject lives and what the hero framed before this
    // change. Collapsing then uncovers upward from that same framing rather
    // than re-centring on a new one. Constant: it depends on nothing that
    // scrolling moves, which is the entire point of a fixed background.
    readonly property int heroPlateY: Math.round((heroFull - heroPlateHeight) / 2)

    // The title steps down as the band does — full hero type in a quarter of
    // the screen crowded the meta line into the edge. It lands on railTitle,
    // the size the shelf captions beneath it already use, so the collapsed
    // header reads as the page's own heading rather than as a shrunken poster.
    readonly property int heroTitleSize: Math.round(fonts.hero - (fonts.hero - fonts.railTitle) * heroCollapse)
    // How deep the art dissolves into the page at the band's bottom edge.
    readonly property int heroFade: Math.round(heroFull * 0.34)

    // Poster width: whichever of two budgets is tighter. Width-wise a shelf
    // wants ~6 cards and a cut one bleeding off the right edge; height-wise
    // the poster plus its caption and label zone must leave the NEXT rail's
    // caption visible under the hero AT REST, which is what heroFull means
    // here — see above for why this must not follow the collapse.
    readonly property int tileSize: {
        const w = panel.width - 2 * edgePad;
        const perW = Math.floor((w - 6 * tileGutter) / 6.35);
        const room = panel.height - heroFull - fonts.railTitle - fonts.labelZone - theme.space(14);
        const perH = Math.floor(room / 1.5);
        return Math.max(theme.space(34), Math.min(perW, perH));
    }
    // Search results are a lookup, not a browse: smaller cards so a query
    // answers with more than one row of the grid.
    readonly property int searchTile: Math.round(tileSize * 0.8)

    // Module-local type scale. StyledText's roles stop at Display (fontPx 1.5
    // — 18 px at the default token), which is bar-and-panel sized; a cinema
    // needs hero type an order larger, and raising the global font.size or
    // adding roles would restyle the whole desktop. These stay theme-honest
    // by being fontPx() multipliers — a theme that changes font.size scales
    // the hub with everything else — boosted by screen height so the desk
    // gets 73 px hero type and a laptop panel a proportionate 40 px.
    readonly property real typeBoost: panel.height > 0 ? Math.max(1, Math.min(2.1, panel.height / 1000)) : 1
    // `var`, not QtObject, so consumers see the same opaque bag `theme` is —
    // the members below are the whole contract.
    readonly property var fonts: QtObject {
        readonly property int hero: dekhoRoot.theme.fontPx(3.1 * dekhoRoot.typeBoost)
        readonly property int heroMeta: dekhoRoot.theme.fontPx(1.25 * dekhoRoot.typeBoost)
        readonly property int heroBody: dekhoRoot.theme.fontPx(1.02 * dekhoRoot.typeBoost)
        readonly property int railTitle: dekhoRoot.theme.fontPx(1.42 * dekhoRoot.typeBoost)
        readonly property int cardTitle: dekhoRoot.theme.fontPx(0.95 * dekhoRoot.typeBoost)
        readonly property int meta: dekhoRoot.theme.fontPx(0.8 * dekhoRoot.typeBoost)
        readonly property int hint: dekhoRoot.theme.fontPx(0.72 * dekhoRoot.typeBoost)
        // Between heroMeta and heroBody: a tagline is the poster's line, set
        // larger than the synopsis it sits above and smaller than the meta
        // line it must not compete with.
        readonly property int tagline: dekhoRoot.theme.fontPx(1.12 * dekhoRoot.typeBoost)
        // Room reserved under every poster for the focus label, whether or
        // not it is showing, so a focus change never reflows the rail. Sized
        // from PAINTED line heights (~1.45x the pixel size for Maple Mono),
        // not the bare font sizes — the bare sum clipped the subtitle's
        // descenders off the bottom of the strip.
        readonly property int labelZone: Math.round((cardTitle + meta) * 1.45) + dekhoRoot.theme.space(3)
    }

    function railTitle(key) {
        switch (key) {
        case "history":
            return "Continue watching";
        case "trending":
            return "Trending this week";
        case "movies":
            return "Movies · " + sortLabel(sortKey);
        default:
            return "Series · " + sortLabel(sortKey);
        }
    }

    function railItems(key) {
        switch (key) {
        case "history":
            return historyItems;
        case "trending":
            return trendingItems;
        case "movies":
            return movieItems;
        default:
            return tvItems;
        }
    }

    function railReady(key) {
        switch (key) {
        case "history":
            return historyReady;
        case "trending":
            return trendingReady;
        case "movies":
            return movieReady;
        default:
            return tvReady;
        }
    }

    function railDir(key) {
        switch (key) {
        case "history":
            return historyDir;
        case "trending":
            return trendingDir;
        case "movies":
            return movieDir;
        default:
            return tvDir;
        }
    }

    function railLoading(key) {
        switch (key) {
        case "history":
            return historyLoading;
        case "trending":
            return trendingLoading;
        case "movies":
            return movieLoading;
        default:
            return tvLoading;
        }
    }

    function sortLabel(key) {
        for (let i = 0; i < sortChips.length; i++)
            if (sortChips[i].key === key)
                return sortChips[i].label;
        return key;
    }

    readonly property bool searching: query.trim() !== ""

    // ------------------------------------------------------------------ hero
    // The top of the screen is the focused title's backdrop, and it follows
    // the cursor — the single thing that turns a grid of stamps into a place.
    readonly property var focusedItem: {
        if (searching)
            return gridIndex >= 0 && gridIndex < searchItems.length ? searchItems[gridIndex] : null;
        const items = railItems(railKeys[railIndex] || "trending");
        return itemIndex >= 0 && itemIndex < items.length ? items[itemIndex] : null;
    }

    // Backdrops are fetched ONE AT A TIME, on focus, debounced — not as a
    // fifth prefetch batch per rail. Sixty w780 stills is megabytes of TMDB
    // traffic for images mostly never looked at; one per settled focus is a
    // few hundred kilobytes per browse, and dekho's disk cache makes every
    // revisit free. The debounce means holding an arrow key skims the rail
    // without spawning a process per step.
    property var heroDone: ({})
    property int heroTick: 0
    property string heroDir: ""
    readonly property string heroPath: {
        void heroTick;
        const it = focusedItem;
        // Guard on the DIRECTORY, not just readiness — same trap as the
        // detail backdrop (§6 of the doc): a path built against "" resolves
        // to the filesystem root.
        if (!it || !it.backdrop || !heroDir)
            return "";
        return heroDone[it.backdrop] === true ? heroDir + "/" + String(it.backdrop).replace(/^\/+/, "") : "";
    }

    onFocusedItemChanged: {
        if (focusedItem && focusedItem.backdrop && heroDone[focusedItem.backdrop] !== true)
            heroDebounce.restart();
    }

    Timer {
        id: heroDebounce
        // Under the search debounce below: settling on a card should feel
        // like the hero answering, not like a page loading.
        interval: 180
        repeat: false
        onTriggered: {
            const it = dekhoRoot.focusedItem;
            if (it && it.backdrop && dekhoRoot.heroDone[it.backdrop] !== true)
                heroPrefetch.fetch(["prefetch", "--size", "w780", it.backdrop]);
        }
    }

    ApiRequest {
        id: heroPrefetch
        onLoaded: data => {
            dekhoRoot.heroDir = String(data.dir || "");
            // lastArgs is ["prefetch","--size","w780", path…]; everything
            // after the size is a backdrop now on disk.
            for (let i = 3; i < lastArgs.length; i++)
                dekhoRoot.heroDone[lastArgs[i]] = true;
            dekhoRoot.heroTick++;
        }
        // No onFailed: a hero that cannot be fetched simply keeps the last
        // one — the rails and their error line already report the network.
    }

    // ------------------------------------------------------------- requests
    // History carries `progress` and the resume line; the rail renders both
    // straight off the row, so the shaping happens once, here.
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
            dekhoRoot.historyReady = false;
            historyPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(items, "poster")));
        }
        onFailed: message => {
            dekhoRoot.historyLoading = false;
            // A machine that has never played anything has no history file,
            // and that is not an error worth a red line across the hub.
            dekhoRoot.historyItems = [];
        }
    }

    ApiRequest {
        id: trendingReq
        onLoaded: data => {
            dekhoRoot.trendingItems = data.items || [];
            dekhoRoot.trendingLoading = false;
            dekhoRoot.trendingReady = false;
            trendingPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.trendingItems, "poster")));
        }
        onFailed: message => {
            dekhoRoot.trendingLoading = false;
            dekhoRoot.errorText = message;
        }
    }

    ApiRequest {
        id: movieReq
        onLoaded: data => {
            dekhoRoot.movieItems = data.items || [];
            dekhoRoot.movieLoading = false;
            dekhoRoot.movieReady = false;
            moviePrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.movieItems, "poster")));
        }
        onFailed: message => {
            dekhoRoot.movieLoading = false;
            dekhoRoot.errorText = message;
        }
    }

    ApiRequest {
        id: tvReq
        onLoaded: data => {
            dekhoRoot.tvItems = data.items || [];
            dekhoRoot.tvLoading = false;
            dekhoRoot.tvReady = false;
            tvPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.tvItems, "poster")));
        }
        onFailed: message => {
            dekhoRoot.tvLoading = false;
            dekhoRoot.errorText = message;
        }
    }

    ApiRequest {
        id: searchReq
        onLoaded: data => {
            dekhoRoot.searchItems = data.items || [];
            dekhoRoot.searchLoading = false;
            dekhoRoot.searchReady = false;
            dekhoRoot.gridIndex = dekhoRoot.searchItems.length > 0 ? 0 : -1;
            searchPrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.searchItems, "poster")));
        }
        onFailed: message => {
            dekhoRoot.searchLoading = false;
            dekhoRoot.errorText = message;
        }
    }

    ApiRequest {
        id: titleReq
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.detail = data;
            dekhoRoot.detailError = "";
            dekhoRoot.detailReady = false;
            dekhoRoot.castReady = false;
            dekhoRoot.similarReady = false;
            detailPosterPrefetch.fetch(["prefetch", "--size", "w342"].concat(data.poster ? [data.poster] : []));
            detailBackdropPrefetch.fetch(["prefetch", "--size", "w780"].concat(data.backdrop ? [data.backdrop] : []));
            // Faces at w185 and the similar posters at w342: two more batches,
            // fired only because a detail page is open. Nothing on the hub
            // pays for them, which is the rule this module's request count
            // lives by — a screen fetches what it draws, when it is drawn.
            const faces = Model.posterArgs(data.cast || [], "profile");
            if (faces.length > 0)
                castPrefetch.fetch(["prefetch", "--size", "w185"].concat(faces));
            const similar = Model.posterArgs(data.similar || [], "poster");
            if (similar.length > 0)
                similarPrefetch.fetch(["prefetch", "--size", "w342"].concat(similar));
            if (data.kind === "tv") {
                const seasons = data.seasons || [];
                // Open on the season history is in, not on season 1 — for
                // anything you are already watching that is the only season
                // you want to see. A season carried back by the nav stack wins
                // over both: it is where you actually were.
                const r = dekhoRoot.resumeFor(data.id, data.kind);
                const remembered = dekhoRoot.pendingSeason;
                const wanted = remembered > 0 ? remembered : (r && r.season ? r.season : (seasons.length > 0 ? seasons[0].number : 1));
                dekhoRoot.pendingSeason = 0;
                dekhoRoot.loadSeason(wanted);
            }
        }
        onFailed: message => {
            dekhoRoot.detailError = message;
        }
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

    // ------------------------------------------------------------- a person
    ApiRequest {
        id: personReq
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.person = data;
            dekhoRoot.personLoading = false;
            dekhoRoot.personError = "";
            dekhoRoot.personPhotoReady = false;
            dekhoRoot.creditsReady = false;
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

    // -------------------------------------------------------------- browse
    ApiRequest {
        id: browseReq
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.browseItems = data.items || [];
            dekhoRoot.browseTotalPages = Number(data.total_pages) || 1;
            dekhoRoot.browseLoading = false;
            dekhoRoot.browseError = "";
            dekhoRoot.browseReady = false;
            browsePrefetch.fetch(["prefetch", "--size", "w342"].concat(Model.posterArgs(dekhoRoot.browseItems, "poster")));
        }
        onFailed: message => {
            dekhoRoot.browseItems = [];
            dekhoRoot.browseLoading = false;
            dekhoRoot.browseError = message;
        }
    }

    // Genres are KIND-SPECIFIC in TMDB ("Action" for films, "Action &
    // Adventure" for series) — the reason the hub never grew a shared genre
    // chip row (doc §9). Here the kind is part of the filter, so each kind's
    // list is fetched once and kept for the visit.
    ApiRequest {
        id: genresReq
        memo: dekhoRoot.memo
        onLoaded: data => {
            const items = data.items || [];
            const kind = String(lastArgs[2] || "movie");
            dekhoRoot.genreCache[kind] = items;
            if (kind !== dekhoRoot.browseKind)
                return;
            dekhoRoot.browseGenres = items;
            // A genre arriving from a detail page is the NAME TMDB printed on
            // the title; the sidebar speaks ids. Normalising here is what makes
            // the arriving genre show as the chosen row rather than as a
            // filter the list does not recognise.
            dekhoRoot.browseGenre = Model.genreValue(items, dekhoRoot.browseGenre);
        }
        // No onFailed: a facet list that did not come back leaves that facet
        // showing only "Any", which is exactly what it can offer.
    }

    ApiRequest {
        id: languagesReq
        memo: dekhoRoot.memo
        onLoaded: data => dekhoRoot.browseLanguages = data.items || []
    }

    // Prefetch answers with the directory it wrote into, which is what the
    // tiles build their file:// paths from — the shell never has to know
    // dekho's cache layout.
    ApiRequest {
        id: historyPrefetch
        onLoaded: data => {
            dekhoRoot.historyDir = String(data.dir || "");
            dekhoRoot.historyReady = true;
        }
        onFailed: message => dekhoRoot.historyReady = false
    }

    ApiRequest {
        id: trendingPrefetch
        onLoaded: data => {
            dekhoRoot.trendingDir = String(data.dir || "");
            dekhoRoot.trendingReady = true;
        }
        onFailed: message => dekhoRoot.trendingReady = false
    }

    ApiRequest {
        id: moviePrefetch
        onLoaded: data => {
            dekhoRoot.movieDir = String(data.dir || "");
            dekhoRoot.movieReady = true;
        }
        onFailed: message => dekhoRoot.movieReady = false
    }

    ApiRequest {
        id: tvPrefetch
        onLoaded: data => {
            dekhoRoot.tvDir = String(data.dir || "");
            dekhoRoot.tvReady = true;
        }
        onFailed: message => dekhoRoot.tvReady = false
    }

    ApiRequest {
        id: searchPrefetch
        onLoaded: data => {
            dekhoRoot.searchDir = String(data.dir || "");
            dekhoRoot.searchReady = true;
        }
        onFailed: message => dekhoRoot.searchReady = false
    }

    ApiRequest {
        id: detailPosterPrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.detailPosterDir = String(data.dir || "");
            dekhoRoot.detailReady = true;
        }
        onFailed: message => dekhoRoot.detailReady = false
    }

    ApiRequest {
        id: detailBackdropPrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.detailBackdropDir = String(data.dir || "");
            // Record the FILES, into the same map the hub's hero uses: both
            // fetch w780 stills into the same cache directory, so "is this
            // backdrop on disk" is one question with one answer, and the
            // detail page gets the hero's per-file guard for free.
            for (let i = 3; i < lastArgs.length; i++)
                dekhoRoot.heroDone[lastArgs[i]] = true;
            dekhoRoot.heroTick++;
        }
        onFailed: message => dekhoRoot.detailBackdropDir = ""
    }

    ApiRequest {
        id: castPrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.castDir = String(data.dir || "");
            dekhoRoot.castReady = true;
        }
        onFailed: message => dekhoRoot.castReady = false
    }

    ApiRequest {
        id: similarPrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.similarDir = String(data.dir || "");
            dekhoRoot.similarReady = true;
        }
        onFailed: message => dekhoRoot.similarReady = false
    }

    ApiRequest {
        id: personPhotoPrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.personPhotoDir = String(data.dir || "");
            dekhoRoot.personPhotoReady = true;
        }
        onFailed: message => dekhoRoot.personPhotoReady = false
    }

    ApiRequest {
        id: creditsPrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.creditsDir = String(data.dir || "");
            dekhoRoot.creditsReady = true;
        }
        onFailed: message => dekhoRoot.creditsReady = false
    }

    ApiRequest {
        id: browsePrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.browseDir = String(data.dir || "");
            dekhoRoot.browseReady = true;
        }
        onFailed: message => dekhoRoot.browseReady = false
    }

    // Episode stills, one prefetch per season load — same size class as the
    // posters (w342 is plenty for a 16:9 thumb) and the same directory-guard
    // discipline as every other art path here.
    ApiRequest {
        id: stillsPrefetch
        memo: dekhoRoot.memo
        onLoaded: data => {
            dekhoRoot.stillsDir = String(data.dir || "");
            dekhoRoot.stillsReady = true;
        }
        onFailed: message => dekhoRoot.stillsReady = false
    }

    // --------------------------------------------------------------- search
    // Typing is not a query yet. 250 ms is the shell's other debounce (the
    // dev-services event probe) and is comfortably under the point where a
    // search field feels laggy.
    Timer {
        id: searchDebounce
        interval: 250
        repeat: false
        onTriggered: dekhoRoot.runSearch()
    }

    function runSearch() {
        const q = query.trim();
        if (!q) {
            searchItems = [];
            searchLoading = false;
            return;
        }
        searchLoading = true;
        errorText = "";
        searchReq.fetch(["search", q]);
    }

    function setQuery(text) {
        query = String(text || "");
        if (query.trim())
            searchDebounce.restart();
        else {
            searchDebounce.stop();
            searchItems = [];
            searchLoading = false;
        }
    }

    // ---------------------------------------------------------------- detail
    property var detail: null
    property var episodes: []
    property int season: 1
    property bool episodesLoading: false
    property string detailError: ""
    property string stillsDir: ""
    property bool stillsReady: false
    // The season a restored nav entry wants, held across the title request
    // because the answer is what says whether the title even has seasons. 0
    // means "decide from history", which is what a fresh open does.
    property int pendingSeason: 0

    function resumeFor(id, kind) {
        for (let i = 0; i < historyItems.length; i++) {
            const e = historyItems[i];
            if (e.id === id && e.kind === kind)
                return e;
        }
        return null;
    }

    function openTitle(item) {
        if (!item || item.id === undefined)
            return;
        push({
            view: "detail",
            id: item.id,
            kind: item.kind || "movie"
        });
        loadTitle(item.id, item.kind || "movie", 0);
    }

    function loadTitle(id, kind, wantSeason) {
        // The cursor is reset HERE, on navigation, rather than by the view
        // reacting to the title changing: a title that answers a second late
        // would otherwise pull the cursor back to Play and the page back to
        // the top under whoever had already started moving.
        detailView.resetCursor();
        detail = null;
        episodes = [];
        detailError = "";
        detailReady = false;
        castReady = false;
        similarReady = false;
        pendingSeason = wantSeason || 0;
        titleReq.fetch(["title", "--id", String(id), "--kind", String(kind)]);
    }

    function loadSeason(number) {
        if (!detail)
            return;
        season = number;
        episodes = [];
        episodesLoading = true;
        stillsReady = false;
        episodesReq.fetch(["episodes", "--id", String(detail.id), "--season", String(number)]);
    }

    // ---------------------------------------------------------------- person
    property var person: null
    property bool personLoading: false
    property string personError: ""

    // A cast row, a crew chip and a `person` payload all carry an id and a
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
        personPhotoReady = false;
        creditsReady = false;
        personReq.fetch(["person", "--id", String(id)]);
    }

    // ---------------------------------------------------------------- browse
    // The filter, live. The nav stack's browse entry carries a copy so a
    // Browse buried under two title pages comes back the way it was left.
    property string browseKind: "movie"
    property string browseSort: "popular"
    property string browseGenre: ""
    property string browseLang: ""
    property string browseMinRating: ""
    property string browseYear: ""
    // A person scope rather than a facet: it arrives from a person page (the
    // `--cast` flag `dekho api discover` grew for exactly this) and is not one
    // of the things the sidebar offers, so it has no row there. Its name is
    // carried alongside because the results header names it and the id does
    // not read as anything.
    property string browseCast: ""
    property string browseCastName: ""
    property int browsePage: 1
    property int browseTotalPages: 1
    property var browseItems: []
    property bool browseLoading: false
    property string browseError: ""
    property var browseGenres: []
    property var browseLanguages: []
    // Per-kind genre lists, kept for the visit. A plain map, not a property
    // anything binds to — `browseGenres` is what the sidebar reads.
    property var genreCache: ({})

    function openBrowse(opts) {
        const o = opts || {};
        // PUSH BEFORE MUTATING. push() snapshots the screen being buried, and
        // the snapshot reads the live properties — so writing the new filters
        // first would file them under the OUTGOING entry and a pop would come
        // back to the filters you left with, not the ones you arrived with.
        push({
            view: "browse"
        });
        if (o.kind !== undefined)
            browseKind = String(o.kind);
        if (o.genre !== undefined)
            browseGenre = String(o.genre);
        if (o.sort !== undefined)
            browseSort = String(o.sort);
        // Always assigned, never carried: a Browse opened from the header or a
        // genre chip is not still scoped to whoever you looked at last.
        browseCast = o.cast === undefined ? "" : String(o.cast);
        browseCastName = o.castName === undefined ? "" : String(o.castName);
        browsePage = 1;
        browseView.pane = "results";
        ensureFacets();
        runDiscover();
    }

    // Genres and languages are fetched the first time Browse is opened and not
    // before: a hub open must not grow two more processes for a screen most
    // opens never reach.
    function ensureFacets() {
        const cached = genreCache[browseKind];
        if (cached !== undefined) {
            browseGenres = cached;
            browseGenre = Model.genreValue(cached, browseGenre);
        } else {
            browseGenres = [];
            genresReq.fetch(["genres", "--kind", browseKind]);
        }
        if (browseLanguages.length === 0)
            languagesReq.fetch(["languages"]);
    }

    function runDiscover() {
        browseLoading = true;
        browseError = "";
        browseReq.fetch(Model.discoverArgs({
            kind: browseKind,
            sort: browseSort,
            genre: browseGenre,
            lang: browseLang,
            minRating: browseMinRating,
            year: browseYear,
            cast: browseCast,
            page: browsePage
        }));
    }

    function setFacet(facet, value) {
        switch (facet) {
        case "kind":
            if (browseKind === value)
                return;
            browseKind = value;
            // Genre ids are kind-specific in TMDB, so a film's Action does not
            // survive the switch to series — carrying it over would filter a
            // series list by an id that means something else, or nothing.
            browseGenre = "";
            ensureFacets();
            break;
        case "sort":
            browseSort = value;
            break;
        case "genre":
            browseGenre = value;
            break;
        case "lang":
            browseLang = value;
            break;
        case "rating":
            browseMinRating = value;
            break;
        case "year":
            browseYear = value;
            break;
        default:
            return;
        }
        browsePage = 1;
        runDiscover();
    }

    function stepPage(delta) {
        const next = browsePage + delta;
        if (next < 1 || next > Math.max(1, browseTotalPages))
            return;
        browsePage = next;
        runDiscover();
    }

    // A genre chip on a detail page opens Browse already filtered — the whole
    // point of making them controls. The kind comes from the title the chip
    // was on, because "Action" is a different genre for films and series.
    function openGenre(name) {
        openBrowse({
            kind: detail && detail.kind === "tv" ? "tv" : "movie",
            genre: name
        });
    }

    // The other half of a cast click. The person page answers "what else have
    // they done"; this answers "which of those, sorted and filtered" — the
    // filmography grid with the whole facet sidebar applied to it.
    function browsePerson() {
        if (!person || person.id === undefined)
            return;
        openBrowse({
            cast: person.id,
            castName: person.name || ""
        });
    }

    // -------------------------------------------------------------- playback
    property var session: null
    property bool playbackRunning: false
    property string playbackLabel: ""
    property string playbackPoster: ""
    property string playbackBackdrop: ""

    // A trailer is a second, independent run: its own transient unit
    // (dekho-trailer, see bin/dekho-play), its own NDJSON file, its own tail
    // and its own session state. All of that is one requirement — pressing
    // Trailer must not stop the film you are forty minutes into, and stopping
    // the trailer must not stop the film. Sharing any of these four would
    // break that in a different place.
    property string trailerFile: ""
    property var trailerSession: null
    property bool trailerRunning: false
    property string trailerLabel: ""

    // ------------------------------------------------------ release choice
    // The release menu, as the CLI has it: play asks `dekho api releases`,
    // shows the list, and only then starts dekho-play — with `--release` when
    // a row was chosen, without it when the Auto row was. Resume skips the
    // menu entirely: the whole point of resuming is picking up the release
    // whose pieces are already on disk.
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
        releaseView.filter = "";
        releaseView.cursor = 0;
        push({
            view: "releases"
        });
        const args = ["releases", "--id", String(detail.id), "--kind", String(detail.kind)];
        if (detail.kind === "tv" && seasonNumber > 0) {
            args.push("-s", String(seasonNumber));
            args.push("-e", String(episodeNumber));
        }
        releasesFetch.fetch(args);
    }

    ApiRequest {
        id: releasesFetch
        // No memo: seeder counts go stale in minutes, and a stale hash sent
        // back with --release is an error the panel would have caused itself.
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
            peers: 0,
            playing: false,
            error: ""
        };
        playbackRunning = true;
        playbackStopped = false;
        playbackLabel = detail.title + (detail.year ? " (" + detail.year + ")" : "") + (detail.kind === "tv" && seasonNumber > 0 ? " — " + Model.episodeCode(seasonNumber, episodeNumber) : "");
        playbackPoster = detailReady && detailPosterDir && detail.poster ? detailPosterDir + "/" + String(detail.poster).replace(/^\/+/, "") : "";
        playbackBackdrop = detailBackdropReadyDir && detail.backdrop ? detailBackdropReadyDir + "/" + String(detail.backdrop).replace(/^\/+/, "") : "";
        push({
            view: "playback",
            trailer: false
        });

        Quickshell.execDetached(args);
        // `tail -F` rather than a FileView watcher: the file does not exist
        // yet at this instant (bin/dekho-play creates it), -F waits for it to
        // appear, and re-reading a growing file on every inotify tick would
        // re-parse every line each time.
        //
        // The restart is split across two turns of the event loop. `running`
        // set false and true again in one turn is a single net change, so the
        // second film of a session would keep the FIRST film's tail — reading
        // the old path, which is now a file nothing writes to.
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
            peers: 0,
            playing: false,
            error: ""
        };
        trailerRunning = true;
        trailerStopped = false;
        trailerLabel = detail.title + (detail.year ? " (" + detail.year + ")" : "") + " — trailer";
        playbackPoster = detailReady && detailPosterDir && detail.poster ? detailPosterDir + "/" + String(detail.poster).replace(/^\/+/, "") : "";
        playbackBackdrop = detailBackdropReadyDir && detail.backdrop ? detailBackdropReadyDir + "/" + String(detail.backdrop).replace(/^\/+/, "") : "";
        push({
            view: "playback",
            trailer: true
        });

        Quickshell.execDetached([dekhoRoot.binDir + "dekho-play", "--trailer", "--session", trailerFile, "--id", String(detail.id), "--kind", String(detail.kind)]);
        // Split across two turns for the same reason the film's tail is: a
        // `running` set false and true again in one turn is a single net
        // change, and the second trailer of a session would keep the first's
        // tail on a path nothing writes to any more.
        trailerTail.running = false;
        Qt.callLater(() => trailerTail.running = true);
    }

    // STOPPING HAS TO SHOW. Both of these end the run by stopping the unit and
    // dropping the tail, which means the last line the view ever saw is the
    // green "Playing …" one — so before these flags existed the whole screen
    // stayed exactly as it was and only the button vanished, which reads as a
    // click that did nothing (user, 2026-08-20). There is no event to wait for
    // either: the unit is SIGTERMed, so the `exit` line that normally ends a
    // run may never be written, and the tail is gone by then in any case.
    // The stop is therefore recorded here, at the only place that knows it
    // happened.
    property bool playbackStopped: false
    property bool trailerStopped: false

    function stopPlayback() {
        // A tracked Process rather than execDetached, ONLY so that its exit is
        // observable: stopping a film moves it into Continue watching, and the
        // rail has to agree. The `exit` NDJSON line that normally triggers that
        // re-fetch never arrives here — the unit is SIGTERMed and the tail is
        // dropped in the same breath — so the exit of the stop itself is the
        // only signal left. bin/dekho-play's --stop waits for the unit's cgroup
        // to drain before returning, which is what makes this ordering true
        // rather than a race: dekho writes the history on its way out.
        //
        // Being in the shell's cgroup is harmless here, unlike playback (§3):
        // `systemctl --user stop` has already been handed to the user manager
        // by the time anything could kill this helper, so a shell that dies
        // mid-stop still stops the film — it only loses the re-fetch, and the
        // next open re-fetches anyway.
        stopper.running = false;
        stopper.running = true;
        playbackRunning = false;
        playbackStopped = true;
        sessionTail.running = false;
    }

    Process {
        id: stopper
        running: false
        command: [dekhoRoot.binDir + "dekho-play", "--stop"]
        // NOT memoised and NOT conditional: what was watched has moved on, and
        // this is the same fetch appendSessionLine makes when a run ends by
        // itself (see historyReq, which deliberately has no memo).
        onExited: historyReq.fetch(["history", "--limit", "12"])
    }

    function stopTrailer() {
        // --trailer --stop: the OTHER unit. Without the flag this would stop
        // the film, which is the exact failure the two unit names exist to
        // prevent.
        Quickshell.execDetached([dekhoRoot.binDir + "dekho-play", "--trailer", "--stop"]);
        trailerRunning = false;
        trailerStopped = true;
        trailerTail.running = false;
    }

    // One NDJSON line to the view's two facts: a headline and, while a swarm
    // is being measured, a meter. Shared by the film and the trailer because
    // `dekho trailer --json` speaks the same vocabulary — what differs between
    // them is what an exit MEANS, which is why that stays at the two call
    // sites below.
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
            peers: prev ? prev.peers : 0,
            playing: prev ? prev.playing : false,
            error: prev ? prev.error : ""
        };
        if (d.kind === "exit") {
            // A clean exit after mpv took over is just the film ending;
            // anything else has already put its reason in `error`.
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
        if (d.kind !== "exit")
            return;
        playbackRunning = false;
        sessionTail.running = false;
        // What was watched has moved on — the rail must agree. NOT memoised
        // (historyReq has no memo), which is the whole reason the memo is
        // opt-in per call site.
        historyReq.fetch(["history", "--limit", "12"]);
    }

    function appendTrailerLine(line) {
        const d = parseSessionLine(line);
        if (!d)
            return;
        trailerSession = foldEvent(trailerSession, d);
        // NO AUTO-HIDE ANY MORE, and its removal is the point of this change.
        // Until 2026-08-20 a `playing` event called hide(), because this was a
        // fullscreen Overlay-layer surface and the panel sat on top of the
        // very mpv it had just started ("mpv can't be visible because panel
        // overlay on top"). That was a workaround for the SURFACE, not a
        // decision about trailers: the hub closing itself is not something
        // anyone asked for, and it took the trail with it. As an ordinary
        // toplevel the floating mpv is drawn above this window by the
        // compositor, so a trailer now just plays in front of the hub and the
        // playback view keeps narrating underneath it — which is also what
        // makes Escape-ing back out of it land somewhere.
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
        // -n +1 reads from the start, so the whole trail is rebuilt even
        // though the tail is started before the file exists. -F waits for it
        // to appear rather than giving up, which is the other half of why the
        // path can be a fresh one every run.
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

    // -------------------------------------------------------------- cursor
    // Rails: which rail, and where in it. Search: one index into the grid.
    // Pointer and keyboard share ONE cursor — hovering a card focuses it, as
    // it does on tvOS, so the hero always describes the card that is lit.
    property int railIndex: 0
    property int itemIndex: 0
    property int gridIndex: -1

    // Follow the pointer, not the scroll (FilePicker's guard): a card sliding
    // under a stationary mouse re-fires hover with the same scene position,
    // and that must not steal the cursor — seen here as every Down keypress
    // handing the focus to whatever landed under the parked pointer.
    property real hoverSceneX: -1
    property real hoverSceneY: -1

    function pointerMoved(sx, sy) {
        if (sx === hoverSceneX && sy === hoverSceneY)
            return false;
        hoverSceneX = sx;
        hoverSceneY = sy;
        return true;
    }

    // The grid divides the row by its own column count (see its `columns`), so
    // the cursor reads that rather than re-deriving it and disagreeing on a
    // rounding boundary — a cursor that thinks a row is seven wide when it is
    // six skips a card on every Down.
    readonly property int gridColumns: grid.columns

    function currentRailItems() {
        const key = railKeys[railIndex];
        return key ? railItems(key) : [];
    }

    function moveRail(delta) {
        if (railKeys.length === 0)
            return;
        const next = railIndex + delta;
        if (next < 0 || next >= railKeys.length)
            return;
        railIndex = next;
        itemIndex = Model.clampIndex(itemIndex, currentRailItems().length);
        railList.positionViewAtIndex(railIndex, ListView.Contain);
    }

    function moveItem(delta) {
        const items = currentRailItems();
        if (items.length === 0)
            return;
        itemIndex = Model.clampIndex(itemIndex + delta, items.length);
    }

    // ------------------------------------------------------------- scrolling
    // THE HERO SCROLLS THE PAGE TOO. A Flickable only sees wheel events that
    // land inside it, and the hero is not inside one — so with the handler on
    // the shelves alone, more than half the screen was dead to the wheel (user,
    // 2026-08-20: "in hero, scrolling not working"). The step is shared out
    // here so that scrolling over the art and scrolling over a shelf are the
    // same gesture rather than two that happen to look alike.
    //
    // One notch is one SHELF VIEWPORT — the room under the hero at rest, not
    // the Flickable's full height, which is larger by the collapsed hero and
    // would overshoot. That first notch spends its opening 536 px collapsing
    // the hero and the rest moving shelves, in one animated run of contentY,
    // which is what makes the shrink read as part of the scroll.
    readonly property int scrollStep: Math.max(theme.space(40), panel.height - heroFull)

    function scrollHub(notches) {
        if (searching)
            scrollFlick(grid, gridScroll, notches);
        else
            scrollFlick(railList, railScroll, notches);
    }

    // Accumulated against the animation's TARGET rather than its current
    // position, so spinning the wheel does not throw away the distance an
    // in-flight step has not covered yet (doc §11's rule, same reason).
    function scrollFlick(flick, anim, notches) {
        const max = Math.max(0, flick.contentHeight - flick.height);
        const base = anim.running ? anim.to : flick.contentY;
        const to = Math.max(0, Math.min(max, base - notches * scrollStep));
        if (Math.abs(to - flick.contentY) < 1)
            return;
        anim.stop();
        anim.from = flick.contentY;
        anim.to = to;
        anim.start();
    }

    // Tab's mover for the shelves: along the rail, and off its end into the
    // next one — so the hub is one order from the first poster of Continue
    // watching to the last of Series, where the arrows would need a Down and
    // a fistful of Lefts to make the same trip.
    function moveLinear(delta) {
        if (railKeys.length === 0)
            return;
        const items = currentRailItems();
        const next = itemIndex + delta;
        if (next >= 0 && next < items.length) {
            itemIndex = next;
            return;
        }
        const nextRail = railIndex + delta;
        if (nextRail < 0 || nextRail >= railKeys.length)
            return;
        railIndex = nextRail;
        // Landing on the far end of the rail you arrived at is what makes Tab
        // and Shift+Tab exact inverses across a boundary.
        const arrived = currentRailItems();
        itemIndex = delta < 0 ? Math.max(0, arrived.length - 1) : 0;
        railList.positionViewAtIndex(railIndex, ListView.Contain);
    }

    function activateCursor() {
        if (searching) {
            if (gridIndex >= 0 && gridIndex < searchItems.length)
                openTitle(searchItems[gridIndex]);
            return;
        }
        const items = currentRailItems();
        if (itemIndex >= 0 && itemIndex < items.length)
            openTitle(items[itemIndex]);
    }

    // ----------------------------------------------------------------- keys
    function handleKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

        // Escape POPS. It used to mean "go to the hub", which was the same
        // thing while there were three screens and two of them were reached
        // from the hub; four screens in, it is the difference between undoing
        // a step and losing your place.
        if (event.key === Qt.Key_Escape) {
            back();
            return true;
        }

        if (view === "playback") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                pop();
            return true;
        }

        // Each screen owns its own cursor model; the hub owns only the hub's.
        if (view === "detail")
            return detailView.handleKey(event);
        if (view === "person")
            return personView.handleKey(event);
        if (view === "browse")
            return browseView.handleKey(event);
        if (view === "releases")
            return releaseView.handleKey(event);

        // The query line owns every printable key — this is a search-first
        // surface, so navigation lives on the arrows, as it does in the emoji
        // and clipboard pickers.
        if (event.key === Qt.Key_Backspace) {
            if (!query)
                return true;
            setQuery(FilterKeys.erased(query, ctrl));
            return true;
        }
        if (ctrl && event.key === Qt.Key_U) {
            clearQuery();
            return true;
        }
        // Ctrl, because every unmodified printable key belongs to the query
        // line above and always has.
        if (ctrl && event.key === Qt.Key_B) {
            openBrowse({});
            return true;
        }
        if (FilterKeys.printable(event)) {
            setQuery(query + event.text);
            return true;
        }

        // Tab walks whichever of the two hub bodies is showing. Above the
        // printable guard would be pointless (Tab is char 9, so it was never
        // going to reach the query line) and below the `searching` split would
        // mean writing it twice.
        const tab = Model.tabDelta(event);
        if (tab !== 0) {
            if (searching)
                moveGrid(tab);
            else
                moveLinear(tab);
            return true;
        }

        if (searching)
            return handleGridKey(event);

        switch (event.key) {
        case Qt.Key_Left:
            moveItem(-1);
            return true;
        case Qt.Key_Right:
            moveItem(1);
            return true;
        case Qt.Key_Up:
            moveRail(-1);
            return true;
        case Qt.Key_Down:
            moveRail(1);
            return true;
        case Qt.Key_Home:
            itemIndex = 0;
            return true;
        case Qt.Key_End:
            itemIndex = Math.max(0, currentRailItems().length - 1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateCursor();
            return true;
        }
        return false;
    }

    // The search grid is already one linear order — Left and Right cross row
    // boundaries by themselves — so Tab is the same step under a key that does
    // not have to be aimed, and both spellings share this.
    function moveGrid(delta) {
        gridIndex = Model.clampIndex(gridIndex + delta, searchItems.length);
        grid.positionViewAtIndex(gridIndex, GridView.Contain);
    }

    function handleGridKey(event) {
        const count = searchItems.length;
        switch (event.key) {
        case Qt.Key_Left:
            moveGrid(-1);
            return true;
        case Qt.Key_Right:
            moveGrid(1);
            return true;
        case Qt.Key_Up:
            gridIndex = Model.gridStep(gridIndex, -1, count, gridColumns);
            grid.positionViewAtIndex(gridIndex, GridView.Contain);
            return true;
        case Qt.Key_Down:
            gridIndex = Model.gridStep(gridIndex, 1, count, gridColumns);
            grid.positionViewAtIndex(gridIndex, GridView.Contain);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateCursor();
            return true;
        }
        return false;
    }

    function clearQuery() {
        setQuery("");
    }

    // ---------------------------------------------------------------- layout
    // A REAL NIRI WINDOW, not a layer-shell overlay (2026-08-20). The hub was
    // a fullscreen surface on the Overlay layer, which is above every window
    // on the screen — so the mpv it had just started came up BEHIND the thing
    // that started it, and the trailer path worked around that by hiding
    // itself on the `playing` event. As an ordinary toplevel the floating mpv
    // is drawn above this window for free, niri manages it like anything else
    // (its own workspace, a column beside something, alt-tab back), and the
    // layer-shell keyboard-grab bug class goes with it: a toplevel gets
    // ordinary focus from the compositor, so there is nothing to re-take.
    //
    // NOT FULLSCREEN, and that single word is the whole change. niri draws a
    // fullscreen window ABOVE the floating layer — measured 2026-08-20, a
    // fullscreen Quickshell window covered a floating mpv AND the bar, which
    // is precisely the situation being escaped, so a `fullscreen: true` here
    // would undo the change while looking identical. The window rule in
    // home/dot_config/niri/config.kdl opens it `open-maximized` instead: a
    // full-width column, 3467x1914 of the desk's 3490x1963, bar and gaps
    // still theirs, mpv floating over it.
    //
    // What went with the overlay: the scrim, dismiss-on-click, the card, the
    // blur negotiation and the focus workaround. What stayed and had to: the
    // window is the opaque surface0 the card used to be, full bleed, because
    // a cinema is a room with the lights off (doc §10) — and every dimension
    // inside is a proportion of panel.width/panel.height, which are window
    // dimensions now instead of screen dimensions and needed no arithmetic
    // change for that.
    FloatingWindow {
        id: panel

        title: dekhoRoot.windowTitle
        color: dekhoRoot.theme.surface0
        // ASSIGNED, NEVER BOUND. show()/hide() write this and `opened` reads
        // it back; a binding the other way would be destroyed the first time
        // niri's close-window wrote to it — see `opened`.
        visible: false
        // niri's first configure will be the maximized size, so asking for
        // the screen's own is asking for very nearly the right thing: the
        // proportional layout below is computed once, not once at a default
        // window size and again a frame later.
        implicitWidth: panel.screen ? panel.screen.width : 1600
        implicitHeight: panel.screen ? panel.screen.height : 1000
        // A floor, not a size. The layout survives being made small — the
        // poster budget and the type scale are both proportions of the window
        // (doc §10), and at half width two rails still read — but below
        // roughly this the hero has no room for a title and the rails stop
        // being rails. niri honours a toplevel's minimum size: measured
        // 2026-08-20, `set-window-width 300` gave 640 and
        // `set-window-height 200` gave 400, so a resize (Mod+R's preset
        // widths, a drag) cannot cut the hub below a hub.
        minimumSize: Qt.size(640, 400)

        onVisibleChanged: {
            if (panel.visible)
                dekhoRoot.didOpen();
            else
                dekhoRoot.didClose();
        }

        Item {
            id: keyCatcher

            anchors.fill: parent
            // The ONLY focus statement left in this module. On a layer
            // surface this was not enough: the surface's exclusive keyboard
            // grab and the scene's active focus are different things, a
            // hide()/show() pair dropped the grab to None and back, and
            // nothing handed the focus back — the panel held the whole
            // keyboard and answered no key (doc §6). show() re-took it with a
            // Qt.callLater on every summon, and OverlaySurface re-took it
            // again on visibleChanged. Both are gone because their reason is:
            // a toplevel is activated by the compositor and Qt gives the
            // focus to the scene's focus item when it is. Verified
            // 2026-08-20 the way the original bug was found — hide, reopen,
            // type — on a bare FloatingWindow with no forceActiveFocus
            // anywhere, and the keypress arrived.
            focus: true

            Keys.onPressed: event => {
                if (dekhoRoot.handleKey(event))
                    event.accepted = true;
            }

            // ------------------------------------------------------- hub
            Item {
                anchors.fill: parent
                visible: dekhoRoot.view === "hub"

                // The hero: the focused title's backdrop, edge to edge. Two
                // stacked Images crossfade — when the focus settles somewhere
                // new the old art holds underneath while the new one fades
                // over it, so skimming a rail never flashes the bare surface.
                Item {
                    id: heroArea

                    width: parent.width
                    height: dekhoRoot.heroHeight
                    // THE ART IS A FIXED FULL-PAGE BACKGROUND, and this is the
                    // window onto it. Both plates below are sized to the whole
                    // page and pinned; only this Item's height changes, so
                    // collapsing the hero UNCOVERS less of a picture that has
                    // not moved, instead of re-cropping it to a thinner band.
                    //
                    // Re-cropping was what made the collapsed header look
                    // wrong (user, 2026-08-20): PreserveAspectCrop of a 24%
                    // band is an arbitrary horizontal slice of a 16:9 still —
                    // the back of someone's head and a bit of skyline — and it
                    // changed as you scrolled, so the composition slid around
                    // under the title. A pinned plate cannot do that.
                    //
                    // Scissor clip, not a framebuffer: one rectangle bound, on
                    // one item, not the per-instance layer this module refuses
                    // everywhere else (doc §5).
                    clip: true

                    // The art can only be uncovered where nothing is drawn on
                    // top of it. Everything below this band stays the opaque
                    // surface0 page because PosterTile's corner cover is a
                    // stroke IN that colour — sixty posters over live artwork
                    // would each get a visible surface0 ring (PosterTile's
                    // header says so, and §11 says the same of FaceTile).
                    // "Full page background" therefore means a full-page plate
                    // that the page covers, not artwork behind the shelves.

                    // The hero is not inside a Flickable, so nothing here
                    // would otherwise answer the wheel — and the hero is the
                    // top half of the screen. Scrolling over the art scrolls
                    // whichever body is showing, which is also what collapses
                    // the hero itself.
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => dekhoRoot.scrollHub(event.angleDelta.y / 120)
                    }

                    Image {
                        id: heroBack

                        width: heroArea.width
                        height: dekhoRoot.heroPlateHeight
                        y: dekhoRoot.heroPlateY
                        fillMode: Image.PreserveAspectCrop
                        // w780 is the largest non-original TMDB size; decoded
                        // at most at native width. Upscaled behind the scrims
                        // it reads as depth-of-field, not as low-res.
                        sourceSize.width: Math.min(width, 1600)
                        asynchronous: true
                        cache: true
                    }

                    Image {
                        id: heroFront

                        width: heroArea.width
                        height: dekhoRoot.heroPlateHeight
                        y: dekhoRoot.heroPlateY
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Math.min(width, 1600)
                        asynchronous: true
                        cache: true
                        opacity: status === Image.Ready ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: dekhoRoot.theme.motion.slow
                                easing.type: dekhoRoot.theme.motion.easing
                            }
                        }
                    }

                    Connections {
                        target: dekhoRoot
                        function onHeroPathChanged() {
                            const p = dekhoRoot.heroPath;
                            const url = p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : "";
                            if (url === String(heroFront.source))
                                return;
                            // The outgoing art moves to the back plate before
                            // the front starts loading; same file, so the
                            // handoff is a cache hit, not a second decode.
                            heroBack.source = heroFront.source;
                            heroFront.source = url;
                        }
                    }

                    // The scrims that keep the hero type legible over any
                    // still: gradients, one node each — a blur would be a
                    // framebuffer. Bottom ramp ends ON the page colour so the
                    // art dissolves into the shelf area with no seam; the
                    // side ramp carries the title block.
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface0, 0.8)
                            }
                            GradientStop {
                                position: 0.55
                                color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface0, 0.15)
                            }
                            GradientStop {
                                position: 1.0
                                color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface0, 0.0)
                            }
                        }
                    }

                    // Top darkening, so the search line over the art stays
                    // legible. A fraction is right here: it is shading the top
                    // of whatever band there is.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Math.round(parent.height * 0.45)
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface0, 0.35)
                            }
                            GradientStop {
                                position: 1.0
                                color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface0, 0.0)
                            }
                        }
                    }

                    // The dissolve into the page, at a FIXED depth rather than
                    // a fraction of the band. As a fraction it thinned with
                    // the collapse until the art ended in a hard cut straight
                    // across the first shelf's posters — the seam a full-height
                    // hero never showed, and half of why the collapsed header
                    // looked wrong. At a fixed depth the art always dissolves
                    // over the same distance, so the band's bottom edge is
                    // never an edge.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.min(parent.height, dekhoRoot.heroFade)
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface0, 0.0)
                            }
                            GradientStop {
                                position: 0.55
                                color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface0, 0.55)
                            }
                            GradientStop {
                                position: 1.0
                                color: dekhoRoot.theme.surface0
                            }
                        }
                    }

                    // The title block, lower-left, over the strongest part of
                    // the side scrim.
                    Column {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: dekhoRoot.edgePad
                        anchors.bottomMargin: dekhoRoot.theme.space(6)
                        width: Math.round(parent.width * 0.52)
                        spacing: dekhoRoot.theme.space(3)

                        StyledText {
                            width: parent.width
                            theme: dekhoRoot.theme
                            // Steps down with the band — see heroTitleSize.
                            font.pixelSize: dekhoRoot.heroTitleSize
                            font.weight: Font.Bold
                            wrapMode: Text.Wrap
                            // One line once collapsed: two lines of a long
                            // title in a quarter-height band is the whole band.
                            maximumLineCount: dekhoRoot.heroCollapse > 0.5 ? 1 : 2
                            elide: Text.ElideRight
                            text: dekhoRoot.focusedItem ? (dekhoRoot.focusedItem.title || "") : "Movies & TV"
                        }

                        StyledText {
                            width: parent.width
                            visible: text !== ""
                            theme: dekhoRoot.theme
                            font.pixelSize: dekhoRoot.fonts.heroMeta
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            text: {
                                const it = dekhoRoot.focusedItem;
                                if (!it)
                                    return dekhoRoot.searching ? "" : "Type to search — arrows to browse";
                                const meta = Model.metaLine(it);
                                return it.resume ? (meta ? meta + "  ·  " + it.resume : it.resume) : meta;
                            }
                            color: dekhoRoot.theme.accent
                        }

                        // The synopsis and the key hints are what the collapse
                        // spends: three wrapped lines of body copy do not
                        // belong in a band a quarter of the screen tall, and
                        // dropping them is what leaves the title and its meta
                        // line legible at heroMin. Height goes with the
                        // opacity — fading alone would leave the Column
                        // reserving room for text nobody can see, and the
                        // title would stay pinned too high in the shrunken
                        // band.
                        StyledText {
                            width: parent.width
                            visible: text !== "" && opacity > 0
                            opacity: 1 - dekhoRoot.heroCollapse
                            height: implicitHeight * opacity
                            clip: true
                            theme: dekhoRoot.theme
                            font.pixelSize: dekhoRoot.fonts.heroBody
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: dekhoRoot.theme.alpha(dekhoRoot.theme.textPrimary, 0.85)
                            text: dekhoRoot.focusedItem ? (dekhoRoot.focusedItem.overview || "") : ""
                        }

                        StyledText {
                            visible: dekhoRoot.focusedItem !== null && opacity > 0
                            opacity: 1 - dekhoRoot.heroCollapse
                            height: implicitHeight * opacity
                            clip: true
                            theme: dekhoRoot.theme
                            font.pixelSize: dekhoRoot.fonts.hint
                            mono: true
                            muted: true
                            text: "↵ open    ^b browse    esc " + (dekhoRoot.searching ? "clear" : "close")
                        }
                    }
                }

                // ------------------------------------------------- shelves
                // A vertical ListView rather than a Column in a Flickable so
                // an off-screen rail's twenty posters are never instantiated
                // at all.
                ListView {
                    id: railList

                    anchors.fill: parent
                    // Anchored at the COLLAPSED hero height, with the
                    // difference carried as a spacer header below. That is
                    // what lets the hero shrink without this Flickable ever
                    // being resized — see `heroCollapse`.
                    anchors.topMargin: dekhoRoot.heroMin
                    visible: !dekhoRoot.searching
                    model: dekhoRoot.railKeys
                    clip: true
                    spacing: dekhoRoot.theme.space(6)
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 0

                    // The room the hero occupies at rest. Scrolling it away is
                    // what collapses the hero, so the two are the same gesture
                    // rather than a scroll plus an animation that has to be
                    // kept in step with it.
                    header: Item {
                        width: railList.width
                        height: dekhoRoot.heroRange
                    }

                    // A NOTCH IS A PAGE. The detail page hit this first (doc
                    // §11 — "scrolling feels too slow") and settled on a
                    // quarter of the viewport; the hub is the same complaint
                    // and the user's word for the fix was "like single page".
                    // Flickable's own step is a fixed ~60 px tuned for a
                    // desktop scroll area, which on shelves this tall is a
                    // dozen notches to reach the bottom.
                    //
                    // Accumulated against the animation's TARGET, not its
                    // current position, so spinning the wheel does not throw
                    // away the distance an in-flight animation has not covered
                    // yet — the same reason the detail page does it that way.
                    NumberAnimation {
                        id: railScroll

                        target: railList
                        property: "contentY"
                        duration: dekhoRoot.theme.motion.standard
                        easing.type: dekhoRoot.theme.motion.easing
                    }

                    // Claims the wheel over the shelves so Flickable's own
                    // much smaller step never runs as well.
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => dekhoRoot.scrollFlick(railList, railScroll, event.angleDelta.y / 120)
                    }

                    delegate: Rail {
                        required property var modelData
                        required property int index

                        width: railList.width
                        theme: dekhoRoot.theme
                        fonts: dekhoRoot.fonts
                        edgePad: dekhoRoot.edgePad
                        gutter: dekhoRoot.tileGutter
                        tileWidth: dekhoRoot.tileSize
                        title: dekhoRoot.railTitle(modelData)
                        items: dekhoRoot.railItems(modelData)
                        postersReady: dekhoRoot.railReady(modelData)
                        posterDir: dekhoRoot.railDir(modelData)
                        loading: dekhoRoot.railLoading(modelData)
                        currentIndex: dekhoRoot.railIndex === index ? dekhoRoot.itemIndex : -1
                        emptyText: modelData === "history" ? "" : "Nothing came back — check the network, or the TMDB key in ~/.config/dekho/config.toml"

                        onEntered: (i, sx, sy) => {
                            if (!dekhoRoot.pointerMoved(sx, sy))
                                return;
                            dekhoRoot.railIndex = index;
                            dekhoRoot.itemIndex = i;
                        }
                        onActivated: i => {
                            dekhoRoot.railIndex = index;
                            dekhoRoot.itemIndex = i;
                            dekhoRoot.activateCursor();
                        }
                    }
                }

                // Search results.
                GridView {
                    id: grid

                    readonly property int cellSpacing: dekhoRoot.tileGutter
                    // A row fills the row: `searchTile` is the TARGET width
                    // that picks the column count, and the width is then
                    // divided by that count. Sizing the cell from the target
                    // left the remainder against the right edge — most of a
                    // seventh card's worth, so results ended in a cut sliver.
                    readonly property int columns: Math.max(1, Math.floor(width / (dekhoRoot.searchTile + cellSpacing)))
                    readonly property int tileWidth: cellWidth - cellSpacing

                    anchors.fill: parent
                    anchors.topMargin: dekhoRoot.heroHeight
                    anchors.leftMargin: dekhoRoot.edgePad
                    anchors.rightMargin: dekhoRoot.edgePad - cellSpacing
                    visible: dekhoRoot.searching
                    model: dekhoRoot.searchItems
                    clip: true
                    cellWidth: Math.floor(width / columns)
                    cellHeight: Math.round(tileWidth * 1.5) + dekhoRoot.fonts.labelZone + dekhoRoot.theme.space(4)
                    boundsBehavior: Flickable.StopAtBounds

                    // Search results scroll at the same rate as the shelves —
                    // the query line does not change which screen you are on,
                    // so the wheel must not change what it does either.
                    NumberAnimation {
                        id: gridScroll

                        target: grid
                        property: "contentY"
                        duration: dekhoRoot.theme.motion.standard
                        easing.type: dekhoRoot.theme.motion.easing
                    }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => dekhoRoot.scrollFlick(grid, gridScroll, event.angleDelta.y / 120)
                    }

                    delegate: Item {
                        id: cell

                        required property var modelData
                        required property int index

                        width: grid.cellWidth
                        height: grid.cellHeight

                        PosterTile {
                            theme: dekhoRoot.theme
                            fonts: dekhoRoot.fonts
                            width: grid.tileWidth
                            title: cell.modelData.title || ""
                            subtitle: (cell.modelData.year ? cell.modelData.year + " · " : "") + Model.kindLabel(cell.modelData.kind)
                            posterPath: dekhoRoot.searchReady && cell.modelData.poster ? dekhoRoot.searchDir + "/" + String(cell.modelData.poster).replace(/^\/+/, "") : ""
                            current: dekhoRoot.gridIndex === cell.index

                            onEntered: (sx, sy) => {
                                if (dekhoRoot.pointerMoved(sx, sy))
                                    dekhoRoot.gridIndex = cell.index;
                            }
                            onActivated: {
                                dekhoRoot.gridIndex = cell.index;
                                dekhoRoot.activateCursor();
                            }
                        }
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: dekhoRoot.heroHeight + dekhoRoot.theme.space(10)
                    visible: dekhoRoot.searching && dekhoRoot.searchItems.length === 0
                    theme: dekhoRoot.theme
                    font.pixelSize: dekhoRoot.fonts.heroBody
                    muted: true
                    text: dekhoRoot.searchLoading ? "Searching…" : "Nothing on TMDB matched “" + dekhoRoot.query + "”"
                }

                // ------------------------------------------------- header
                // Floats over the hero art, so it is drawn after it.
                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: dekhoRoot.edgePad
                    anchors.rightMargin: dekhoRoot.edgePad
                    anchors.topMargin: dekhoRoot.theme.space(6)
                    spacing: dekhoRoot.theme.space(4)

                    OpticalGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰎁"
                        color: dekhoRoot.theme.accent
                        pixelSize: dekhoRoot.fonts.railTitle
                    }

                    // The query line. NOT a TextInput, for the same reason
                    // the emoji and clipboard pickers are not: a focused
                    // TextInput eats Left and Right for its own cursor, and
                    // those are how you walk a rail. The key catcher above
                    // owns every keystroke, and this draws what it has
                    // collected.
                    Rectangle {
                        id: searchField

                        readonly property int chipsRoom: chipsRow.visible ? chipsRow.implicitWidth + dekhoRoot.theme.space(4) : 0

                        width: parent.width - dekhoRoot.fonts.railTitle - chipsRoom - browseButton.width - dekhoRoot.theme.space(12)
                        height: Math.round(dekhoRoot.fonts.heroMeta * 2.1)
                        anchors.verticalCenter: parent.verticalCenter
                        radius: height / 2
                        color: dekhoRoot.theme.alpha(dekhoRoot.theme.surface2, 0.75)
                        border.width: dekhoRoot.theme.borderWidth
                        border.color: dekhoRoot.searching ? dekhoRoot.theme.accent : dekhoRoot.theme.alpha(dekhoRoot.theme.surface3, 0.7)

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: clearHint.left
                            anchors.leftMargin: dekhoRoot.theme.space(5)
                            anchors.rightMargin: dekhoRoot.theme.space(2)
                            anchors.verticalCenter: parent.verticalCenter
                            theme: dekhoRoot.theme
                            font.pixelSize: dekhoRoot.fonts.heroMeta
                            elide: Text.ElideLeft
                            text: dekhoRoot.query || "Search films and series"
                            color: dekhoRoot.searching ? dekhoRoot.theme.textPrimary : dekhoRoot.theme.textMuted
                        }

                        StyledText {
                            id: clearHint
                            anchors.right: parent.right
                            anchors.rightMargin: dekhoRoot.theme.space(5)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: dekhoRoot.searching
                            theme: dekhoRoot.theme
                            font.pixelSize: dekhoRoot.fonts.hint
                            mono: true
                            muted: true
                            text: "esc clears"
                        }
                    }

                    Row {
                        id: chipsRow

                        anchors.verticalCenter: parent.verticalCenter
                        spacing: dekhoRoot.theme.space(2)
                        visible: !dekhoRoot.searching

                        Repeater {
                            model: dekhoRoot.sortChips

                            ChipSurface {
                                required property var modelData

                                theme: dekhoRoot.theme
                                width: chipLabel.implicitWidth + dekhoRoot.theme.space(6)
                                height: searchField.height
                                radius: height / 2
                                chosen: dekhoRoot.sortKey === modelData.key

                                StyledText {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    theme: dekhoRoot.theme
                                    font.pixelSize: dekhoRoot.fonts.meta
                                    font.weight: Font.DemiBold
                                    text: modelData.label
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dekhoRoot.setSort(modelData.key)
                                }
                            }
                        }
                    }

                    // The way into Browse that is not a keybind. The sort
                    // chips beside it change what the two catalog rails show;
                    // this opens the screen where every other filter lives.
                    GlyphButton {
                        id: browseButton

                        anchors.verticalCenter: parent.verticalCenter
                        width: dekhoRoot.theme.space(12)
                        height: searchField.height
                        radius: height / 2
                        theme: dekhoRoot.theme
                        glyph: "󰀻"
                        glyphSize: dekhoRoot.fonts.heroMeta
                        hint: "Browse with filters (Ctrl+B)"
                        onActivated: dekhoRoot.openBrowse({})
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: dekhoRoot.theme.space(20)
                    width: Math.round(parent.width * 0.5)
                    visible: dekhoRoot.errorText !== ""
                    theme: dekhoRoot.theme
                    font.pixelSize: dekhoRoot.fonts.meta
                    color: dekhoRoot.theme.error
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: dekhoRoot.errorText
                }
            }

            // ------------------------------------------------------- detail
            DetailView {
                id: detailView

                anchors.fill: parent
                visible: dekhoRoot.view === "detail"
                theme: dekhoRoot.theme
                fonts: dekhoRoot.fonts
                edgePad: dekhoRoot.edgePad
                posterWidth: dekhoRoot.tileSize
                title: dekhoRoot.detail
                episodes: dekhoRoot.episodes
                season: dekhoRoot.season
                loadingEpisodes: dekhoRoot.episodesLoading
                resume: dekhoRoot.detail ? dekhoRoot.resumeFor(dekhoRoot.detail.id, dekhoRoot.detail.kind) : null
                backdropDir: dekhoRoot.detailBackdropReadyDir
                stillsDir: dekhoRoot.stillsDir
                stillsReady: dekhoRoot.stillsReady
                castDir: dekhoRoot.castDir
                castReady: dekhoRoot.castReady
                similarDir: dekhoRoot.similarDir
                similarReady: dekhoRoot.similarReady
                error: dekhoRoot.detailError
                // sectionIndex and cursor are the view's own state,
                // deliberately NOT bound from here: its movers assign them,
                // and an assignment destroys an incoming binding — after the
                // first arrow key the two would silently stop agreeing. The
                // nav stack reads them back through captureTop() instead.
                onSeasonPicked: number => dekhoRoot.loadSeason(number)
                onPlayed: (s, e, fromResume) => fromResume ? dekhoRoot.play(s, e, true) : dekhoRoot.openReleases(s, e)
                onTrailerRequested: dekhoRoot.playTrailer()
                onPersonPicked: p => dekhoRoot.openPerson(p)
                onGenrePicked: name => dekhoRoot.openGenre(name)
                onTitlePicked: item => dekhoRoot.openTitle(item)
                onDismissed: dekhoRoot.pop()
            }

            // ------------------------------------------------------- person
            PersonView {
                id: personView

                anchors.fill: parent
                visible: dekhoRoot.view === "person"
                theme: dekhoRoot.theme
                fonts: dekhoRoot.fonts
                edgePad: dekhoRoot.edgePad
                posterWidth: dekhoRoot.tileSize
                person: dekhoRoot.person
                loading: dekhoRoot.personLoading
                error: dekhoRoot.personError
                photoDir: dekhoRoot.personPhotoDir
                photoReady: dekhoRoot.personPhotoReady
                creditsDir: dekhoRoot.creditsDir
                creditsReady: dekhoRoot.creditsReady

                onTitlePicked: item => dekhoRoot.openTitle(item)
                onBrowseRequested: dekhoRoot.browsePerson()
                onDismissed: dekhoRoot.pop()
            }

            // ------------------------------------------------------- browse
            BrowseView {
                id: browseView

                anchors.fill: parent
                visible: dekhoRoot.view === "browse"
                theme: dekhoRoot.theme
                fonts: dekhoRoot.fonts
                edgePad: dekhoRoot.edgePad
                posterWidth: dekhoRoot.searchTile
                kind: dekhoRoot.browseKind
                sort: dekhoRoot.browseSort
                genre: dekhoRoot.browseGenre
                lang: dekhoRoot.browseLang
                minRating: dekhoRoot.browseMinRating
                year: dekhoRoot.browseYear
                castName: dekhoRoot.browseCastName
                page: dekhoRoot.browsePage
                totalPages: dekhoRoot.browseTotalPages
                genres: dekhoRoot.browseGenres
                languages: dekhoRoot.browseLanguages
                items: dekhoRoot.browseItems
                loading: dekhoRoot.browseLoading
                error: dekhoRoot.browseError
                posterDir: dekhoRoot.browseDir
                postersReady: dekhoRoot.browseReady

                onFacetChosen: (facet, value) => dekhoRoot.setFacet(facet, value)
                onPageStepped: delta => dekhoRoot.stepPage(delta)
                onTitlePicked: item => dekhoRoot.openTitle(item)
                onDismissed: dekhoRoot.pop()
            }

            // ----------------------------------------------------- releases
            ReleaseView {
                id: releaseView

                anchors.fill: parent
                visible: dekhoRoot.view === "releases"
                theme: dekhoRoot.theme
                fonts: dekhoRoot.fonts
                edgePad: dekhoRoot.edgePad
                label: dekhoRoot.detail ? dekhoRoot.detail.title + (dekhoRoot.detail.kind === "tv" && dekhoRoot.releaseSeason > 0 ? " — " + Model.episodeCode(dekhoRoot.releaseSeason, dekhoRoot.releaseEpisode) : "") : ""
                items: dekhoRoot.releaseItems
                loading: dekhoRoot.releasesLoading
                error: dekhoRoot.releasesError
                dropped: dekhoRoot.releasesDropped

                onPicked: hash => {
                    // Replace this screen with the playback one: coming back
                    // from a film must land on the detail view, not on a list
                    // of seeder counts that stopped being true.
                    const s = dekhoRoot.releaseSeason;
                    const e = dekhoRoot.releaseEpisode;
                    dekhoRoot.pop();
                    dekhoRoot.play(s, e, false, hash);
                }
                onDismissed: dekhoRoot.pop()
            }

            // ----------------------------------------------------- playback
            PlaybackView {
                anchors.fill: parent
                visible: dekhoRoot.view === "playback"
                theme: dekhoRoot.theme
                fonts: dekhoRoot.fonts
                // The trailer and the film are two runs with two sessions;
                // which one this view is describing is a property of the stack
                // entry that opened it, not of the module.
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
    }
}
