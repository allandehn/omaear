import QtQuick
import QtQuick.Controls

Item {
    id: page
    signal queueRequested()

    // Which show this page is holding. Main keeps one page per visited show.
    property double showId: 0
    property var episodeModel: null
    // Same five list-cover steps as ShelfView. 0 matches Shelf's original 44px.
    // New libraries start at index 2 (Library::episodeListSize).
    readonly property var listCoverSteps: [44, 64, 88, 120, 160]
    readonly property int listCoverBase: listCoverSteps[Math.max(0, Math.min(backend.episodeListSize, listCoverSteps.length - 1))]
    readonly property real listCover: listCoverBase * theme.textScale
    readonly property real listRowHeight: listCover + 20 * theme.textScale
    readonly property int descriptionLimit: 140

    property real zoomPending: 0

    // ---- Keyboard navigation (driven by Main.qml) ---------------------------
    function navItems() {
        var list = [back]
        if (actions.visible) {
            for (var i = 0; i < actions.children.length; ++i) {
                var kid = actions.children[i]
                if (kid.visible && kid.enabled && kid.kbdFocus !== undefined)
                    list.push(kid)
            }
        }
        return list
    }
    // Episode list as a one-column grid; the ring follows the episode id.
    property bool kbdRing: false
    property int kbdIndex: 0
    property double kbdEpisodeId: 0
    readonly property int navCount: list.count
    readonly property int navColumns: 1
    function syncNavIndex() {
        var row = kbdEpisodeId ? list.model.rowOfEpisode(kbdEpisodeId) : -1
        if (row >= 0)
            kbdIndex = row
        kbdIndex = Math.max(0, Math.min(kbdIndex, navCount - 1))
        kbdEpisodeId = list.model.episodeIdAt(kbdIndex)
    }
    function setNavIndex(index) {
        kbdIndex = Math.max(0, Math.min(index, navCount - 1))
        kbdEpisodeId = list.model.episodeIdAt(kbdIndex)
        list.positionViewAtIndex(kbdIndex, ListView.Contain)
    }
    function openNavItem() {
        if (navCount > 0)
            win.openEpisodePage(list.model.episodeIdAt(kbdIndex))
    }

    function zoomIn() {
        backend.setEpisodeListSize(backend.episodeListSize + 1)
    }

    function zoomOut() {
        backend.setEpisodeListSize(backend.episodeListSize - 1)
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

    function clock(seconds) {
        if (!seconds || seconds < 1)
            return ""
        var total = Math.floor(seconds)
        var hours = Math.floor(total / 3600)
        var minutes = Math.floor((total % 3600) / 60)
        var remain = total % 60
        function pad(value) { return value < 10 ? "0" + value : "" + value }
        if (hours > 0)
            return hours + ":" + pad(minutes) + ":" + pad(remain)
        return minutes + ":" + pad(remain)
    }

    function day(unix) {
        return backend.formatDay(unix)
    }

    function snippet(text) {
        if (!text || text.length === 0)
            return ""
        var flat = text.replace(/\s+/g, " ").trim()
        if (flat.length <= descriptionLimit)
            return flat
        return flat.slice(0, descriptionLimit - 1).replace(/\s+\S*$/, "") + "…"
    }

    // UI self-test hooks (OMAEAR_UI_TEST).
    readonly property Item backItem: back
    function rowItemAt(i) { return list.itemAtIndex(i) }
    readonly property bool episodeMenuOpen: episodeMenu.opened

    function openMarkMenu(episodeId, played, anchor) {
        episodeMenu.openFor(episodeId, anchor)
    }
    function openNavMenu() {
        var row = list.itemAtIndex(kbdIndex)
        if (navCount > 0 && row)
            openMarkMenu(list.model.episodeIdAt(kbdIndex), row.navPlayed, row)
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

        IconButton {
            id: back
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            icon.source: theme.iconBase + "back-symbolic.svg"
            tip: "Back"
            onClicked: win.back()
        }
        Row {
            id: actions
            // Narrow window: keep back + title; buttons return once they fit.
            visible: back.x + back.width + 18 + 120 + implicitWidth + 28 <= parent.width
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            IconButton {
                icon.name: backend.episodeShowAll ? "view-reveal-symbolic" : "view-conceal-symbolic"
                tip: backend.episodeShowAll ? "Show unplayed only" : "Show all"
                onClicked: backend.setEpisodeShowAll(!backend.episodeShowAll)
            }
            IconButton {
                icon.name: "view-refresh-symbolic"
                tip: "Refresh  ·  Ctrl+click reloads artwork"
                property bool reloadArtwork: false
                onPressedChanged: {
                    if (pressed)
                        reloadArtwork = backend.controlHeld()
                }
                onClicked: backend.refreshOpenShow(reloadArtwork)
            }
            IconButton {
                icon.source: theme.iconBase + "queue-symbolic.svg"
                tip: backend.queueCount > 0 ? "Queue (" + backend.queueCount + ")" : "Queue"
                onClicked: page.queueRequested()
            }
            IconButton {
                icon.source: theme.iconBase + "info-symbolic.svg"
                dot: backend.updatePhase === "available"
                tip: "Info"
                onClicked: win.helpOpen = true
            }
        }
        Column {
            anchors.left: back.right
            anchors.right: actions.visible ? actions.left : parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            SelectableText {
                width: parent.width
                text: backend.openShowTitle
                color: theme.foreground
                font.pixelSize: theme.heading
                wrapMode: TextEdit.NoWrap
                clip: true
            }
            SelectableText {
                text: backend.openShowUnheard === 0
                      ? "Caught up"
                      : backend.openShowUnheard + " unplayed"
                color: theme.dim
                font.pixelSize: theme.caption
                wrapMode: TextEdit.NoWrap
            }
        }
    }


    ListView {
        id: list
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { }
        model: page.episodeModel !== null ? page.episodeModel : backend.episodes
        spacing: 2
        // Keep a screenful of delegates so scrolling back up does not rebuild art.
        cacheBuffer: height

        delegate: Rectangle {
            id: row
            readonly property bool navPlayed: model.played
            width: list.width
            height: Math.max(page.listRowHeight, contentColumn.implicitHeight + 20 * theme.textScale)
            color: hover.containsMouse ? theme.selection : "transparent"

            Rectangle {
                anchors.fill: parent
                visible: page.kbdRing && index === page.kbdIndex
                radius: theme.rButton
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.7)
                z: 5
            }

            Rectangle {
                width: 3
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: theme.accent
                visible: model.episodeId === backend.playerEpisodeId && backend.playerStatus !== "stopped"
            }

            Item {
                id: playWell
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                width: page.listCover
                height: page.listCover
                z: 2

                // Episode art when the feed has it; otherwise the show cover.
                readonly property string art: model.cover && model.cover !== ""
                                             ? model.cover
                                             : backend.openShowCover
                readonly property real coverRadius: theme.rButton // standalone row thumbnail: min(R,4)
                layer.enabled: coverRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software // no shader effects there: stay square
                layer.smooth: true
                layer.effect: CoverClip { art: wellImage; radius: playWell.coverRadius }
                Rectangle { anchors.fill: parent; color: theme.background; z: -1 } // backing: the surface the cover sits on
                Image {
                    id: wellImage
                    anchors.fill: parent
                    source: playWell.art
                    fillMode: Image.PreserveAspectCrop
                    // Synchronous so a cache hit paints with the delegate.
                    // asynchronous:true completes one row at a time and reads as a
                    // top-to-bottom cascade even when the file is already on disk.
                    asynchronous: false
                    cache: true
                    // Fixed decode size so resizing never reloads.
                    smooth: true
                    mipmap: true
                    sourceSize.width: coverCache.rowSide / Screen.devicePixelRatio
                    sourceSize.height: coverCache.rowSide / Screen.devicePixelRatio
                    visible: playWell.art !== ""
                    z: 0
                }
                Rectangle {
                    anchors.fill: parent
                    color: theme.selection
                    visible: playWell.art === ""
                    z: 0
                }
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, playButton.hovered || playButton.down ? 0.45 : 0.28)
                    z: 1
                }
                IconButton {
                    id: playButton
                    anchors.fill: parent
                    z: 2
                    icon.name: model.episodeId === backend.playerEpisodeId
                               && backend.playerStatus === "playing"
                               ? "media-playback-pause-symbolic"
                               : "media-playback-start-symbolic"
                    // Scale the glyph with the cover so art stays readable under it.
                    icon.width: Math.max(16 * theme.textScale, page.listCover * 0.375)
                    icon.height: icon.width
                    glyph: theme.foreground
                    // Transparent chrome so episode art shows through under the glyph.
                    background: Item {}
                    onClicked: backend.playEpisode(model.episodeId)
                }
                // Right-click on the art: the same episode menu as the row.
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: page.openMarkMenu(model.episodeId, model.played)
                }
                QueueBadge {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 3
                    z: 3
                    // queueCount ties the lookup to queueChanged (add/remove/reorder).
                    slot: backend.queueCount >= 0 ? backend.queueSlot(model.episodeId) : 0
                }
            }

            Column {
                id: contentColumn
                anchors.left: playWell.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 20
                spacing: 4

                Text {
                    width: parent.width
                    text: model.title
                    color: model.played ? theme.dim : theme.foreground
                    font.pixelSize: theme.titleSize
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    color: theme.dim
                    font.pixelSize: theme.caption
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    text: page.day(model.published)
                          + (model.duration > 0 ? " · " + page.clock(model.duration) : "")
                          + (model.played ? " · Played" : "")
                          + (!model.played && model.positionMs > 5000 ? " · In progress (" + page.clock(model.positionMs / 1000) + ")" : "")
                }
                Text {
                    width: parent.width
                    visible: model.description && model.description.length > 0
                    text: page.snippet(model.description)
                    color: model.played ? theme.dim : theme.foreground
                    font.pixelSize: theme.caption
                    font.weight: Font.Normal
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Rectangle {
                    visible: !model.played && model.duration > 0 && model.positionMs > 0
                    width: parent.width
                    height: 3
                    radius: theme.rIcon
                    color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.15)
                    Rectangle {
                        width: parent.width * Math.min(1, model.positionMs / (model.duration * 1000))
                        height: parent.height
                        color: theme.accent
                    }
                }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                anchors.leftMargin: playWell.width + 18
                z: 0
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton)
                        page.openMarkMenu(model.episodeId, model.played)
                    else {
                        page.kbdIndex = index
                        page.kbdEpisodeId = model.episodeId
                        win.openEpisodePage(model.episodeId)
                    }
                }
                onWheel: (wheel) => page.takeWheel(wheel)
            }
        }
    }

    QuietScroll {
        view: list
        loadedCount: list.count
        anchors.top: list.top
        anchors.bottom: list.bottom
        anchors.right: parent.right
        anchors.rightMargin: 2
    }


    EpisodeMenu { id: episodeMenu }
}
