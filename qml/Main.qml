import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import QtCore

ApplicationWindow {
    id: win
    // One timing for every popup, menu and overlay: the Material popup fade
    // the volume/speed popups always used (opacity OutCubic, slight grow).
    readonly property int popupFadeInMs: 150
    readonly property int popupFadeOutMs: 150
    readonly property int popupScaleMs: 220
    width: 1100
    height: 740
    minimumWidth: 720
    minimumHeight: 480
    // Shown at the end of Component.onCompleted, once the saved size is set, so
    // the compositor never maps a default-size buffer and then resizes it
    // (Hyprland stretches the old frame on every resize: the launch "double stretch").
    visible: false
    title: pageKind === "episode" ? backend.openEpisodeTitle
         : pageKind === "show" ? backend.openShowTitle
         : pageKind === "queue" ? "Queue"
         : pageKind === "explore" ? "Find new podcasts"
         : pageKind === "search" ? "Search"
         : pageKind === "nowPlaying" ? backend.playerTitle
         : "OmaEar"
    color: theme.background
    font.family: "monospace"
    font.weight: Font.Normal

    Material.theme: theme.darkMode ? Material.Dark : Material.Light
    Material.accent: theme.accent

    function inkOn(swatch) {
        var accentLuma = 0.299 * swatch.r + 0.587 * swatch.g + 0.114 * swatch.b
        var backgroundLuma = 0.299 * theme.background.r + 0.587 * theme.background.g + 0.114 * theme.background.b
        var foregroundLuma = 0.299 * theme.foreground.r + 0.587 * theme.foreground.g + 0.114 * theme.foreground.b
        return Math.abs(accentLuma - backgroundLuma) > Math.abs(accentLuma - foregroundLuma)
                ? theme.background : theme.foreground
    }

    property bool addOpen: false
    property bool confirmAll: false
    // Show that "Mark all as played" applies to (set by confirmMarkShow).
    property double markAllShowId: 0
    property string markAllTitle: ""
    property bool confirmRemove: false
    property bool confirmQueue: false
    // ALLAN'S DECISIONS: which dialogs start with Cancel selected (so Enter cancels) and
    // which start on the confirm button, which is Omarchy Stable 4.5's default for all of them.
    // Flip a line to change one dialog.
    readonly property bool unsubscribeStartsOnCancel: false      // one podcast: starts on Unsubscribe
    readonly property bool unsubscribeAllStep1StartsOnCancel: false // Unsubscribe from all, step 1: starts on Unsubscribe from all…
    readonly property bool unsubscribeAllStep2StartsOnCancel: true  // Unsubscribe from all, final step: starts on Cancel
    readonly property bool markAllStartsOnCancel: true           // Mark all as played (one podcast)
    readonly property bool markEverythingStartsOnCancel: true    // every episode of every podcast (not built yet)
    readonly property bool clearQueueStartsOnCancel: false       // starts on Clear queue
    // Unsubscribe from all: two steps, both must be confirmed.
    property bool confirmUnsubAll: false
    property bool confirmUnsubAll2: false
    property int unsubAllCount: 0
    property bool helpOpen: false
    onHelpOpenChanged: {
        closeAllPopups()
        if (helpOpen)
            backend.requestUpdateCheck()
        else
            Qt.callLater(focusPage)
    }
    property double unsubscribeShowId: 0
    property string unsubscribeTitle: ""
    property rect normalGeometry: Qt.rect(x, y, width, height)
    property bool wasMaximized: false

    function trackNormalGeometry() {
        if (visibility === Window.Windowed)
            normalGeometry = Qt.rect(x, y, width, height)
    }

    onXChanged: trackNormalGeometry()
    onYChanged: trackNormalGeometry()
    onWidthChanged: trackNormalGeometry()
    onHeightChanged: trackNormalGeometry()
    onVisibilityChanged: function(visibility) {
        if (visibility === Window.Maximized || visibility === Window.FullScreen)
            wasMaximized = true
        else if (visibility === Window.Windowed)
            wasMaximized = false
    }

    Component.onCompleted: {
        // Tiling compositor: it picks the size in its first configure, before
        // our first frame. Asking for the saved size or maximize first made it
        // map at that size and then re-tile, shifting the covers a few px.
        if (backend.tiledSession()) {
            show()
            return
        }
        var geometry = backend.windowGeometry()
        if (geometry.valid) {
            x = geometry.x
            y = geometry.y
            width = geometry.width
            height = geometry.height
        }
        if (geometry.valid && geometry.maximized)
            showMaximized()
        else
            show()
    }
    Component.onDestruction: backend.saveWindowGeometry(
        normalGeometry.x, normalGeometry.y,
        normalGeometry.width, normalGeometry.height, wasMaximized)

    Connections {
        target: backend
        function onRaised() {
            win.show()
            win.raise()
            win.requestActivate()
        }
    }

    Shortcut {
        sequence: "Ctrl+Q"
        context: Qt.ApplicationShortcut
        onActivated: win.close()
    }
    // ---- Page navigation: one browser-style history -------------------------
    // Entries are {kind, showId, episodeId}; kind is shelf | show | episode | queue
    // | nowPlaying. The visible page is derived from history[historyIndex] only.
    // Modal dialogs are not entries; back() closes them first. history[0] is
    // always the shelf, so Back on any other page has somewhere to go.
    readonly property int historyLimit: 60
    property var history: [{ kind: "shelf", showId: 0, episodeId: 0 }]
    property int historyIndex: 0
    readonly property var currentPage: history[Math.max(0, Math.min(historyIndex, history.length - 1))]
    readonly property string pageKind: currentPage.kind
    // Keyboard grid wrap is fixed (no menu choice, saved ui.gridWrap is ignored):
    // false = "rows" (Up/Down stay in their column). Flip here to change the app's mode;
    // the nav tests set it per check.
    property bool gridWrapFull: false
    readonly property bool canGoBack: modalOpen || explore.previewOpen || explorePage.regionOpen || historyIndex > 0
    readonly property bool canGoForward: !modalOpen && historyIndex < history.length - 1
    readonly property bool modalOpen: addOpen || confirmAll || confirmRemove || confirmQueue || confirmUnsubAll || confirmUnsubAll2
    readonly property bool nowPlayingOpen: pageKind === "nowPlaying"
    readonly property bool queueOpen: pageKind === "queue"
    // True while we drive backend.open*/close*, so its change signals are not
    // mistaken for the backend dropping a page on its own.
    property bool navGuard: false

    function makeEntry(kind, showId, episodeId) {
        return { kind: kind, showId: showId || 0, episodeId: episodeId || 0 }
    }

    function sameEntry(a, b) {
        return a.kind === b.kind && a.showId === b.showId && a.episodeId === b.episodeId
    }

    function navigate(entry) {
        if (sameEntry(entry, currentPage)) {
            applyPage()
            return
        }
        var list = history.slice(0, historyIndex + 1)
        list.push(entry)
        // Cap the length but keep the shelf root at 0.
        while (list.length > historyLimit)
            list.splice(1, 1)
        history = list
        historyIndex = list.length - 1
        // A fresh visit (not Back/Forward) starts at the page's own start spot.
        var states = navStates; delete states[entry.kind]; navStates = states
        applyPage()
        Qt.callLater(navFreshEntry)
    }

    function closeModals() {
        if (!modalOpen)
            return false
        addOpen = false
        confirmAll = false
        confirmRemove = false
        confirmQueue = false
        confirmUnsubAll = false
        confirmUnsubAll2 = false
        return true
    }

    // Confirm, then mark every episode of one show played (menus on the shelf,
    // Episodes page and player bar).
    function confirmMarkShow(showId, title) {
        if (!showId)
            return
        markAllShowId = showId
        markAllTitle = title || ""
        confirmAll = true
    }

    function confirmUnsubscribeAll() {
        if (backend.showCount === 0)
            return
        confirmUnsubAll = true
    }

    // Same confirm dialog as the episodes-page Unsubscribe button.
    function confirmUnsubscribe(showId, title) {
        if (!showId)
            return
        unsubscribeShowId = showId
        unsubscribeTitle = title
        confirmRemove = true
    }

    // The menu or popup that is open right now (AppMenu, player-bar popups).
    property var openPopup: null

    // One place that closes every menu and popup when the view or layout
    // changes (page, history step, shelf list/gallery, dialogs, Info, focus loss).
    function closeAllPopups() {
        if (openPopup && openPopup.opened)
            openPopup.close()
        explorePage.closeRegions()
    }
    // Called by the C++ window filter on every mouse press, before delivery.
    // Closes the open menu/popup when the press lands outside it; the press
    // itself then carries on to whatever is underneath.
    function popupContains(p, x, y) {
        var bg = p.background || p.contentItem
        if (!bg) return false
        var q = bg.mapFromItem(null, x, y)
        return q.x >= 0 && q.y >= 0 && q.x < bg.width && q.y < bg.height
    }
    // A right-press outside swaps menus at once (no fade), so the new target's
    // menu can open on the same click; left/middle presses get the normal fade.
    function closePopupsAt(x, y, rightButton) {
        if (openPopup && openPopup.visible && !popupContains(openPopup, x, y)) {
            if (rightButton && openPopup.closeNow !== undefined)
                openPopup.closeNow()
            else
                openPopup.close()
        }
        if (explorePage.regionOpen && !popupContains(explorePage.regionPopupItem, x, y))
            explorePage.closeRegions()
    }
    onCurrentPageChanged: closeAllPopups()
    onHistoryIndexChanged: closeAllPopups()
    onActiveChanged: {
        if (active)
            theme.refreshRounding()
        else
            closeAllPopups()
    }
    Connections {
        target: backend
        function onShelfLayoutChanged() { win.closeAllPopups() }
    }

    function back() {
        // An open menu takes Esc / Back first and the page stays put.
        if (openPopup && openPopup.opened) {
            openPopup.close()
            return
        }
        if (helpOpen) {
            helpOpen = false
            return
        }
        if (closeModals())
            return
        // Explore's region picker and preview card are page-level overlays: close them first.
        if (pageKind === "explore" && explorePage.closeRegions())
            return
        if (pageKind === "explore" && explore.previewOpen) {
            explore.closePreview()
            return
        }
        if (historyIndex <= 0) {
            navShown = false   // Esc on the shelf just hides the keyboard ring
            return
        }
        historyIndex = historyIndex - 1
        applyPage()
    }

    function forward() {
        if (modalOpen || historyIndex >= history.length - 1)
            return
        historyIndex = historyIndex + 1
        applyPage()
    }

    // Kept for the C++ input filter and older call sites.
    function navigateBack() { back() }
    function navigateForward() { forward() }

    // Called from the app-wide key filter. False leaves "?" for a text field.
    function toggleHelp() {
        var item = win.activeFocusItem
        if (item instanceof TextInput)
            return false
        helpOpen = !helpOpen
        return true
    }

    function openShowPage(showId) { navigate(makeEntry("show", showId, 0)) }
    function openEpisodePage(episodeId) {
        navigate(makeEntry("episode", backend.episodeShowId(episodeId), episodeId))
    }
    function openQueuePage() { navigate(makeEntry("queue", 0, 0)) }
    function openExplorePage() { navigate(makeEntry("explore", 0, 0)) }
    // showId: search only that podcast (Episodes page ⋯); none = whole library.
    function openSearchPage(showId) {
        navigate(makeEntry("search", showId || 0, 0))
        searchPage.focusSearch()
    }
    // From library search: Explore with the same words already searched.
    function exploreFor(text) {
        navigate(makeEntry("explore", 0, 0))
        if (text.length > 0)
            explorePage.searchFor(text)
    }
    function openNowPlayingPage() {
        if (backend.playerEpisodeId !== 0)
            navigate(makeEntry("nowPlaying", 0, 0))
    }

    // Player-bar toggle. Same path as the back button and the mouse side
    // button. If Now Playing is the root entry, Back would stop; put the
    // shelf under it and show that page (forward history stays).
    function collapseNowPlaying() {
        if (pageKind === "nowPlaying" && historyIndex <= 0 && !modalOpen) {
            var list = history.slice()
            list.unshift(makeEntry("shelf", 0, 0))
            if (list.length > historyLimit)
                list.pop()
            history = list
            historyIndex = 0
            applyPage()
            return
        }
        back()
    }

    // Is this entry still showable? Shows/episodes can vanish under us.
    function entryValid(entry) {
        if (entry.kind === "show")
            return backend.hasShow(entry.showId)
        if (entry.kind === "episode")
            return backend.hasEpisode(entry.episodeId)
        if (entry.kind === "nowPlaying")
            return backend.playerEpisodeId !== 0
        return true
    }

    // Drop entries matching `gone`, fold neighbours that became duplicates, and
    // keep the index on the nearest surviving page at or before the current one.
    function pruneHistory(gone) {
        var list = []
        var index = 0
        for (var i = 0; i < history.length; ++i) {
            var entry = history[i]
            var keep = i === 0 || !gone(entry)
            if (keep && list.length > 0 && sameEntry(list[list.length - 1], entry))
                keep = false
            if (keep)
                list.push(entry)
            if (i <= historyIndex)
                index = Math.max(0, list.length - 1)
        }
        if (list.length === 0 || list[0].kind !== "shelf")
            list.unshift(makeEntry("shelf", 0, 0))
        var changed = list.length !== history.length || index !== historyIndex
        if (!changed)
            return
        history = list
        historyIndex = Math.min(index, list.length - 1)
        applyPage()
    }

    // Make the backend match the current entry. Instant: no animation, and warm
    // ShowView pages are only hidden/shown.
    function applyPage() {
        var entry = currentPage
        if (!entryValid(entry)) {
            pruneHistory(function(e) { return !entryValid(e) })
            return
        }
        pointerActive = false // new view: a resting pointer doesn't count as hover
        navShown = keyboardMode // keyboard mode: ring shows at once; mouse mode: none until a key
        navGuard = true
        if (entry.kind === "shelf") {
            backend.closeShow()
        } else if (entry.kind === "show") {
            if (backend.openShowId === entry.showId && backend.openEpisodeId !== 0)
                backend.closeEpisode()
            else if (backend.openShowId !== entry.showId)
                backend.openShow(entry.showId)
        } else if (entry.kind === "episode") {
            if (backend.openEpisodeId !== entry.episodeId)
                backend.openEpisode(entry.episodeId)
        }
        if (entry.kind === "search")
            librarySearch.setScope(entry.showId)
        // queue / nowPlaying cover the content and leave the backend as is.
        navGuard = false
        focusPage()
    }

    // Keys go to the visible page only. A hidden page keeps active focus in Qt
    // Quick, so its list would still take arrows/Enter; park focus on the content
    // stack. Search and Explore place their own focus when they show.
    function focusPage() {
        var kind = currentPage.kind
        if (kind === "search")
            return
        if (kind === "explore") {
            if (navShown) navRestoreFocus()   // else Explore focuses its own field
            return
        }
        if (modalOpen || helpOpen)
            return
        contentStack.forceActiveFocus()
    }

    // Does the backend still show what the current entry asks for?
    function backendMatchesPage() {
        var entry = currentPage
        if (entry.kind === "shelf")
            return backend.openShowId === 0
        if (entry.kind === "show")
            return backend.openShowId === entry.showId && backend.openEpisodeId === 0
        if (entry.kind === "episode")
            return backend.openEpisodeId === entry.episodeId
        return true
    }

    // The backend changed pages on its own (show removed, episode vanished in a
    // refresh, ...). Re-sync after the backend call finishes: applyPage drops
    // entries that are no longer valid and reopens the right page.
    function backendMoved() {
        if (!navGuard && !backendMatchesPage())
            Qt.callLater(function() { if (!backendMatchesPage()) applyPage() })
    }

    Connections {
        target: backend
        function onOpenShowChanged() {
            rememberShow(backend.openShowId)
            backendMoved()
        }
        function onOpenEpisodeChanged() {
            backendMoved()
        }
        function onEpisodeModelDiscarded(showId) {
            forgetShow(showId)
            Qt.callLater(function() { pruneHistory(function(e) { return !entryValid(e) }) })
        }
        function onPlayerStateChanged() {
            if (backend.playerEpisodeId === 0)
                pruneHistory(function(e) { return e.kind === "nowPlaying" })
        }
    }

    // Keyboard: Esc / Backspace / Alt+Left = back, Alt+Right = forward.
    // Qt::Key_Back / Key_Forward and the mouse side buttons are caught app-wide
    // in main.cpp (WindowInputFilter) so child MouseAreas and popups cannot eat them.
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: back()
    }
    Shortcut {
        sequence: "Alt+Left"
        context: Qt.ApplicationShortcut
        onActivated: back()
    }
    Shortcut {
        sequences: [StandardKey.Find]
        context: Qt.ApplicationShortcut
        enabled: !modalOpen
        onActivated: {
            helpOpen = false
            openSearchPage()
        }
    }
    // Episode details: Enter = the page's play button (plays or resumes from the
    // saved spot; pauses if this episode is playing). Not while typing or selecting.
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.ApplicationShortcut
        enabled: pageKind === "episode" && !modalOpen && !helpOpen && !navActive && !openPopup
                 && !(win.activeFocusItem instanceof TextInput || win.activeFocusItem instanceof TextEdit)
        onActivated: backend.playEpisode(backend.openEpisodeId)
    }
    Shortcut {
        sequence: "Alt+Right"
        context: Qt.ApplicationShortcut
        onActivated: forward()
    }
    Shortcut {
        sequence: "Backspace"
        context: Qt.ApplicationShortcut
        // Leave Backspace to TextField / TextInput / TextEdit / TextArea.
        enabled: {
            var item = win.activeFocusItem
            return !(item instanceof TextInput || item instanceof TextEdit)
        }
        onActivated: back()
    }

    // ---- Keyboard navigation (main page, Explore, Now Playing) ---------------
    // Navigation zones: top bar, content, bottom bar (PlayerBar), plus Explore's
    // search field as its own stop. Tab / Shift+Tab move to the next / previous
    // zone (wrapping; hidden or empty zones are skipped) and land where that zone
    // was last left, or on its first item. Arrow keys never leave a zone: they
    // wrap inside it. A zone is one or more areas (a row of buttons or a grid);
    // Now Playing's content stacks transport / controls / seek / notes, and
    // Up/Down step between those. Grid wrap (win.gridWrapFull, fixed):
    //   rows: absolute. Left/Right wrap within the row; Up/Down always stay in
    //         the same column and wrap top<->bottom of that column (a short last
    //         row that lacks the column is skipped, never clamped).
    //   full: Left/Right walk the whole grid in reading order, wrapping at the
    //         ends; Up/Down walk it column by column: past the bottom you land on
    //         the top of the next column, past the top on the bottom of the
    //         previous one (wrapping at the last/first column).
    // Enter activates. The ring appears after the first nav key and hides on
    // mouse movement; each page remembers its area and per-zone spots.
    readonly property var navPages: ["shelf", "explore", "nowPlaying", "show", "episode", "queue"]
    property string navArea: "grid"
    property var navIdx: ({})          // area name -> button index
    property var navStates: ({})       // page kind -> {area, idx}
    property string navKind: "shelf"   // page the state above belongs to
    property bool navShown: false
    property var navPainted: []
    property point navMouseAt: Qt.point(-1, -1)
    // Hover may steer focus only after a REAL pointer move since the last key press
    // or view change. A resting pointer over a freshly shown view (Hyprland sends
    // hover-enter then) must not steal keyboard focus or show hover rings.
    property bool pointerActive: false
    // Input mode: true after any key press, false after a real pointer move.
    // Decides where focus lands when a page is entered (see navFreshEntry).
    property bool keyboardMode: false
    // Fresh page (not Back/Forward): the spot starts at the page's natural start;
    // in keyboard mode the ring shows there at once, in mouse mode only after a key.
    //   Shelf / Queue: first item. Episodes: first episode's cover, else Back.
    //   Explore: search field. Episode: Play. Now playing: play/pause.
    function navFreshEntry() {
        if (navPages.indexOf(pageKind) < 0 || modalOpen || helpOpen) return
        navSwitchPage()
        var g = pageKind === "shelf" ? shelfView : pageKind === "queue" ? queuePage
              : pageKind === "show" ? activeShow() : null
        if (g) {
            if (g.kbdCol !== undefined) g.kbdCol = 0
            if (g.kbdEpisodeId !== undefined) g.kbdEpisodeId = 0
            if (g.navCount > 0) { g.setNavIndex(0); navArea = "grid" }
            else { var m = navIdx; m.top = 0; navIdx = m; navArea = "top" }
        }
        if (!keyboardMode) { navRefreshRing(); return }
        navShown = true
        navApplyFocus()
        navRefreshRing()
    }
    readonly property bool navActive: navShown && navPages.indexOf(pageKind) >= 0
                                      && !modalOpen && !helpOpen && !explorePage.regionOpen

    function navDefaults(kind) {
        // Unvisited zones start on their first item; the page's own start spot is kept.
        if (kind === "explore") return { area: "search", idx: { preview: 0 } }
        if (kind === "episode") return { area: "actions", idx: {} }   // Play
        if (kind === "nowPlaying") return { area: "transport", idx: { transport: playerBar.prevId !== 0 ? 2 : 1 } }
        return { area: "grid", idx: {} }
    }
    function navSwitchPage() {
        if (navKind === pageKind) return
        var states = navStates
        states[navKind] = { area: navArea, idx: navIdx }
        navStates = states
        var next = states[pageKind] || navDefaults(pageKind)
        navKind = pageKind
        navIdx = next.idx
        navArea = next.area
    }
    function navAreasFor(kind) {
        var list = []
        var player = playerBar.visible && !nowPlayingOpen ? playerBar.navItems() : []
        if (kind === "shelf") {
            list.push({ name: "top", items: shelfView.navItems() })
            list.push({ name: "grid", grid: shelfView })
        } else if (kind === "explore") {
            if (explore.previewOpen)
                return [{ name: "preview", items: explorePage.previewItems() }]
            // Find: every header control is its own Tab stop, in reading order:
            // back, search field, region, info, results, player (wrapping).
            var ex = explorePage.navItems()   // [back, flag, help] (visible ones)
            list.push({ name: "top", items: ex.filter(function(i) { return i === explorePage.backItem }) })
            list.push({ name: "search", zone: "search", items: explorePage.searchItems() })
            list.push({ name: "region", zone: "region", items: ex.filter(function(i) { return i === explorePage.regionItem }) })
            list.push({ name: "info", zone: "info", items: ex.filter(function(i) { return i === explorePage.infoItem }) })
            list.push({ name: "grid", grid: explorePage })
        } else if (kind === "show") {
            var sp = activeShow()
            if (sp) {
                list.push({ name: "top", items: sp.navItems() })
                list.push({ name: "grid", grid: sp })
            }
        } else if (kind === "queue") {
            list.push({ name: "top", items: queuePage.navItems() })
            list.push({ name: "grid", grid: queuePage })
        } else if (kind === "episode") {
            var ep = episodePage.navItems()   // [back, actions...]
            list.push({ name: "top", items: ep.slice(0, 1) })
            list.push({ name: "actions", items: ep.slice(1) })
        } else if (kind === "nowPlaying") {
            list.push({ name: "top", items: nowPlayingPage.navTop() })
            list.push({ name: "transport", items: nowPlayingPage.navTransport() })
            list.push({ name: "controls", items: nowPlayingPage.navControls() })
            list.push({ name: "seek", items: nowPlayingPage.navSeek() })
            list.push({ name: "notes", items: nowPlayingPage.navNotes() })
            player = playerBar.visible ? playerBar.navItems() : []
        }
        list.push({ name: "player", items: player })
        list.forEach(function(a) {
            if (!a.zone) a.zone = a.name === "top" || a.name === "player" ? a.name : "content"
        })
        return list.filter(function(a) { return a.grid ? a.grid.navCount > 0 : a.items.length > 0 })
    }
    function navZoneOf(name) {
        return ["top", "player", "search", "region", "info"].indexOf(name) >= 0 ? name : "content"
    }

    function navAreas() { return navAreasFor(pageKind) }
    function navFind(areas, name) {
        for (var i = 0; i < areas.length; ++i) if (areas[i].name === name) return areas[i]
        return null
    }
    function navBarIndex(name) { return navIdx[name] !== undefined ? navIdx[name] : 0 }
    function navSetBar(name, i) {
        var m = navIdx; m[name] = i; navIdx = m
        navApplyFocus()
        navRefreshRing()
    }
    // Enter an area. edge: "first", "last", or "" for where you left it.
    function navEnter(area, edge) {
        navArea = area.name
        if (area.grid) {
            area.grid.syncNavIndex()
            area.grid.setNavIndex(edge === "first" ? 0 : edge === "last" ? area.grid.navCount - 1 : area.grid.kbdIndex)
            navApplyFocus()
            navRefreshRing()
            return
        }
        var n = area.items.length
        var i = edge === "first" ? 0 : edge === "last" ? n - 1 : navBarIndex(area.name)
        navSetBar(area.name, Math.max(0, Math.min(i, n - 1)))
    }
    // Tab / Shift+Tab: previous/next zone, wrapping; lands where that zone was left.
    function navStep(step) {
        var areas = navAreas()
        if (areas.length === 0) return
        var zones = []
        areas.forEach(function(a) { if (zones.indexOf(a.zone) < 0) zones.push(a.zone) })
        var cur = navFind(areas, navArea)
        if (zones.length === 1 && cur && !cur.grid) { navMove(step); return } // one zone (preview): Tab walks it
        var at = cur ? zones.indexOf(cur.zone) : -1
        var zone = zones[at < 0 ? 0 : (at + step + zones.length) % zones.length]
        var target = navFind(areas, navIdx["@" + zone])
        if (!target || target.zone !== zone)
            target = areas.filter(function(a) { return a.zone === zone })[0]
        navEnter(target, "")
    }
    // Up/Down between the areas of one zone (Now Playing), wrapping; no-op if alone.
    function navVert(step) {
        var areas = navAreas()
        var cur = navFind(areas, navArea)
        if (!cur) return
        var same = areas.filter(function(a) { return a.zone === cur.zone })
        if (same.length < 2) return
        var at = same.indexOf(cur)
        navEnter(same[(at + step + same.length) % same.length], "")
    }
    // Grid / list arrow moves with wrap (see the zone comment above).
    function navGridKey(g, k) {
        var n = g.navCount, c = Math.max(1, Math.min(g.navColumns, n)), i = g.kbdIndex
        if (n <= 0) return
        var col = i % c, row = Math.floor(i / c), rows = Math.ceil(n / c)
        var dir = (k === Qt.Key_Left || k === Qt.Key_Up) ? -1 : 1
        var horiz = k === Qt.Key_Left || k === Qt.Key_Right
        var j = i
        if (win.gridWrapFull) {
            if (horiz) j = (i + dir + n) % n
            else if (dir > 0) j = i + c < n ? i + c : (col + 1) % c
            else if (i - c >= 0) j = i - c
            else { var pc = (col - 1 + c) % c; j = pc + Math.floor((n - 1 - pc) / c) * c }
        } else if (horiz) {
            var start = row * c, len = Math.min(c, n - start)
            j = start + (col + dir + len) % len
        } else {
            // Absolute: stay in this column; past the end wrap to its far end
            // (a short last row without this column is skipped, never clamped).
            var colRows = Math.floor((n - 1 - col) / c) + 1
            j = ((row + dir + colRows) % colRows) * c + col
        }
        if (j !== i) g.setNavIndex(j)
    }
    function navCurrent() {
        var areas = navAreas()
        if (areas.length === 0) return null
        var area = navFind(areas, navArea)
        if (!area) {
            area = navFind(areas, "grid") || areas[0]
            navEnter(area, "")
        } else if (!area.grid) {
            var n = area.items.length
            if (navBarIndex(area.name) > n - 1) navSetBar(area.name, n - 1)
        }
        return area
    }
    function navIsField(item) { return item && item.selectAll !== undefined && item.cursorPosition !== undefined }
    // A text field in a row takes real focus (its own underline is the ring);
    // everything else leaves Qt focus on the page so these keys reach shelfKey.
    function navApplyFocus() {
        if (navPages.indexOf(pageKind) < 0 || modalOpen || helpOpen || explorePage.regionOpen) return
        navSwitchPage()
        var area = navFind(navAreas(), navArea)
        var item = area && area.items ? area.items[navBarIndex(area.name)] : null
        if (navIsField(item)) {
            if (!item.activeFocus) item.forceActiveFocus()
        } else if (!contentStack.activeFocus || win.activeFocusItem instanceof TextInput) {
            contentStack.forceActiveFocus()
        }
    }
    // Focus back where navigation expects it (after dialogs, menus, Info).
    function navRestoreFocus() {
        if (navPages.indexOf(pageKind) < 0 || modalOpen || helpOpen) return
        if (pageKind === "explore" && !navShown) { explorePage.focusSearch(); return }
        navApplyFocus()
        if (!navIsField(win.activeFocusItem)) contentStack.forceActiveFocus()
    }
    // Called by a field (Explore search) for keys it doesn't use itself.
    function navFromField(key) {
        keyboardMode = true
        navShown = true
        // Only Tab leaves a field; arrows stay inside it.
        if (key === Qt.Key_Backtab) navStep(-1)
        else if (key === Qt.Key_Tab) navStep(1)
    }
    function navMove(dir) {
        var area = navCurrent()
        if (!area) return
        if (area.grid) { navGridKey(area.grid, dir < 0 ? Qt.Key_Left : Qt.Key_Right); return }
        var n = area.items.length
        navSetBar(area.name, (navBarIndex(area.name) + dir + n) % n)
    }
    // Navigation animation: true while a held key is auto-repeating (covers skip the lift).
    property bool keyRepeating: false
    function shelfKey(event) {
        if (navPages.indexOf(pageKind) < 0 || modalOpen || helpOpen) return
        navSwitchPage()
        var k = event.key
        var mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
        if (mods) return
        // Explore: typing anywhere goes to the search field.
        if (pageKind === "explore" && !explore.previewOpen && event.text.length === 1
                && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127) {
            event.accepted = true
            navArea = "search"
            navSetBar("search", 0)
            explorePage.typeIntoSearch(event.text)
            return
        }
        // Vim keys: h/j/k/l = Left/Down/Up/Right (plain only; never while typing).
        if (!(event.modifiers & Qt.ShiftModifier) && !navIsField(activeFocusItem)) {
            var vim = { [Qt.Key_H]: Qt.Key_Left, [Qt.Key_J]: Qt.Key_Down,
                        [Qt.Key_K]: Qt.Key_Up, [Qt.Key_L]: Qt.Key_Right }
            if (vim[k] !== undefined) k = vim[k]
        }
        // Menu key / Shift+F10: the ringed item's context menu.
        if (k === Qt.Key_Menu || (k === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            event.accepted = true
            var marea = navCurrent()
            navShown = true
            navRefreshRing()
            if (marea && marea.grid && marea.grid.openNavMenu !== undefined)
                marea.grid.openNavMenu()
            else if (pageKind === "shelf" && shelfView.navCount === 0)
                shelfView.openNavMenu()
            else if (pageKind === "episode")
                episodePage.openNavMenu()
            else if (pageKind === "nowPlaying")
                nowPlayingPage.openNavMenu()
            return
        }
        if (pageKind === "episode" && (k === Qt.Key_PageUp || k === Qt.Key_PageDown)) {
            event.accepted = true
            episodePage.scrollPage(k === Qt.Key_PageUp ? -1 : 1)
            return
        }
        var navKeys = [Qt.Key_Up, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right, Qt.Key_Tab, Qt.Key_Backtab,
                       Qt.Key_Return, Qt.Key_Enter, Qt.Key_Home, Qt.Key_End, Qt.Key_Delete]
        if (navKeys.indexOf(k) < 0) return
        event.accepted = true
        // Mouse resting on a cover/row: that already shows where you are, so the
        // first key moves from there instead of only revealing the ring.
        if (!navShown) {
            var hg = navFind(navAreas(), "grid")
            if (hg && hg.grid.hoverIndex !== undefined && hg.grid.hoverIndex >= 0) {
                navArea = "grid"
                navShown = true
                navRefreshRing()
            }
        }
        pointerActive = false // keys own focus until the pointer really moves
        var area = navCurrent()
        if (!area) return
        // First key only reveals where you are (no surprise jump).
        if (!navShown && k !== Qt.Key_Return && k !== Qt.Key_Enter) {
            navShown = true
            navRefreshRing()
            return
        }
        navShown = true
        if (k === Qt.Key_Tab) { navStep(1); return }
        if (k === Qt.Key_Backtab) { navStep(-1); return }
        if (area.grid) {
            var g = area.grid, idx = g.kbdIndex, count = g.navCount, cols = g.navColumns
            if (k === Qt.Key_Return || k === Qt.Key_Enter) g.openNavItem()
            else if (k === Qt.Key_Delete) { if (g.navDelete !== undefined) g.navDelete() }
            else if (k === Qt.Key_Home) g.setNavIndex(0)
            else if (k === Qt.Key_End) g.setNavIndex(count - 1)
            // Rows with parts (Episodes: cover | text): Left/Right switch parts.
            else if ((k === Qt.Key_Left || k === Qt.Key_Right) && g.navSide !== undefined
                     && g.navSide(k === Qt.Key_Left ? -1 : 1)) {}
            else navGridKey(g, k)
            return
        }
        var bi = navBarIndex(area.name)
        var item = area.items[bi]
        if (k === Qt.Key_Delete) return
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (navIsField(item)) { item.forceActiveFocus(); return }
            if (item.reloadArtwork !== undefined) item.reloadArtwork = false
            item.clicked()
        }
        else if (k === Qt.Key_Home) navSetBar(area.name, 0)
        else if (k === Qt.Key_End) navSetBar(area.name, area.items.length - 1)
        // A slider (the Now Playing scrubber) uses Left/Right itself.
        else if ((k === Qt.Key_Left || k === Qt.Key_Right) && item.navNudge !== undefined)
            item.navNudge(k === Qt.Key_Left ? -1 : 1)
        else if (k === Qt.Key_Left) navMove(-1)
        else if (k === Qt.Key_Right) navMove(1)
        // A scrolling box (Now Playing notes) scrolls first, then hands Up/Down on.
        else if ((k === Qt.Key_Up || k === Qt.Key_Down) && item.navScroll !== undefined
                 && item.navScroll(k === Qt.Key_Up ? -1 : 1)) {}
        else if (k === Qt.Key_Up) navVert(-1)
        else if (k === Qt.Key_Down) navVert(1)
    }
    // Paint the ring: clear what was lit, then light the current spot.
    function navRefreshRing() {
        for (var p = 0; p < navPainted.length; ++p) {
            var old = navPainted[p]
            if (old.kbdRing !== undefined) old.kbdRing = false
            else if (old.kbdFocus !== undefined) old.kbdFocus = false
        }
        var lit = []
        if (navActive) {
            var area = navFind(navAreas(), navArea)
            if (area && area.grid) {
                area.grid.kbdRing = true
                lit.push(area.grid)
            } else if (area) {
                var item = area.items[navBarIndex(area.name)]
                if (item && item.kbdFocus !== undefined) {
                    item.kbdFocus = true
                    lit.push(item)
                }
            }
        }
        navPainted = lit
    }
    onNavActiveChanged: navRefreshRing()
    // Also remember which area each zone was left in (per page, inside navIdx).
    onNavAreaChanged: {
        var m = navIdx; m["@" + navZoneOf(navArea)] = navArea; navIdx = m
        navRefreshRing()
    }
    onPageKindChanged: {
        navSwitchPage()
        var listPage = pageKind === "shelf" ? shelfView : pageKind === "explore" ? explorePage
                     : pageKind === "queue" ? queuePage : pageKind === "show" ? activeShow() : null
        if (listPage) Qt.callLater(function() {
            var g = pageKind === "shelf" ? shelfView : pageKind === "explore" ? explorePage
                  : pageKind === "queue" ? queuePage : pageKind === "show" ? activeShow() : null
            if (!g) return
            g.syncNavIndex()
            if (navArea === "grid" && g.navCount > 0) g.setNavIndex(g.kbdIndex)
            navRefreshRing()
        })
        else navRefreshRing()
    }
    // Dialogs and Info closing must hand the keys back (Esc out of Add feed
    // used to leave focus on the hidden field, so nothing responded).
    onModalOpenChanged: {
        if (modalOpen)
            closeAllPopups()
        else
            Qt.callLater(focusPage)
    }
    Connections {
        target: explore
        function onPreviewOpenChanged() {
            if (explore.previewOpen) {
                if (win.navShown) { win.navArea = "preview"; win.navSetBar("preview", 0) }
            } else {
                win.navArea = "grid"
            }
            Qt.callLater(win.navRestoreFocus)
            win.navRefreshRing()
        }
    }
    Connections {
        target: backend.shows
        function onModelReset() { if (win.navShown) Qt.callLater(function() { shelfView.syncNavIndex() }) }
    }
    // Queue rows can vanish under the ring (marked played elsewhere): keep it
    // on the same episode, or the nearest row, and visible.
    Connections {
        target: backend
        function onQueueChanged() {
            if (win.pageKind !== "queue") return
            Qt.callLater(function() {
                queuePage.syncNavIndex()
                win.navRefreshRing()
            })
        }
    }

    function rememberShow(showId) {
        if (!showId)
            return
        for (var i = 0; i < warmShows.count; ++i) {
            if (warmShows.get(i).showId === showId)
                return
        }
        warmShows.append({ showId: showId })
    }

    function forgetShow(showId) {
        for (var i = warmShows.count - 1; i >= 0; --i) {
            if (warmShows.get(i).showId === showId)
                warmShows.remove(i)
        }
    }

    function activeShow() {
        for (var i = 0; i < showRepeater.count; ++i) {
            var page = showRepeater.itemAt(i)
            if (page && page.showId === backend.openShowId)
                return page
        }
        return null
    }

    function zoomFromWheel(delta) {
        if (modalOpen || helpOpen)
            return false
        // Now Playing: Ctrl+wheel sizes the art (and never reaches the shelf zoom).
        if (pageKind === "nowPlaying") {
            nowPlayingPage.applyArtZoom(delta)
            return true
        }
        if (pageKind !== "shelf" && pageKind !== "show" && pageKind !== "queue")
            return false
        if (pageKind === "show") {
            var page = activeShow()
            if (page)
                page.applyZoomDelta(delta)
        } else if (pageKind === "queue") {
            queuePage.applyZoomDelta(delta)
        } else {
            shelfView.applyZoomDelta(delta)
        }
        return true
    }

    Shortcut {
        sequence: "Space"
        // Never steal a typed space from a text field (Explore search, add feed).
        enabled: !addOpen && !(win.activeFocusItem instanceof TextInput)
        context: Qt.ApplicationShortcut
        onActivated: backend.togglePlayback()
    }
    Shortcut {
        sequences: [StandardKey.ZoomIn, "Ctrl+="]
        context: Qt.ApplicationShortcut
        enabled: !modalOpen && !helpOpen && (pageKind === "shelf" || pageKind === "show" || pageKind === "queue")
        onActivated: {
            if (pageKind === "queue") {
                queuePage.zoomIn()
            } else if (pageKind === "show") {
                var page = win.activeShow()
                if (page)
                    page.zoomIn()
            } else {
                shelfView.zoomIn()
            }
        }
    }
    Shortcut {
        sequences: [StandardKey.ZoomOut]
        context: Qt.ApplicationShortcut
        enabled: !modalOpen && !helpOpen && (pageKind === "shelf" || pageKind === "show" || pageKind === "queue")
        onActivated: {
            if (pageKind === "queue") {
                queuePage.zoomOut()
            } else if (pageKind === "show") {
                var page = win.activeShow()
                if (page)
                    page.zoomOut()
            } else {
                shelfView.zoomOut()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Any real mouse movement hides the keyboard ring (its place is kept).
        HoverHandler {
            onPointChanged: {
                var p = point.scenePosition
                // > 1.5px: synthetic re-hovers after a view change jitter by sub-pixels
                if (win.navMouseAt.x >= 0 && Math.abs(p.x - win.navMouseAt.x) + Math.abs(p.y - win.navMouseAt.y) > 1.5) {
                    win.navShown = false
                    win.pointerActive = true
                    win.keyboardMode = false
                }
                win.navMouseAt = p
            }
        }

        // Content stack sits above the always-visible PlayerBar so Now Playing
        // never paints under / behind the chrome.
        Item {
            id: contentStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            focus: true
            // Shelf keyboard navigation; other pages ignore these keys here.
            Keys.onPressed: function(event) { win.keyboardMode = true; win.keyRepeating = event.isAutoRepeat; win.shelfKey(event) }
            // Navigation animation: no cover lift while a key auto-repeats; back on release.
            Keys.onReleased: function(event) { if (!event.isAutoRepeat) win.keyRepeating = false }

            ShelfView {
                id: shelfView
                anchors.fill: parent
                z: 0
                visible: win.pageKind === "shelf"
                onAddRequested: {
                    feedField.text = ""
                    win.addOpen = true
                }
                onImportRequested: opmlDialog.open()
                onExportRequested: opmlExportDialog.open()
                onQueueRequested: win.openQueuePage()
                onExploreRequested: win.openExplorePage()
                onSearchRequested: win.openSearchPage()
                onUnsubscribeRequested: function(showId, title) {
                    win.confirmUnsubscribe(showId, title)
                }
            }

            // One episode page per visited show. Back only hides it, so the
            // list and its decoded covers stay warm for the next open.
            ListModel { id: warmShows }
            Repeater {
                id: showRepeater
                model: warmShows
                ShowView {
                    showId: model.showId
                    episodeModel: backend.episodesFor(model.showId)
                    anchors.fill: parent
                    z: 1
                    visible: win.pageKind === "show" && win.currentPage.showId === showId
                    onQueueRequested: win.openQueuePage()
                }
            }

            EpisodeView {
                id: episodePage
                anchors.fill: parent
                z: 2
                visible: win.pageKind === "episode"
            }

            ExploreView {
                id: explorePage
                anchors.fill: parent
                z: 1.5
                visible: win.pageKind === "explore"
                onDismissRequested: win.back()
            }

            SearchView {
                id: searchPage
                anchors.fill: parent
                z: 1.5
                visible: win.pageKind === "search"
                onDismissRequested: win.back()
                onExploreRequested: function(text) { win.exploreFor(text) }
            }

            QueueView {
                id: queuePage
                anchors.fill: parent
                z: 1.5
                visible: win.pageKind === "queue"
                onDismissRequested: win.back()
                onClearRequested: win.confirmQueue = true
            }

            NowPlaying {
                id: nowPlayingPage
                anchors.fill: parent
                z: 3
                visible: win.pageKind === "nowPlaying" && backend.playerEpisodeId !== 0
                onDismissRequested: win.back()
            }

            // Status messages (refresh progress, results, errors) float over every
            // page, bottom centre just above the player bar (this stack ends there),
            // so they never move content. Not interactive and never focusable.
            Rectangle {
                id: statusPill
                z: 10
                enabled: false
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                readonly property real padX: 14
                width: Math.min(globalStatus.naturalWidth + 2 + padX * 2, parent.width * 0.8)
                height: globalStatus.implicitHeight + 10
                radius: theme.rButton
                color: theme.pillBackground
                border.width: 1
                border.color: Qt.rgba(theme.dim.r, theme.dim.g, theme.dim.b, 0.25)
                opacity: globalStatus.fade
                visible: opacity > 0.01
                StatusNote {
                    id: globalStatus
                    opacity: 1 // the pill carries the fade
                    anchors.centerIn: parent
                    width: parent.width - parent.padX * 2
                    horizontalAlignment: TextEdit.AlignHCenter
                    font.pixelSize: theme.bodySmall
                    activeFocusOnPress: false
                    selectByMouse: false
                }
            }
        }

        PlayerBar {
            id: playerBar
            Layout.fillWidth: true
            // Hidden on Now playing: that page has its own transport.
            visible: backend.playerEpisodeId !== 0 && !win.nowPlayingOpen
            nowPlayingOpen: win.nowPlayingOpen
            onNowPlayingRequested: win.openNowPlayingPage()
            onNowPlayingCollapseRequested: win.collapseNowPlaying()
        }
    }

    Rectangle {
        anchors.fill: parent
        id: dialogScrim
        visible: addOpen || confirmAll || confirmRemove || confirmQueue || confirmUnsubAll || confirmUnsubAll2
        // Omarchy Stable 4.5 scrim: the theme background at 70%. A click on it cancels.
        color: Qt.alpha(theme.background, 0.7)
        PopupFadeIn { host: dialogScrim }

        MouseArea {
            anchors.fill: parent
            onClicked: closeModals()
        }

        ConfirmDialog {
            id: dialog
            anchors.centerIn: parent
            visible: dialogScrim.visible
            // Messages are questions that name the thing; the button carries the verb.
            message: addOpen ? "Which feed do you want to add?"
                     : confirmUnsubAll
                     ? "Unsubscribe from all podcasts?"
                     : confirmUnsubAll2
                     ? "Unsubscribe from all " + unsubAllCount + (unsubAllCount === 1 ? " podcast?" : " podcasts?")
                     : confirmQueue
                     ? "Clear the queue (" + backend.queueCount + (backend.queueCount === 1 ? " episode)?" : " episodes)?")
                     : confirmRemove
                     ? "Unsubscribe from " + unsubscribeTitle + "?"
                     : "Mark every episode of " + markAllTitle + " as played?"
            detail: confirmUnsubAll2 ? "This can't be undone."
                    : confirmRemove ? "Playback history for this show goes with it."
                    : ""
            // Adding is not destructive: the confirm button takes the accent, not the urgent colour.
            // Mark all as played can't be undone in one step, so it is destructive too, and so are
            // both steps of Unsubscribe from all (Allan, 2026-11-12).
            destructive: !addOpen
            // Per-dialog start (see the decisions above); 4.5's own default is the confirm button.
            startOnCancel: addOpen ? false
                           : confirmUnsubAll ? unsubscribeAllStep1StartsOnCancel
                           : confirmUnsubAll2 ? unsubscribeAllStep2StartsOnCancel
                           : confirmQueue ? clearQueueStartsOnCancel
                           : confirmRemove ? unsubscribeStartsOnCancel
                           : markAllStartsOnCancel
            initialFocusItem: addOpen ? feedField : null
            // Step 1 of Unsubscribe from all only leads to step 2, which shows the
            // podcast count (in the question and on the final, destructive button).
            actionLabel: addOpen ? "Add"
                         : confirmUnsubAll ? "Unsubscribe from all\u2026"
                         : confirmUnsubAll2 ? "Unsubscribe from all (" + unsubAllCount + ")"
                         : confirmQueue ? "Clear queue"
                         : confirmRemove ? "Unsubscribe" : "Mark all as played"
            onCanceled: closeModals()
            onAccepted: {
                if (addOpen) {
                    submitFeed()
                    return
                }
                if (confirmUnsubAll) {
                    unsubAllCount = backend.showCount
                    confirmUnsubAll2 = true
                    confirmUnsubAll = false
                    return
                }
                if (confirmUnsubAll2)
                    backend.removeAllShows()
                else if (confirmQueue)
                    backend.clearQueue()
                else if (confirmRemove)
                    backend.removeShow(unsubscribeShowId)
                else
                    backend.markAllPlayed(markAllShowId)
                closeModals()
            }

            TextField {
                id: feedField
                visible: addOpen
                width: parent.width
                // Plain in-box hint instead of Material's floating label:
                // shown only while the field is empty, no animation.
                color: theme.foreground
                font.pixelSize: theme.body
                font.weight: Font.Normal
                topPadding: 10
                bottomPadding: 10
                leftPadding: 10
                rightPadding: 10
                verticalAlignment: TextInput.AlignVCenter
                Text {
                    x: feedField.leftPadding
                    anchors.verticalCenter: parent.verticalCenter
                    visible: feedField.length === 0 && feedField.preeditText.length === 0
                    text: "https://example.com/feed.xml"
                    color: theme.dim
                    font: feedField.font
                }
                Material.accent: theme.accent
                onAccepted: submitFeed()
                Keys.onTabPressed: dialog.focusButtons(1)
                Keys.onBacktabPressed: dialog.focusButtons(0)
                background: Rectangle {
                    color: theme.selection
                    opacity: 0.55
                    radius: theme.rButton
                }
            }
        }
    }

    HelpOverlay {
        anchors.fill: parent
        z: 40
        open: win.helpOpen
        onDismiss: win.helpOpen = false
    }

    // Shared "Save artwork…" dialog (Now Playing art, shelf covers).
    function saveArtworkAs(episodeId, showId) {
        var info = backend.artworkInfo(episodeId, showId)
        if (!info.available)
            return
        artSaveDialog.episodeId = episodeId
        artSaveDialog.showId = showId
        artSaveDialog.currentFolder = info.folderUrl
        artSaveDialog.selectedFile = info.fileUrl
        artSaveDialog.open()
    }
    FileDialog {
        id: artSaveDialog
        property real episodeId: 0
        property real showId: 0
        title: "Save artwork"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp *.gif)", "All files (*)"]
        onAccepted: { backend.saveArtwork(episodeId, showId, selectedFile); win.focusPage() }
        onRejected: win.focusPage()
    }
    Shortcut {
        sequence: "Ctrl+0"
        context: Qt.ApplicationShortcut
        // Reset this page's art size to its default (defaults match library.cpp).
        enabled: !modalOpen && !helpOpen
                 && (pageKind === "nowPlaying" || pageKind === "shelf" || pageKind === "show" || pageKind === "queue")
        onActivated: {
            if (pageKind === "nowPlaying")
                backend.setNowPlayingArtScale(1.0)
            else if (pageKind === "show" || pageKind === "queue")
                backend.setListCoverSize(2)
            else if (backend.shelfView === "list")
                backend.setListCoverSize(2)
            else
                backend.setShelfColumns(6)
        }
    }

    FileDialog {
        id: opmlDialog
        title: "Import OPML"
        nameFilters: ["OPML files (*.opml *.xml)", "All files (*)"]
        onAccepted: { backend.importOpml(selectedFile); win.focusPage() }
        onRejected: win.focusPage()
    }

    FileDialog {
        id: opmlExportDialog
        title: "Export OPML"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "opml"
        nameFilters: ["OPML files (*.opml)", "All files (*)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        selectedFile: currentFolder + "/omaear-subscriptions.opml"
        onAccepted: { backend.exportOpml(selectedFile); win.focusPage() }
        onRejected: win.focusPage()
    }

    function submitFeed() {
        var url = feedField.text.trim()
        if (url.length === 0)
            return
        backend.addFeed(url)
        addOpen = false
    }
}
