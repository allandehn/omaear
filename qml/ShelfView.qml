import QtQuick
import QtQuick.Controls

Item {
    id: shelf
    signal addRequested()
    signal importRequested()
    signal markLibraryRequested()
    signal queueRequested()
    signal exploreRequested()
    signal searchRequested()
    signal unsubscribeRequested(double showId, string title)

    readonly property int columnFloor: 112
    readonly property real galleryGap: 12
    readonly property real galleryWidth: Math.max(1, width - 32)
    readonly property int columnsFit: Math.max(1, Math.floor((galleryWidth + galleryGap) / (columnFloor + galleryGap)))
    readonly property int columns: Math.max(1, Math.min(10, Math.min(backend.shelfColumns, columnsFit)))
    readonly property real cellWidth: galleryWidth / columns
    readonly property real coverSize: Math.max(columnFloor, cellWidth - galleryGap)
    readonly property real cellHeight: coverSize + theme.titleSize * 2.4 + 22
    readonly property real caughtUpVeil: 0.38
    // Refresh gray-out disabled (same spirit as enabled: !backend.busy comments).
    // Stronger than caught-up while refresh-all runs; cleared with backend.busy on success or failure.
    // readonly property real refreshVeil: 0.62
    // Five steps. 0 matches the original 44px list cover. Keep the count in step with shelfListSize.
    readonly property var listCoverSteps: [44, 64, 88, 120, 160]
    readonly property int listCoverBase: listCoverSteps[Math.max(0, Math.min(backend.shelfListSize, listCoverSteps.length - 1))]
    readonly property real listCover: listCoverBase * theme.textScale
    readonly property real listRowHeight: listCover + 20 * theme.textScale

    property real zoomPending: 0

    // ---- Keyboard navigation (driven by Main.qml) ---------------------------
    // Ring on the podcast at kbdIndex while Main says the grid area is active.
    property bool kbdRing: false
    property int kbdIndex: 0
    property double kbdShowId: 0
    readonly property int navCount: grid.count
    // Gallery moves by row of `columns`; the list is one column.
    readonly property int navColumns: backend.shelfView === "list" ? 1 : columns

    function navItems() {
        var list = []
        if (!actions.visible)
            return list
        for (var i = 0; i < actions.children.length; ++i) {
            var kid = actions.children[i]
            if (kid.visible && kid.enabled && kid.kbdFocus !== undefined)
                list.push(kid)
        }
        return list
    }

    // Keep the ring on the same show when the shelf reorders or filters.
    function syncNavIndex() {
        var row = kbdShowId ? backend.shows.rowOf(kbdShowId) : -1
        if (row >= 0)
            kbdIndex = row
        kbdIndex = Math.max(0, Math.min(kbdIndex, navCount - 1))
        kbdShowId = backend.shows.showIdAt(kbdIndex)
    }

    function setNavIndex(index) {
        kbdIndex = Math.max(0, Math.min(index, navCount - 1))
        kbdShowId = backend.shows.showIdAt(kbdIndex)
        var view = backend.shelfView === "list" ? showList : grid
        view.positionViewAtIndex(kbdIndex, ListView.Contain)
    }

    function openNavMenu() {
        if (navCount === 0) return
        var view = backend.shelfView === "list" ? showList : grid
        var id = backend.shows.showIdAt(kbdIndex)
        coverMenuShow = id
        coverMenuTitle = view.itemAtIndex(kbdIndex) ? view.itemAtIndex(kbdIndex).navTitle : ""
        coverMenu.info = backend.artworkInfo(0, id)
        coverMenu.popupAt(view.itemAtIndex(kbdIndex))
    }
    function openNavItem() {
        if (navCount > 0)
            win.openShowPage(backend.shows.showIdAt(kbdIndex))
    }

    function zoomIn() {
        if (backend.shelfView === "list")
            backend.setShelfListSize(backend.shelfListSize + 1)
        else
            backend.setShelfColumns(Math.min(backend.shelfColumns, columns) - 1)
    }

    function zoomOut() {
        if (backend.shelfView === "list")
            backend.setShelfListSize(backend.shelfListSize - 1)
        else if (backend.shelfColumns < 10)
            backend.setShelfColumns(backend.shelfColumns + 1)
    }

    function takeWheel(wheel) {
        if (!(wheel.modifiers & Qt.ControlModifier)) {
            wheel.accepted = false
            return
        }
        var delta = wheel.angleDelta.y
        if (delta === 0 && wheel.pixelDelta.y !== 0)
            delta = wheel.pixelDelta.y > 0 ? 120 : -120
        applyZoomDelta(delta)
        wheel.accepted = true
    }

    function applyZoomDelta(delta) {
        zoomPending += delta
        while (zoomPending >= 120) {
            zoomPending -= 120
            zoomIn()
        }
        while (zoomPending <= -120) {
            zoomPending += 120
            zoomOut()
        }
    }

    function unplayedLine(count) {
        if (count <= 0)
            return "Caught up"
        if (count === 1)
            return "1 unplayed"
        return count + " unplayed"
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64 * theme.textScale
        z: 1

        Rectangle {
            anchors.fill: parent
            color: theme.background
        }

        // Ear logo: the framed app tile, recoloured from the live Omarchy theme
        // (Design Champ's rule). Rebuilds instantly when the theme changes.
        Image {
            id: logo
            function lum(c) {
                function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
                return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
            }
            function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
            function hex(c) {
                function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
                return "#" + h(c.r) + h(c.g) + h(c.b)
            }
            readonly property bool light: lum(theme.background) > 0.5
            readonly property color tile: mix(theme.background, theme.foreground, light ? 0.05 : 0.06)
            readonly property color frame: mix(theme.background, theme.foreground, 0.20)
            readonly property color ink: {
                var a = lum(theme.accent), t = lum(tile)
                return (Math.max(a, t) + 0.05) / (Math.min(a, t) + 0.05) >= 3.0 ? theme.accent : theme.foreground
            }
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: title.verticalCenter
            // Sized from font metrics (known on the first frame), not from the
            // title's implicitHeight, which settles a frame later and used to
            // resize the logo and re-rasterize it: the launch flash.
            width: Math.round(logoMetrics.height * 1.15)
            height: width
            // Fixed raster size: the SVG is decoded once, synchronously, and
            // only scaled when the logo size changes. Theme changes still
            // rebuild it (new source string).
            sourceSize.width: 192
            sourceSize.height: 192
            asynchronous: false
            smooth: true
            mipmap: true
            cache: true
            FontMetrics {
                id: logoMetrics
                font.family: "monospace"
                font.pixelSize: theme.display
            }
            source: "data:image/svg+xml;utf8," + encodeURIComponent(
                "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 48 48'>"
                + "<rect x='1' y='1' width='46' height='46' rx='11' fill='" + hex(tile) + "' stroke='" + hex(frame) + "'/>"
                + "<path d='M13 22C13 15.5 18 11 24 11S35 15.5 35 22C35 28 31.5 30 30.5 33.5C29.5 37 27.5 40 23.5 40C20 40 17.5 37.5 17.5 34.5' fill='none' stroke='" + hex(ink) + "' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'/>"
                + "<path d='M21 18.5L28.5 23L21 27.5Z' fill='" + hex(ink) + "' stroke='" + hex(ink) + "' stroke-width='1.5' stroke-linejoin='round'/></svg>")
        }
        SelectableText {
            id: title
            anchors.left: logo.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "OmaEar"
            color: theme.foreground
            font.pixelSize: theme.display
            wrapMode: TextEdit.NoWrap
        }
        Row {
            id: actions
            // Narrow window: keep just the logo and title; the buttons come back
            // as soon as they fit without overlapping.
            visible: title.x + title.implicitWidth + 24 + implicitWidth + 28 <= header.width
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            // Refresh busy used to disable these controls; leave them usable so
            // shows can open while refresh runs. Spinner / StatusNote still use busy.
            // No podcasts yet: only Add and Import. The eye stays available once
            // any show exists, even if the unplayed filter hides every cover.
            readonly property bool hasShows: backend.showCount > 0
            IconButton {
                visible: actions.hasShows
                icon.name: backend.shelfShowAll ? "view-reveal-symbolic" : "view-conceal-symbolic"
                // tip: backend.busy ? "Refreshing…" : …
                tip: backend.shelfShowAll ? "Show unplayed only" : "Show all"
                // enabled: !backend.busy
                enabled: true
                onClicked: backend.setShelfShowAll(!backend.shelfShowAll)
            }
            IconButton {
                visible: actions.hasShows
                icon.name: backend.shelfView === "list" ? "view-list-symbolic" : "view-grid-symbolic"
                // tip: backend.busy ? "Refreshing…" : …
                tip: backend.shelfView === "list" ? "Show as gallery" : "Show as list"
                // enabled: !backend.busy
                enabled: true
                onClicked: backend.setShelfView(backend.shelfView === "list" ? "gallery" : "list")
            }
            IconButton {
                id: refreshButton
                visible: actions.hasShows
                icon.name: "view-refresh-symbolic"
                // tip: backend.busy ? "Refreshing…" : …
                tip: backend.lastRefreshLabel.length
                     ? ("Refresh — " + backend.lastRefreshLabel + "  ·  Ctrl+click reloads artwork")
                     : "Refresh  ·  Ctrl+click reloads artwork"
                // enabled: !backend.busy
                enabled: true
                property bool reloadArtwork: false
                onPressedChanged: {
                    if (pressed)
                        reloadArtwork = backend.controlHeld()
                }
                onClicked: backend.refreshAll(reloadArtwork)

                // Spin only the glyph so the hover/press background stays still.
                RotationAnimator {
                    target: refreshButton.contentItem
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: backend.busy && refreshButton.visible
                    onRunningChanged: {
                        if (!running && refreshButton.contentItem)
                            refreshButton.contentItem.rotation = 0
                    }
                }
            }
            IconButton {
                visible: actions.hasShows
                icon.source: "qrc:/icons/queue-symbolic.svg"
                tip: backend.queueCount > 0 ? "Queue (" + backend.queueCount + ")" : "Queue"
                onClicked: shelf.queueRequested()
            }
            IconButton {
                visible: actions.hasShows
                icon.name: "check-plain-symbolic"
                // enabled: !backend.busy && grid.count > 0
                enabled: grid.count > 0
                // tip: backend.busy ? "Refreshing…" : …
                tip: grid.count > 0 ? "Mark all as played" : "Nothing to mark"
                onClicked: shelf.markLibraryRequested()
            }
            IconButton {
                // With shows: search your own episodes. Empty shelf: straight to Explore.
                icon.name: "system-search-symbolic"
                tip: actions.hasShows ? "Search your episodes (Ctrl+F)" : "Explore podcasts"
                onClicked: actions.hasShows ? shelf.searchRequested() : shelf.exploreRequested()
            }
            IconButton {
                visible: actions.hasShows
                icon.source: "qrc:/icons/globe-symbolic.svg"
                tip: "Explore podcasts online"
                onClicked: shelf.exploreRequested()
            }
            IconButton {
                icon.name: "list-add-symbolic"
                tip: "Add feed"
                // enabled: !backend.busy
                enabled: true
                onClicked: shelf.addRequested()
            }
            IconButton {
                icon.name: "document-open-symbolic"
                tip: "Import OPML"
                // enabled: !backend.busy
                enabled: true
                onClicked: shelf.importRequested()
            }
            IconButton {
                icon.source: "qrc:/icons/info-symbolic.svg"
                dot: backend.updatePhase === "available"
                tip: "Info"
                onClicked: win.helpOpen = true
            }
        }
        StatusNote {
            anchors.left: title.right
            anchors.right: actions.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            font.pixelSize: theme.bodySmall
        }
    }

    Column {
        visible: grid.count === 0
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        spacing: 10
        SelectableText {
            width: parent.width
            horizontalAlignment: TextEdit.AlignHCenter
            wrapMode: TextEdit.Wrap
            color: theme.dim
            font.pixelSize: theme.body
            text: backend.shelfShowAll
                  ? "Add a feed to start. An OPML export from another podcast app brings the shows with it."
                  : "No shows with unplayed episodes."
        }
        Text {
            visible: backend.showCount === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Press ? for shortcuts"
            color: theme.dim
            font.pixelSize: theme.caption
            font.family: "monospace"
            font.weight: Font.Normal
        }
    }

    GridView {
        id: grid
        visible: backend.shelfView !== "list"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        leftMargin: 16
        rightMargin: 16
        topMargin: 8
        clip: true
        cellWidth: shelf.cellWidth
        cellHeight: shelf.cellHeight
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { }
        model: backend.shows
        cacheBuffer: height

        delegate: Item {
            readonly property string navTitle: model.title
            width: grid.cellWidth
            height: grid.cellHeight

            Column {
                width: shelf.coverSize
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Item {
                    id: cover
                    width: parent.width
                    height: width

                    Image {
                        anchors.fill: parent
                        source: model.cover
                        fillMode: Image.PreserveAspectCrop
                        // Fixed decode size: resizing the window never reloads; the GPU scales.
                        // Sync only when prewarmed in memory (paints with the first frame).
                        asynchronous: !coverCache.ready(model.cover, coverCache.tileSide)
                        cache: true
                        smooth: true
                        mipmap: true
                        sourceSize.width: coverCache.tileSide / Screen.devicePixelRatio
                        sourceSize.height: coverCache.tileSide / Screen.devicePixelRatio
                        visible: model.cover !== ""
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: model.cover === ""
                        color: theme.selection
                        Text {
                            anchors.centerIn: parent
                            text: model.title.length ? model.title.charAt(0) : "?"
                            color: model.unheard > 0 ? theme.foreground : theme.dim
                            font.pixelSize: theme.display * 1.6
                            font.weight: Font.Normal
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: model.unheard === 0
                        color: theme.background
                        opacity: shelf.caughtUpVeil
                    }
                    Rectangle {
                        visible: model.unheard > 0
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        radius: 3
                        color: theme.accent
                        height: 22 * theme.textScale
                        width: Math.max(height, countLabel.implicitWidth + 12)
                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: model.unheard > 99 ? "99+" : model.unheard
                            color: inkOnAccent(theme.accent)
                            font.pixelSize: theme.caption
                            font.weight: Font.Normal
                        }
                    }
                    // Refresh veil: left inactive so covers stay undimmed while refresh runs.
                    // Rectangle {
                    //     anchors.fill: parent
                    //     visible: backend.busy
                    //     color: theme.background
                    //     opacity: shelf.refreshVeil
                    // }
                }

                Text {
                    width: parent.width
                    text: model.title
                    color: model.unheard === 0 ? theme.dim : theme.foreground
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: theme.titleSize
                    font.weight: Font.Normal
                }
            }

            MouseArea {
                anchors.fill: parent
                // enabled: !backend.busy
                enabled: true
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton)
                        shelf.openCoverMenu(model.showId, model.title)
                    else {
                        shelf.kbdIndex = index
                        shelf.kbdShowId = model.showId
                        win.openShowPage(model.showId)
                    }
                }
                onWheel: (wheel) => shelf.takeWheel(wheel)
                Rectangle {
                    anchors.fill: cover
                    z: -1
                    color: theme.selection
                    opacity: parent.containsMouse ? 0.28 : 0
                }
            }
            // Keyboard ring: a quiet theme-foreground outline around the cover.
            Rectangle {
                visible: shelf.kbdRing && index === shelf.kbdIndex
                x: (parent.width - shelf.coverSize) / 2 - 4
                y: -4
                width: shelf.coverSize + 8
                height: shelf.coverSize + 8
                radius: 4
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.7)
            }
        }
    }

    ListView {
        id: showList
        visible: backend.shelfView === "list"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        leftMargin: 12
        rightMargin: 12
        topMargin: 4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { }
        model: backend.shows
        cacheBuffer: height
        spacing: 2

        delegate: Item {
            readonly property string navTitle: model.title
            width: showList.width
            height: shelf.listRowHeight

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: theme.selection
                opacity: rowMouse.containsMouse ? 0.35 : 0
            }
            Rectangle {
                anchors.fill: parent
                visible: shelf.kbdRing && index === shelf.kbdIndex
                radius: 4
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.7)
            }

            Item {
                id: rowArt
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: shelf.listCover
                height: width
                clip: true

                Image {
                    id: rowCover
                    anchors.fill: parent
                    source: model.cover
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: !coverCache.ready(model.cover, coverCache.rowSide)
                    cache: true
                    smooth: true
                    mipmap: true
                    sourceSize.width: coverCache.rowSide / Screen.devicePixelRatio
                    sourceSize.height: coverCache.rowSide / Screen.devicePixelRatio
                    visible: model.cover !== ""
                }
                Rectangle {
                    anchors.fill: parent
                    visible: model.cover === ""
                    color: theme.selection
                    Text {
                        anchors.centerIn: parent
                        text: model.title.length ? model.title.charAt(0) : "?"
                        color: model.unheard > 0 ? theme.foreground : theme.dim
                        font.pixelSize: theme.heading
                        font.weight: Font.Normal
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    visible: model.unheard === 0
                    color: theme.background
                    opacity: shelf.caughtUpVeil
                }
                Rectangle {
                    visible: model.unheard > 0
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: parent.width >= 96 ? 8 : 4
                    radius: 3
                    color: theme.accent
                    height: Math.min(22 * theme.textScale, parent.height * 0.5)
                    width: Math.max(height, rowBadgeText.implicitWidth + 12)
                    Text {
                        id: rowBadgeText
                        anchors.centerIn: parent
                        text: model.unheard > 99 ? "99+" : model.unheard
                        color: inkOnAccent(theme.accent)
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                    }
                }
                // Refresh veil: left inactive so list covers stay undimmed while refresh runs.
                // Rectangle {
                //     anchors.fill: parent
                //     visible: backend.busy
                //     color: theme.background
                //     opacity: shelf.refreshVeil
                // }
            }
            Column {
                anchors.left: rowArt.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 16
                spacing: 2
                Text {
                    width: parent.width
                    text: model.title
                    color: model.unheard === 0 ? theme.dim : theme.foreground
                    elide: Text.ElideRight
                    font.pixelSize: theme.titleSize
                    font.weight: Font.Normal
                }
                Text {
                    width: parent.width
                    text: shelf.unplayedLine(model.unheard)
                    color: theme.dim
                    elide: Text.ElideRight
                    font.pixelSize: theme.caption
                    font.weight: Font.Normal
                }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                // enabled: !backend.busy
                enabled: true
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton)
                        shelf.openCoverMenu(model.showId, model.title)
                    else {
                        shelf.kbdIndex = index
                        shelf.kbdShowId = model.showId
                        win.openShowPage(model.showId)
                    }
                }
                onWheel: (wheel) => shelf.takeWheel(wheel)
            }
        }
    }

    // Right-click on a show cover (gallery tile or list row).
    property real coverMenuShow: 0
    property string coverMenuTitle: ""
    function openCoverMenu(showId, title) {
        coverMenuShow = showId
        coverMenuTitle = title
        coverMenu.info = backend.artworkInfo(0, showId)
        coverMenu.popup()
    }
    AppMenu {
        id: coverMenu
        property var info: ({})
        AppMenuItem {
            text: "Copy"
            enabled: coverMenu.info.available === true
            onTriggered: backend.copyArtwork(0, shelf.coverMenuShow)
        }
        AppMenuItem {
            text: "Save artwork…"
            enabled: coverMenu.info.available === true
            onTriggered: win.saveArtworkAs(0, shelf.coverMenuShow)
        }
        AppMenuItem {
            text: "Copy image URL"
            enabled: coverMenu.info.hasUrl === true
            onTriggered: backend.copyArtworkUrl(0, shelf.coverMenuShow)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: "Unsubscribe"
            onTriggered: shelf.unsubscribeRequested(shelf.coverMenuShow, shelf.coverMenuTitle)
        }
    }

    QuietScroll {
        view: grid
        loadedCount: grid.count
        anchors.top: grid.top
        anchors.bottom: grid.bottom
        anchors.right: parent.right
        anchors.rightMargin: 2
    }
    QuietScroll {
        view: showList
        loadedCount: showList.count
        anchors.top: showList.top
        anchors.bottom: showList.bottom
        anchors.right: parent.right
        anchors.rightMargin: 2
    }

    function inkOnAccent(swatch) {
        var accentLuma = 0.299 * swatch.r + 0.587 * swatch.g + 0.114 * swatch.b
        var backgroundLuma = 0.299 * theme.background.r + 0.587 * theme.background.g + 0.114 * theme.background.b
        var foregroundLuma = 0.299 * theme.foreground.r + 0.587 * theme.foreground.g + 0.114 * theme.foreground.b
        return Math.abs(accentLuma - backgroundLuma) > Math.abs(accentLuma - foregroundLuma)
                ? theme.background : theme.foreground
    }

}
