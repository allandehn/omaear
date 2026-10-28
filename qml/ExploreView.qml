import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Controls.impl

// Explore: search the online podcast directory (iTunes) and subscribe.
// Empty search shows the local top chart. Gallery tiles match the shelf.
Item {
    id: page
    signal dismissRequested()

    property int menuRow: -1
    readonly property bool regionOpen: regionPopup.opened

    // ---- Keyboard navigation (driven by Main.qml) ---------------------------
    property bool kbdRing: false
    property int kbdIndex: 0
    readonly property int navCount: grid.count
    readonly property int navColumns: columns
    readonly property Item searchFieldItem: searchField
    function navItems() {
        return [back, searchField, flagButton, helpButton].filter(function(i) { return i.visible })
    }
    function previewItems() {
        return [previewSubscribe, previewBrowser, previewClose].filter(function(i) { return i.visible && i.enabled })
    }
    function syncNavIndex() { kbdIndex = Math.max(0, Math.min(kbdIndex, navCount - 1)) }
    function setNavIndex(index) {
        kbdIndex = Math.max(0, Math.min(index, navCount - 1))
        grid.positionViewAtIndex(kbdIndex, GridView.Contain)
    }
    function openNavMenu() {
        var tile = grid.itemAtIndex(kbdIndex)
        if (navCount === 0 || !tile) return
        menuRow = kbdIndex
        resultMenu.subscribed = tile.model.subscribed
        resultMenu.popupAt(tile)
    }
    function openNavItem() { if (navCount > 0) explore.openPreview(kbdIndex) }
    function typeIntoSearch(text) {
        searchField.forceActiveFocus()
        searchField.insert(searchField.cursorPosition, text)
        explore.setQuery(searchField.text)
    }

    readonly property var regionPopupItem: regionPopup
    function closeRegions() {
        if (!regionPopup.opened)
            return false
        regionPopup.close()
        return true
    }
    readonly property real columnFloor: 132 * theme.textScale
    readonly property real galleryGap: 12
    readonly property real galleryWidth: Math.max(1, width - 32)
    readonly property int columns: Math.max(1, Math.min(10, Math.floor((galleryWidth + galleryGap) / (columnFloor + galleryGap))))
    readonly property real cellWidth: galleryWidth / columns
    readonly property real coverSize: Math.max(columnFloor * 0.8, cellWidth - galleryGap)
    readonly property real cellHeight: coverSize + theme.titleSize * 2.4 + theme.caption * 1.4 + 26

    // Run an online search for text (handed over from library search).
    function searchFor(text) {
        searchField.text = text
        explore.setQuery(text)
        explore.searchNow()
        focusSearch()
    }

    function focusSearch() {
        searchField.forceActiveFocus()
        searchField.selectAll()
    }

    onVisibleChanged: {
        if (visible) {
            explore.activate()
            if (win.navShown && win.navArea !== "top")
                Qt.callLater(win.navRestoreFocus)
            else
                focusSearch()
        } else {
            explore.closePreview()
            regionPopup.close()
        }
    }

    function day(unix) {
        return unix > 0 ? backend.formatDay(unix) : ""
    }

    function clock(seconds) {
        if (!seconds || seconds < 1)
            return ""
        var total = Math.floor(seconds)
        var hours = Math.floor(total / 3600)
        var minutes = Math.floor((total % 3600) / 60)
        return hours > 0 ? hours + " h " + minutes + " min" : minutes + " min"
    }

    Rectangle {
        anchors.fill: parent
        color: theme.background
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64 * theme.textScale
        z: 1

        IconButton {
            id: back
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            icon.source: theme.iconBase + "back-symbolic.svg"
            tip: "Back"
            onClicked: page.dismissRequested()
        }

        TextField {
            id: searchField
            anchors.left: back.right
            anchors.leftMargin: 18
            anchors.right: flagButton.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            // Plain in-box hint like the add-feed dialog: no floating label, no animation.
            color: theme.foreground
            font.pixelSize: theme.body
            font.weight: Font.Normal
            topPadding: 10
            bottomPadding: 10
            leftPadding: 10
            // Room inside the box for the loading spinner and the clear button.
            rightPadding: 10 + clearButton.width + (spinner.visible ? spinner.width + 4 : 0)
            verticalAlignment: TextInput.AlignVCenter
            Material.accent: theme.accent

            BusyIndicator {
                id: spinner
                anchors.right: clearButton.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 24 * theme.textScale
                height: width
                running: explore.loading
                visible: explore.loading
                Material.accent: theme.accent
            }

            // Clear: only while there is text; empties the box and brings the hint back.
            IconButton {
                id: clearButton
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.length > 0
                width: visible ? implicitWidth : 0
                implicitHeight: 30 * theme.textScale
                icon.name: "window-close-symbolic"
                tip: "Clear search"
                focusPolicy: Qt.NoFocus
                onClicked: {
                    searchField.clear()
                    explore.setQuery("")
                    searchField.forceActiveFocus()
                }
            }
            Text {
                x: searchField.leftPadding
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.length === 0 && searchField.preeditText.length === 0
                text: "Search podcasts"
                color: theme.dim
                font: searchField.font
            }
            background: Rectangle {
                color: theme.selection
                opacity: 0.55
                radius: theme.rButton
            }
            onTextEdited: { explore.setQuery(text); page.kbdIndex = 0 }
            // Keys the field doesn't need hand over to page navigation: Up/Down,
            // Tab, and Left/Right at either end of the text.
            onActiveFocusChanged: if (activeFocus && win.pageKind === "explore") {
                win.navSwitchPage()
                if (win.navArea === "top" && win.navIdx.top === page.navItems().indexOf(searchField))
                    return
                win.navArea = "top"
                win.navSetBar("top", page.navItems().indexOf(searchField))
            }
            Keys.onPressed: function(event) {
                if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                    return
                var k = event.key
                var atStart = cursorPosition === 0 && selectedText.length === 0
                var atEnd = cursorPosition === length && selectedText.length === 0
                if (k === Qt.Key_Up || k === Qt.Key_Down || k === Qt.Key_Tab || k === Qt.Key_Backtab
                        || (k === Qt.Key_Left && atStart) || (k === Qt.Key_Right && atEnd)) {
                    event.accepted = true
                    win.navSwitchPage()
                    win.navArea = "top"
                    win.navFromField(k)
                }
            }
            onAccepted: explore.searchNow()
        }

        IconButton {
            id: helpButton
            visible: header.width >= 380
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            icon.source: theme.iconBase + "info-symbolic.svg"
            dot: backend.updatePhase === "available"
            tip: "Info"
            onClicked: win.helpOpen = true
        }

        // Region picker: the flag of the region in use (emoji from the two-letter
        // code) plus a small dropdown arrow. Falls back to the globe if no code.
        IconButton {
            id: flagButton
            anchors.right: helpButton.visible ? helpButton.left : parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            readonly property string code: (explore.countryCode || "").toUpperCase()
            readonly property string flag: code.length === 2
                     ? String.fromCodePoint(0x1F1E6 + code.charCodeAt(0) - 65,
                                            0x1F1E6 + code.charCodeAt(1) - 65)
                     : ""
            leftPadding: 8
            rightPadding: 6
            implicitWidth: flagRow.implicitWidth + leftPadding + rightPadding
            tip: "Region: " + explore.countryName
            contentItem: Row {
                id: flagRow
                spacing: 4 * theme.textScale
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: flagButton.flag.length > 0
                    text: flagButton.flag
                    font.family: "Noto Color Emoji"
                    font.pixelSize: theme.heading
                }
                IconImage {
                    // Symbolic: tinted like the caret beside it.
                    anchors.verticalCenter: parent.verticalCenter
                    visible: flagButton.flag.length === 0
                    source: theme.iconBase + "globe-symbolic.svg"
                    width: 18 * theme.textScale
                    height: width
                    sourceSize: Qt.size(width, height)
                    color: regionPopup.opened ? theme.foreground : theme.dim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u25BE"
                    color: regionPopup.opened ? theme.foreground : theme.dim
                    font.pixelSize: theme.body
                }
            }
            // A press on this button while the list is open already closed it
            // (press outside); don't reopen it on the same click.
            onClicked: {
                if (regionPopup.opened)
                    regionPopup.close()
                else if (Date.now() - regionPopup.closedAt > 250)
                    regionPopup.open()
            }
        }
    }

    // Heading, or the network error with a retry.
    Item {
        id: subhead
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        height: headingText.implicitHeight + 6

        Text {
            id: headingText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.5
            text: explore.error.length > 0 ? explore.error : explore.heading
            color: explore.error.length > 0 ? theme.accent : theme.dim
            font.pixelSize: theme.bodySmall
            font.weight: Font.Normal
            elide: Text.ElideRight
        }
        Text {
            anchors.left: headingText.left
            anchors.leftMargin: Math.min(headingText.implicitWidth, headingText.width) + 12
            anchors.verticalCenter: parent.verticalCenter
            visible: explore.error.length > 0
            text: "Try again"
            color: theme.accent
            font.pixelSize: theme.bodySmall
            font.underline: true
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: explore.retry()
            }
        }
    }

    Text {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: grid.count === 0 && !explore.loading && explore.error.length === 0
        text: explore.query.trim().length > 0
              ? "No podcasts found for “" + explore.query.trim() + "”."
              : "Type to search the podcast directory."
        color: theme.dim
        font.pixelSize: theme.body
        font.weight: Font.Normal
    }
    BusyIndicator {
        anchors.centerIn: parent
        visible: grid.count === 0 && explore.loading
        running: visible
        Material.accent: theme.accent
    }

    GridView {
        id: grid
        anchors.top: subhead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        leftMargin: 16
        rightMargin: 16
        topMargin: 8
        clip: true
        cellWidth: page.cellWidth
        cellHeight: page.cellHeight
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { }
        model: explore.results
        cacheBuffer: Math.max(0, height)

        delegate: Item {
            id: tile
            required property int index
            required property var model
            width: grid.cellWidth
            height: grid.cellHeight

            Column {
                width: page.coverSize
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                Item {
                    id: cover
                    width: parent.width
                    height: width
                    readonly property real coverRadius: theme.rCard
                    layer.enabled: coverRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software // no shader effects there: stay square
                    layer.smooth: true
                    readonly property Image artRef: art // "art" inside CoverClip is its own property
                    layer.effect: CoverClip { art: cover.artRef; radius: cover.coverRadius }
                    Rectangle { anchors.fill: parent; color: theme.background; z: -1 } // backing: the surface the cover sits on

                    Rectangle {
                        anchors.fill: parent
                        color: theme.selection
                        visible: art.status !== Image.Ready
                        Text {
                            anchors.centerIn: parent
                            text: tile.model.title.length ? tile.model.title.charAt(0) : "?"
                            color: theme.dim
                            font.pixelSize: theme.display * 1.6
                            font.weight: Font.Normal
                        }
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: tile.model.cover
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: Math.max(168, cover.width * 2)
                        sourceSize.height: Math.max(168, cover.height * 2)
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: theme.selection
                        opacity: tileMouse.containsMouse ? 0.28 : 0
                    }
                    Rectangle {
                        visible: page.kbdRing && tile.index === page.kbdIndex
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: theme.rButton
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.7)
                    }
                    // Subscribe badge: + / spinner / check.
                    Rectangle {
                        id: badge
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 32 * theme.textScale
                        height: width
                        radius: width / 2
                        color: tile.model.subscribed ? theme.accent : theme.background
                        opacity: tile.model.subscribed || tile.model.adding || tileMouse.containsMouse
                                 || subscribeButton.hovered ? 0.95 : 0.8
                        IconButton {
                            id: subscribeButton
                            anchors.fill: parent
                            visible: !tile.model.adding
                            icon.name: tile.model.subscribed ? "check-plain-symbolic" : "list-add-symbolic"
                            icon.width: 16 * theme.textScale
                            icon.height: 16 * theme.textScale
                            glyph: tile.model.subscribed ? win.inkOn(theme.accent) : theme.foreground
                            tip: tile.model.subscribed ? "Subscribed" : "Subscribe"
                            background: Item {}
                            onClicked: explore.subscribe(tile.index)
                        }
                        BusyIndicator {
                            anchors.fill: parent
                            anchors.margins: 2
                            visible: tile.model.adding
                            running: visible
                            Material.accent: theme.accent
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: tile.model.title
                    color: theme.foreground
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: theme.titleSize
                    font.weight: Font.Normal
                }
                Text {
                    width: parent.width
                    text: tile.model.author
                    color: theme.dim
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: theme.caption
                    font.weight: Font.Normal
                }
            }

            MouseArea {
                id: tileMouse
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        page.menuRow = tile.index
                        resultMenu.subscribed = tile.model.subscribed
                        resultMenu.popup()
                    } else {
                        page.kbdIndex = tile.index
                        explore.openPreview(tile.index)
                    }
                }
            }
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

    AppMenu {
        id: resultMenu
        property bool subscribed: false
        AppMenuItem {
            text: resultMenu.subscribed ? "Subscribed" : "Subscribe"
            enabled: !resultMenu.subscribed
            onChosen: explore.subscribe(page.menuRow)
        }
        AppMenuItem {
            text: "Preview"
            onChosen: explore.openPreview(page.menuRow)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: "Copy feed URL"
            onChosen: explore.copyFeedUrl(page.menuRow)
        }
        AppMenuItem {
            text: "Open in browser"
            onChosen: explore.openInBrowser(page.menuRow)
        }
    }

    // ---- Preview (no subscription needed). Back / Esc / side button closes it.
    Rectangle {
        id: previewScrim
        anchors.fill: parent
        visible: explore.previewOpen
        PopupFadeIn { host: previewScrim }
        z: 5
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: explore.closePreview()
            onWheel: (wheel) => wheel.accepted = true
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 720 * theme.textScale)
            height: Math.min(parent.height - 48, cardBody.implicitHeight + 40)
            color: theme.background
            border.color: theme.selection
            border.width: 1

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Flickable {
                id: cardFlick
                anchors.fill: parent
                anchors.margins: 20
                contentWidth: width
                contentHeight: cardBody.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                FastWheel { }

                Column {
                    id: cardBody
                    width: cardFlick.width
                    spacing: 14

                    Row {
                        width: parent.width
                        spacing: 18
                        Image {
                            id: previewArt
                            width: Math.min(180 * theme.textScale, parent.width * 0.35)
                            height: width
                            source: explore.preview.cover || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: width * 2
                            sourceSize.height: height * 2
                            readonly property real coverRadius: theme.rCard
                            layer.enabled: coverRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software // no shader effects there: stay square
                            layer.smooth: true
                            layer.effect: CoverClip { art: previewArt; radius: previewArt.coverRadius }
                            Rectangle {
                                anchors.fill: parent
                                color: theme.selection
                                visible: previewArt.status !== Image.Ready
                            }
                        }
                        Column {
                            width: parent.width - previewArt.width - parent.spacing
                            spacing: 6
                            SelectableText {
                                width: parent.width
                                text: explore.preview.title || ""
                                color: theme.foreground
                                font.pixelSize: theme.heading
                                wrapMode: TextEdit.Wrap
                            }
                            // Publisher link: lists this publisher's podcasts.
                            Text {
                                id: publisherLink
                                width: Math.min(implicitWidth, parent.width)
                                text: explore.preview.author || ""
                                color: theme.blue
                                font.pixelSize: theme.body
                                font.weight: Font.Normal
                                font.underline: true
                                wrapMode: Text.Wrap
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: publisherLink.text.length > 0
                                    onClicked: {
                                        searchField.text = publisherLink.text
                                        explore.searchPublisher(publisherLink.text)
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                color: theme.dim
                                font.pixelSize: theme.caption
                                font.weight: Font.Normal
                                wrapMode: Text.Wrap
                                text: {
                                    var p = explore.preview
                                    var parts = []
                                    if (p.genre) parts.push(p.genre)
                                    var n = p.trackCount || p.feedEpisodes || 0
                                    if (n > 0) parts.push(n + (n === 1 ? " episode" : " episodes"))
                                    if (p.released) parts.push("Latest " + page.day(p.released))
                                    return parts.join(" · ")
                                }
                            }
                            Item { width: 1; height: 6 }
                            Row {
                                spacing: 10
                                IconButton {
                                    id: previewSubscribe
                                    visible: !explore.preview.adding
                                    icon.name: explore.preview.subscribed ? "check-plain-symbolic" : "list-add-symbolic"
                                    caption: explore.preview.subscribed ? "Subscribed" : "Subscribe"
                                    glyph: explore.preview.subscribed ? theme.dim : theme.accent
                                    enabled: !explore.preview.subscribed
                                    onClicked: explore.subscribePreview()
                                }
                                BusyIndicator {
                                    visible: explore.preview.adding === true
                                    running: visible
                                    width: 32 * theme.textScale
                                    height: width
                                    Material.accent: theme.accent
                                }
                                IconButton {
                                    id: previewBrowser
                                    visible: (explore.preview.viewUrl || "") !== ""
                                    icon.name: "web-browser-symbolic"
                                    tip: "Open in browser"
                                    onClicked: explore.openInBrowser(explore.preview.row)
                                }
                            }
                        }
                    }

                    SelectableText {
                        width: parent.width
                        visible: text.length > 0
                        text: explore.preview.description || ""
                        color: theme.foreground
                        font.pixelSize: theme.bodySmall
                        wrapMode: TextEdit.Wrap
                    }

                    Text {
                        visible: explore.previewLoading
                        text: "Loading episodes…"
                        color: theme.dim
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                    }
                    Text {
                        visible: !explore.previewLoading && (explore.preview.feedError || "") !== ""
                        text: explore.preview.feedError || ""
                        color: theme.accent
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                    }

                    Text {
                        visible: (explore.preview.episodes || []).length > 0
                        text: "Latest episodes"
                        color: theme.dim
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                    }
                    Repeater {
                        model: explore.preview.episodes || []
                        delegate: Column {
                            required property var modelData
                            width: cardBody.width
                            spacing: 2
                            Text {
                                width: parent.width
                                text: modelData.title
                                color: theme.foreground
                                font.pixelSize: theme.body
                                font.weight: Font.Normal
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: page.day(modelData.published)
                                      + (modelData.duration > 0 ? " · " + page.clock(modelData.duration) : "")
                                color: theme.dim
                                font.pixelSize: theme.caption
                                font.weight: Font.Normal
                            }
                        }
                    }
                }
            }

            IconButton {
                id: previewClose
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                icon.name: "window-close-symbolic"
                glyph: theme.dim
                tip: "Close"
                onClicked: explore.closePreview()
            }
        }
    }

    // Store region picker: "Automatic (<detected>)" then the curated storefronts.
    // Typing in the filter narrows the list; Up/Down + Enter pick from the keyboard.
    Popup {
        id: regionPopup
        readonly property real rowHeight: theme.titleSize * 1.25 + 14
        property string filter: ""
        readonly property var entries: {
            var f = filter.trim().toLowerCase()
            var autoLabel = "Automatic (" + explore.autoCountryName + ")"
            var out = []
            if (f.length === 0 || autoLabel.toLowerCase().indexOf(f) >= 0)
                out.push({ code: "", name: autoLabel })
            var all = explore.regions
            for (var i = 0; i < all.length; ++i) {
                var r = all[i]
                if (f.length === 0 || r.name.toLowerCase().indexOf(f) >= 0 || r.code === f)
                    out.push(r)
            }
            return out
        }

        function choose(code) {
            close()
            explore.setRegion(code)
        }

        function currentIndexIn(list) {
            for (var i = 0; i < list.length; ++i) {
                if (list[i].code === explore.regionOverride)
                    return i
            }
            return 0
        }

        x: Math.max(8, page.width - width - 16)
        y: header.height - 6
        width: Math.min(page.width - 16, 300 * theme.textScale)
        height: Math.min(page.height - y - 12,
                         filterField.implicitHeight + 8 + Math.max(1, entries.length) * rowHeight + 10)
        padding: 1
        topPadding: 4
        bottomPadding: 4
        focus: true
        // Any press outside the list closes it, including the search field.
        closePolicy: Popup.CloseOnEscape  // outside presses: Main.closePopupsAt
        modal: false
        dim: false
        property double closedAt: 0
        Material.elevation: 0
        // Shared fade-in; closing stays instant (closedAt toggle logic).
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; easing.type: Easing.OutCubic; duration: win.popupFadeInMs }
        }
        exit: null

        background: Rectangle {
            color: theme.background
            border.color: theme.foreground
            border.width: 1
            radius: theme.rButton
        }

        onAboutToShow: {
            filter = ""
            filterField.text = ""
            regionList.currentIndex = currentIndexIn(entries)
            regionList.positionViewAtIndex(regionList.currentIndex, ListView.Center)
        }
        onOpened: filterField.forceActiveFocus()
        onClosed: {
            closedAt = Date.now()
            if (page.visible && win.navShown && win.navArea === "top")
                Qt.callLater(win.navRestoreFocus)   // ring back on the flag
            else if (page.visible)
                searchField.forceActiveFocus()
        }

        contentItem: Item {
            TextField {
                id: filterField
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 6
                color: theme.foreground
                font.pixelSize: theme.bodySmall
                font.weight: Font.Normal
                topPadding: 7
                bottomPadding: 7
                leftPadding: 8
                rightPadding: 8
                verticalAlignment: TextInput.AlignVCenter
                Material.accent: theme.accent
                Text {
                    x: filterField.leftPadding
                    anchors.verticalCenter: parent.verticalCenter
                    visible: filterField.length === 0 && filterField.preeditText.length === 0
                    text: "Filter regions"
                    color: theme.dim
                    font: filterField.font
                }
                background: Rectangle {
                    color: theme.selection
                    opacity: 0.55
                    radius: theme.rButton
                }
                onTextEdited: {
                    regionPopup.filter = text
                    regionList.currentIndex = 0
                    regionList.positionViewAtBeginning()
                }
                onAccepted: {
                    var list = regionPopup.entries
                    if (regionList.currentIndex >= 0 && regionList.currentIndex < list.length)
                        regionPopup.choose(list[regionList.currentIndex].code)
                }
                Keys.onDownPressed: regionList.incrementCurrentIndex()
                Keys.onUpPressed: regionList.decrementCurrentIndex()
            }

            ListView {
                id: regionList
                anchors.top: filterField.bottom
                anchors.topMargin: 4
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationWraps: false
                highlightMoveDuration: 0
                highlightFollowsCurrentItem: false
                model: regionPopup.entries
                FastWheel { }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool chosen: modelData.code === explore.regionOverride
                    width: ListView.view.width
                    height: regionPopup.rowHeight
                    color: index === regionList.currentIndex ? theme.selection : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: checkIcon.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name
                        color: theme.foreground
                        font.family: "monospace"
                        font.pixelSize: theme.titleSize
                        font.weight: Font.Normal
                        elide: Text.ElideRight
                    }
                    IconLabel {
                        id: checkIcon
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        display: AbstractButton.IconOnly
                        icon.name: "check-plain-symbolic"
                        icon.color: theme.foreground
                        icon.width: 16 * theme.textScale
                        icon.height: 16 * theme.textScale
                        visible: row.chosen
                    }
                    // Hairline under "Automatic" when the full list follows.
                    Rectangle {
                        visible: row.modelData.code === "" && regionList.count > 1
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        height: 1
                        color: theme.dim
                        opacity: 0.4
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: regionList.currentIndex = row.index
                        onClicked: regionPopup.choose(row.modelData.code)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: regionList.count === 0
                    text: "No matching region"
                    color: theme.dim
                    font.pixelSize: theme.bodySmall
                }
            }

            QuietScroll {
                view: regionList
                loadedCount: regionList.count
                anchors.top: regionList.top
                anchors.bottom: regionList.bottom
                anchors.right: parent.right
                anchors.rightMargin: 2
            }
        }
    }
}
