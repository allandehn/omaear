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
    onVisibilityChanged: {
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
        applyPage()
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
    function openSearchPage() {
        navigate(makeEntry("search", 0, 0))
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
        sequence: StandardKey.Find
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
    // Each page is a stack of areas: a row of buttons, or a grid (podcasts,
    // Explore results). Up/Down and Tab/Shift+Tab move between areas, Left/Right
    // within one and run on into the next area at the ends; a grid moves by row
    // and leaves at its top/bottom row. Enter activates. Areas that aren't
    // showing are skipped. The ring appears after the first nav key and hides on
    // mouse movement; each page remembers where it was.
    readonly property var navPages: ["shelf", "explore", "nowPlaying", "show", "episode", "queue"]
    property string navArea: "grid"
    property var navIdx: ({})          // area name -> button index
    property var navStates: ({})       // page kind -> {area, idx}
    property string navKind: "shelf"   // page the state above belongs to
    property bool navShown: false
    property var navPainted: []
    property point navMouseAt: Qt.point(-1, -1)
    readonly property bool navActive: navShown && navPages.indexOf(pageKind) >= 0
                                      && !modalOpen && !helpOpen && !explorePage.regionOpen

    function navDefaults(kind) {
        if (kind === "explore") return { area: "top", idx: { top: 1, player: 1, preview: 0 } }
        if (kind === "episode") return { area: "top", idx: { top: 1, player: 1 } }   // Play
        if (kind === "nowPlaying") return { area: "transport", idx: { top: 0, transport: playerBar.prevId !== 0 ? 2 : 1, controls: 0, seek: 0, player: 1 } }
        return { area: "grid", idx: { top: 0, player: 1 } }
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
            list.push({ name: "top", items: explorePage.navItems() })
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
            list.push({ name: "top", items: episodePage.navItems() })
        } else if (kind === "nowPlaying") {
            list.push({ name: "top", items: nowPlayingPage.navTop() })
            list.push({ name: "transport", items: nowPlayingPage.navTransport() })
            list.push({ name: "controls", items: nowPlayingPage.navControls() })
            list.push({ name: "seek", items: nowPlayingPage.navSeek() })
            player = playerBar.visible ? playerBar.navItems() : []
        }
        list.push({ name: "player", items: player })
        return list.filter(function(a) { return a.grid ? a.grid.navCount > 0 : a.items.length > 0 })
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
    function navStep(step) {        // previous/next area, wrapping
        var areas = navAreas()
        if (areas.length === 0) return
        var at = areas.indexOf(navFind(areas, navArea))
        navEnter(areas[at < 0 ? 0 : (at + step + areas.length) % areas.length], "")
    }
    function navRun(step) {         // Left/Right past the end of an area
        var areas = navAreas()
        if (areas.length === 0) return
        var at = Math.max(0, areas.indexOf(navFind(areas, navArea)))
        navEnter(areas[(at + step + areas.length) % areas.length], step > 0 ? "first" : "last")
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
        navShown = true
        if (key === Qt.Key_Left) navMove(-1)
        else if (key === Qt.Key_Right) navMove(1)
        else if (key === Qt.Key_Up || key === Qt.Key_Backtab) navStep(-1)
        else navStep(1)
    }
    function navMove(dir) {
        var area = navCurrent()
        if (!area) return
        if (area.grid) {
            var idx = area.grid.kbdIndex
            if (dir < 0 ? idx > 0 : idx < area.grid.navCount - 1) area.grid.setNavIndex(idx + dir)
            else navRun(dir)
            return
        }
        var bi = navBarIndex(area.name)
        if (dir < 0 ? bi > 0 : bi < area.items.length - 1) navSetBar(area.name, bi + dir)
        else navRun(dir)
    }
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
            var items = explorePage.navItems()
            navArea = "top"
            navSetBar("top", items.indexOf(explorePage.searchFieldItem))
            explorePage.typeIntoSearch(event.text)
            return
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
            else if (k === Qt.Key_Left) navMove(-1)
            else if (k === Qt.Key_Right) navMove(1)
            else if (k === Qt.Key_Up) { if (idx - cols >= 0) g.setNavIndex(idx - cols); else navStep(-1) }
            else if (k === Qt.Key_Down) {
                if (idx + cols < count) g.setNavIndex(idx + cols)
                // Last partial row below: land on the last item first.
                else if (Math.floor(idx / cols) < Math.floor((count - 1) / cols)) g.setNavIndex(count - 1)
                else navStep(1)
            }
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
        else if (k === Qt.Key_Up) navStep(-1)
        else if (k === Qt.Key_Down) navStep(1)
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
    onNavAreaChanged: navRefreshRing()
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
        if (pageKind !== "shelf" && pageKind !== "show")
            return false
        if (pageKind === "show") {
            var page = activeShow()
            if (page)
                page.applyZoomDelta(delta)
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
        enabled: !modalOpen && !helpOpen && (pageKind === "shelf" || pageKind === "show")
        onActivated: {
            if (pageKind === "show") {
                var page = win.activeShow()
                if (page)
                    page.zoomIn()
            } else {
                shelfView.zoomIn()
            }
        }
    }
    Shortcut {
        sequence: StandardKey.ZoomOut
        context: Qt.ApplicationShortcut
        enabled: !modalOpen && !helpOpen && (pageKind === "shelf" || pageKind === "show")
        onActivated: {
            if (pageKind === "show") {
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
                if (win.navMouseAt.x >= 0 && (p.x !== win.navMouseAt.x || p.y !== win.navMouseAt.y))
                    win.navShown = false
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
            Keys.onPressed: function(event) { win.shelfKey(event) }

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
                color: theme.darkMode ? Qt.darker(theme.background, 1.35) : Qt.lighter(theme.background, 1.12)
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
            visible: backend.playerEpisodeId !== 0
            nowPlayingOpen: win.nowPlayingOpen
            onNowPlayingRequested: win.openNowPlayingPage()
            onNowPlayingCollapseRequested: win.collapseNowPlaying()
        }
    }

    Rectangle {
        anchors.fill: parent
        id: dialogScrim
        visible: addOpen || confirmAll || confirmRemove || confirmQueue || confirmUnsubAll || confirmUnsubAll2
        color: Qt.rgba(0, 0, 0, 0.45)
        PopupFadeIn { host: dialogScrim }

        MouseArea {
            anchors.fill: parent
            onClicked: closeModals()
        }

        ConfirmDialog {
            id: dialog
            anchors.centerIn: parent
            visible: dialogScrim.visible
            title: addOpen ? "Add a feed"
                   : confirmUnsubAll2 ? "Unsubscribe from all " + unsubAllCount + (unsubAllCount === 1 ? " podcast" : " podcasts") + "?"
                   : ""
            detail: confirmUnsubAll2 ? "This can't be undone." : ""
            destructive: confirmUnsubAll2 || confirmQueue || confirmRemove
            startOnCancel: confirmUnsubAll2
            initialFocusItem: addOpen ? feedField : null
            message: addOpen ? ""
                     : confirmUnsubAll
                     ? "Unsubscribe from all podcasts?"
                     : confirmUnsubAll2
                     ? ""
                     : confirmQueue
                     ? "Clear the queue? " + backend.queueCount + (backend.queueCount === 1 ? " episode" : " episodes") + " will be removed from it."
                     : confirmRemove
                     ? "Unsubscribe from " + unsubscribeTitle + "? Playback history for this show goes with it."
                     : "Mark every episode of " + markAllTitle + " as played?"
            // Step 1 of Unsubscribe from all only leads to step 2, which shows the
            // podcast count and the final, destructive button.
            actionLabel: addOpen ? "Add"
                         : confirmUnsubAll ? "Unsubscribe from all\u2026"
                         : confirmUnsubAll2 ? "Unsubscribe from all"
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
                 && (pageKind === "nowPlaying" || pageKind === "shelf" || pageKind === "show")
        onActivated: {
            if (pageKind === "nowPlaying")
                backend.setNowPlayingArtScale(1.0)
            else if (pageKind === "show")
                backend.setEpisodeListSize(2)
            else if (backend.shelfView === "list")
                backend.setShelfListSize(0)
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
