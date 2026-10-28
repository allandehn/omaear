import QtQuick
import QtQuick.Controls

// Up-next queue. Play over the art plays/resumes (the episode stays queued; it
// leaves only when it finishes). Click the text for details, drag the handle to
// reorder live, right-click for move / remove.
Item {
    id: page
    signal dismissRequested()
    signal clearRequested()


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
    function openNavMenu() {
        if (navCount === 0) return
        menuEpisode = list.model.episodeIdAt(kbdIndex)
        menuIndex = kbdIndex
        rowMenu.popupAt(list.itemAtIndex(kbdIndex))
    }
    // Delete on a ring row removes it from the queue.
    function navDelete() {
        if (navCount > 0)
            backend.removeFromQueue(list.model.episodeIdAt(kbdIndex))
    }

    function snippet(text) {
        if (!text || text.length === 0)
            return ""
        var flat = text.replace(/\s+/g, " ").trim()
        return flat.length <= 160 ? flat : flat.slice(0, 159).replace(/\s+\S*$/, "") + "…"
    }

    property real menuEpisode: 0
    property int menuIndex: -1
    readonly property real cover: 56 * theme.textScale

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

    Rectangle {
        anchors.fill: parent
        color: theme.background
    }
    // Swallow clicks/wheel so nothing underneath reacts.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: (wheel) => wheel.accepted = true
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
        Row {
            id: actions
            // Narrow window: keep back + title; buttons return once they fit.
            visible: back.x + back.width + 18 + 120 + implicitWidth + 28 <= parent.width
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            IconButton {
                // Autoplay icon B: accent when on, foreground when off (the SVG dims its own triangle).
                icon.width: 24 * theme.textScale
                icon.source: backend.queueAutoplay ? theme.iconBase + "autoplay-b-on-symbolic.svg" : theme.iconBase + "autoplay-b-off-symbolic.svg"
                glyph: backend.queueAutoplay ? theme.accent : theme.foreground
                tip: backend.queueAutoplay ? "Autoplay: on" : "Autoplay: off"
                onClicked: backend.toggleQueueAutoplay()
            }
            IconButton {
                visible: backend.queueCount > 0
                icon.source: theme.iconBase + "queue-clear-symbolic.svg"
                glyph: theme.dim
                tip: "Clear queue"
                onClicked: page.clearRequested()
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
            Text {
                text: "Queue"
                color: theme.foreground
                font.pixelSize: theme.heading
                font.weight: Font.Normal
            }
            Text {
                text: backend.queueCount === 0 ? "Nothing queued"
                      : backend.queueCount === 1 ? "1 episode up next"
                      : backend.queueCount + " episodes up next"
                color: theme.dim
                font.pixelSize: theme.caption
                font.weight: Font.Normal
            }
        }
    }


    Column {
        anchors.centerIn: parent
        visible: backend.queueCount === 0
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "The queue is empty"
            color: theme.foreground
            font.pixelSize: theme.titleSize
            font.weight: Font.Normal
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Right-click an episode and choose Add to queue or Play next."
            color: theme.dim
            font.pixelSize: theme.caption
            font.weight: Font.Normal
        }
    }

    function rowItemAt(i) { return list.itemAtIndex(i) } // for the UI test

    ListView {
        id: list
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: !dragging
        FastWheel { }
        model: backend.queueModel
        spacing: 2

        property bool dragging: false
        moveDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: 90; easing.type: Easing.OutQuad }
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property var model
            width: list.width
            height: page.cover + 20 * theme.textScale
            readonly property bool current: row.model.episodeId === backend.playerEpisodeId
                                            && backend.playerStatus !== "stopped"
            readonly property bool playing: row.model.episodeId === backend.playerEpisodeId
                                            && backend.playerStatus === "playing"
            color: hover.containsMouse || handle.pressed ? theme.selection
                 : row.current ? Qt.rgba(theme.selection.r, theme.selection.g, theme.selection.b, 0.5)
                 : "transparent"

            Rectangle {
                anchors.fill: parent
                visible: page.kbdRing && row.index === page.kbdIndex
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
                visible: handle.pressed || row.current
            }

            Item {
                id: handleWell
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 28 * theme.textScale
                height: parent.height
                z: 2
                IconButton {
                    anchors.centerIn: parent
                    icon.name: "list-drag-handle-symbolic"
                    glyph: theme.dim
                    background: Item {}
                    // Disabled so its hover cursor never fights the drag MouseArea.
                    enabled: false
                }
                MouseArea {
                    id: handle
                    anchors.fill: parent
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    preventStealing: true
                    onPressed: list.dragging = true
                    onReleased: list.dragging = false
                    onCanceled: list.dragging = false
                    onPositionChanged: function(mouse) {
                        if (!pressed)
                            return
                        var p = mapToItem(list.contentItem, mouse.x, mouse.y)
                        var target = list.indexAt(10, p.y)
                        if (target < 0)
                            target = p.y < 0 ? 0 : list.count - 1
                        if (target !== row.index)
                            backend.moveInQueue(row.index, target)
                    }
                }
            }

            Item {
                id: art
                anchors.left: handleWell.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: page.cover
                height: page.cover
                z: 2
                readonly property real coverRadius: theme.rButton // standalone row thumbnail: min(R,4)
                layer.enabled: coverRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software // no shader effects there: stay square
                layer.smooth: true
                layer.effect: CoverClip { art: artImage; radius: art.coverRadius }
                Rectangle { anchors.fill: parent; color: Qt.tint(theme.background, row.color); z: -1 } // backing: follows the row background (hover, selection, highlight)
                Image {
                    id: artImage
                    anchors.fill: parent
                    source: row.model.cover || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: true
                    sourceSize.width: page.cover * 2
                    sourceSize.height: page.cover * 2
                }
                Rectangle {
                    anchors.fill: parent
                    color: theme.selection
                    visible: artImage.status !== Image.Ready
                }
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, playButton.hovered || playButton.down ? 0.45 : 0.28)
                }
                IconButton {
                    id: playButton
                    anchors.fill: parent
                    icon.name: row.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                    icon.width: Math.max(16 * theme.textScale, page.cover * 0.375)
                    icon.height: icon.width
                    glyph: theme.foreground
                    tip: row.playing ? "Pause" : "Play"
                    background: Item {}
                    // playEpisode toggles the current one and resumes others from their saved spot.
                    onClicked: backend.playEpisode(row.model.episodeId)
                }
            }

            IconButton {
                id: removeButton
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                z: 2
                icon.name: "window-close-symbolic"
                glyph: theme.dim
                tip: "Remove from queue"
                onClicked: backend.removeFromQueue(row.model.episodeId)
            }

            Column {
                anchors.left: art.right
                anchors.right: removeButton.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 4
                Text {
                    width: parent.width
                    text: row.model.title
                    color: theme.foreground
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
                    text: row.model.showTitle
                          + (row.model.duration > 0 ? " · " + page.clock(row.model.duration) : "")
                          + (!row.model.played && row.model.positionMs > 5000
                             ? " · In progress (" + page.clock(row.model.positionMs / 1000) + ")" : "")
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: page.snippet(row.model.description)
                    color: theme.dim
                    font.pixelSize: theme.caption
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                anchors.leftMargin: handleWell.width + 8 + art.width + 8
                z: 0
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        page.menuEpisode = row.model.episodeId
                        page.menuIndex = row.index
                        rowMenu.popup()
                    } else {
                        page.kbdIndex = row.index
                        page.kbdEpisodeId = row.model.episodeId
                        win.openEpisodePage(row.model.episodeId)
                    }
                }
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

    AppMenu {
        id: rowMenu
        AppMenuItem {
            text: "Play now"
            onChosen: backend.playFromQueue(page.menuEpisode)
        }
        AppMenuItem {
            text: "Episode details"
            onChosen: win.openEpisodePage(page.menuEpisode)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: "Move to top"
            enabled: page.menuIndex > 0
            onChosen: backend.moveInQueue(page.menuIndex, 0)
        }
        AppMenuItem {
            text: "Move up"
            enabled: page.menuIndex > 0
            onChosen: backend.moveInQueue(page.menuIndex, page.menuIndex - 1)
        }
        AppMenuItem {
            text: "Move down"
            enabled: page.menuIndex >= 0 && page.menuIndex < backend.queueCount - 1
            onChosen: backend.moveInQueue(page.menuIndex, page.menuIndex + 1)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: "Remove from queue"
            onChosen: backend.removeFromQueue(page.menuEpisode)
        }
    }
}
