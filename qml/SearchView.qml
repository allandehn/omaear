import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window

// Library search: episode titles and show notes across every subscribed show.
// Results update on each keystroke (in-memory index, see search.cpp). Title
// matches come first, then newest. Click a row for details; play over the art;
// right-click for the same episode menu as the episodes page.
Item {
    id: page
    signal dismissRequested()
    signal exploreRequested(string text)

    property real menuEpisode: 0
    property bool menuPlayed: false
    property bool menuQueued: false
    readonly property real cover: 56 * theme.textScale

    // Keyboard selection in the results (-1 = none). Kept apart from hover, so
    // the mouse never moves it. resultsFocused remembers where focus was, so
    // coming back from details restores the row and the focus.
    property int selected: -1
    property bool resultsFocused: false

    function focusSearch() {
        resultsFocused = false
        searchField.forceActiveFocus()
        searchField.selectAll()
    }

    function focusField() {
        resultsFocused = false
        searchField.forceActiveFocus()
        searchField.cursorPosition = searchField.length
    }

    function select(row) {
        if (list.count === 0)
            return
        selected = Math.max(0, Math.min(list.count - 1, row))
        list.positionViewAtIndex(selected, ListView.Contain)
    }

    function focusResults() {
        if (list.count === 0)
            return
        resultsFocused = true
        list.forceActiveFocus()
        select(selected >= 0 ? selected : 0)
    }

    function openSelected() {
        var item = list.itemAtIndex(selected)
        if (item)
            win.openEpisodePage(item.model.episodeId)
    }

    onVisibleChanged: {
        if (visible) {
            librarySearch.warm()
            if (resultsFocused && selected >= 0 && selected < list.count)
                focusResults()
            else
                focusSearch()
        } else {
            // Hidden: never keep keys (arrows, Enter) on the list or field.
            list.focus = false
            searchField.focus = false
        }
    }

    Connections {
        target: librarySearch
        function onResultsChanged() { page.selected = -1 }
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
            icon.name: "go-previous-symbolic"
            tip: "Back"
            onClicked: page.dismissRequested()
        }

        TextField {
            id: searchField
            anchors.left: back.right
            anchors.leftMargin: 18
            anchors.right: exploreButton.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: theme.foreground
            font.pixelSize: theme.body
            font.weight: Font.Normal
            topPadding: 10
            bottomPadding: 10
            leftPadding: 10
            rightPadding: 10 + clearButton.width
            verticalAlignment: TextInput.AlignVCenter
            Material.accent: theme.accent

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
                    librarySearch.setQuery("")
                    searchField.forceActiveFocus()
                }
            }
            Text {
                x: searchField.leftPadding
                anchors.verticalCenter: parent.verticalCenter
                visible: searchField.length === 0 && searchField.preeditText.length === 0
                text: "Search your episodes"
                color: theme.dim
                font: searchField.font
            }
            background: Rectangle {
                color: theme.selection
                opacity: 0.55
            }
            onTextEdited: librarySearch.setQuery(text)
            // Enter opens the top result.
            onAccepted: {
                var first = list.itemAtIndex(0)
                if (first)
                    win.openEpisodePage(first.model.episodeId)
            }
            Keys.onDownPressed: {
                page.selected = 0
                page.focusResults()
            }
            Keys.onTabPressed: page.focusResults()
        }

        IconButton {
            id: exploreButton
            anchors.right: helpButton.visible ? helpButton.left : parent.right
            anchors.rightMargin: helpButton.visible ? 2 : 16
            anchors.verticalCenter: parent.verticalCenter
            icon.source: "qrc:/icons/globe-symbolic.svg"
            tip: searchField.text.trim().length > 0 ? "Search podcasts online for \u201C" + searchField.text.trim() + "\u201D"
                                                    : "Explore podcasts online"
            onClicked: page.exploreRequested(searchField.text.trim())
        }

        IconButton {
            id: helpButton
            visible: header.width >= 380
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            icon.source: "qrc:/icons/info-symbolic.svg"
            dot: backend.updatePhase === "available"
            tip: "Info"
            onClicked: win.helpOpen = true
        }
    }

    Item {
        id: subhead
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        height: Math.max(fieldChips.implicitHeight, countText.implicitHeight, statusNote.implicitHeight) + 10
        // Which fields are searched. Bright = on, dimmed = off; the last one on stays on.
        Row {
            id: fieldChips
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            FieldChip { label: "Show"; bit: 1; keys: "Alt+1"; blurb: "show names and authors" }
            FieldChip { label: "Title"; bit: 2; keys: "Alt+2"; blurb: "episode titles" }
            FieldChip { label: "Notes"; bit: 4; keys: "Alt+3"; blurb: "show notes" }
        }
        Text {
            id: countText
            anchors.left: fieldChips.right
            anchors.leftMargin: 14
            anchors.right: statusNote.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: librarySearch.query.length > 0
            text: librarySearch.total === 0 ? ""
                  : librarySearch.total === 1 ? "1 episode"
                  : librarySearch.total > librarySearch.count
                    ? librarySearch.total + " episodes, newest " + librarySearch.count + " shown"
                    : librarySearch.total + " episodes"
            color: theme.dim
            font.pixelSize: theme.bodySmall
            font.weight: Font.Normal
            elide: Text.ElideRight
        }
        StatusNote {
            id: statusNote
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.45
            horizontalAlignment: TextEdit.AlignRight
            font.pixelSize: theme.bodySmall
        }
    }

    // Empty query / no results.
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 520)
        visible: list.count === 0
        spacing: 10
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: librarySearch.query.length === 0 ? "Search titles and show notes of every episode you subscribe to"
                                                    : "No episodes match \u201C" + librarySearch.query + "\u201D"
            color: librarySearch.query.length === 0 ? theme.dim : theme.foreground
            font.pixelSize: librarySearch.query.length === 0 ? theme.body : theme.titleSize
            font.weight: Font.Normal
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: librarySearch.query.length > 0
            text: "Search podcasts online instead"
            color: exploreLink.containsMouse ? theme.foreground : theme.dim
            font.pixelSize: theme.caption
            font.underline: true
            MouseArea {
                id: exploreLink
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.exploreRequested(librarySearch.query)
            }
        }
    }

    ListView {
        id: list
        anchors.top: subhead.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { }
        model: librarySearch
        spacing: 2
        reuseItems: true
        keyNavigationEnabled: false
        readonly property int pageRows: Math.max(1, Math.floor(height / (page.cover + 22 * theme.textScale + spacing)) - 1)
        Keys.onPressed: function(event) {
            var k = event.key
            if (k === Qt.Key_Down) {
                page.select(page.selected + 1)
            } else if (k === Qt.Key_Up) {
                if (page.selected <= 0)
                    page.focusField()
                else
                    page.select(page.selected - 1)
            } else if (k === Qt.Key_PageDown) {
                page.select(page.selected + pageRows)
            } else if (k === Qt.Key_PageUp) {
                page.select(page.selected - pageRows)
            } else if (k === Qt.Key_Home) {
                page.select(0)
            } else if (k === Qt.Key_End) {
                page.select(list.count - 1)
            } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
                page.focusField()
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                page.openSelected()
            } else if (event.text.length > 0 && event.text !== " "
                       && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                       && event.text.charCodeAt(0) >= 32) {
                // Typing goes back to the field and continues the query.
                page.focusField()
                searchField.insert(searchField.length, event.text)
                librarySearch.setQuery(searchField.text)
            } else {
                return
            }
            event.accepted = true
        }
        // New query: back to the top.
        Connections {
            target: librarySearch
            function onResultsChanged() { list.positionViewAtBeginning() }
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property var model
            width: list.width
            height: page.cover + 22 * theme.textScale
            readonly property bool current: row.model.episodeId === backend.playerEpisodeId
                                            && backend.playerStatus !== "stopped"
            readonly property bool playing: row.model.episodeId === backend.playerEpisodeId
                                            && backend.playerStatus === "playing"
            readonly property bool picked: row.index === page.selected && page.resultsFocused
            color: hover.containsMouse || row.picked ? theme.selection
                 : row.current ? Qt.rgba(theme.selection.r, theme.selection.g, theme.selection.b, 0.5)
                 : "transparent"

            Rectangle {
                width: 3
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: row.picked ? theme.foreground : theme.accent
                visible: row.current || row.picked
            }

            Item {
                id: art
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: page.cover
                height: page.cover
                z: 2
                Image {
                    id: artImage
                    anchors.fill: parent
                    source: row.model.cover || ""
                    fillMode: Image.PreserveAspectCrop
                    // Asynchronous here: results change on every keystroke, and a
                    // first-time cover decode must never hold up typing. Memory-cached
                    // covers still arrive within a frame.
                    asynchronous: true
                    cache: true
                    sourceSize.width: coverCache.rowSide / Screen.devicePixelRatio
                    sourceSize.height: coverCache.rowSide / Screen.devicePixelRatio
                    smooth: true
                    // Played episodes step back, like the rest of the app.
                    opacity: row.model.played ? 0.45 : 1
                }
                Rectangle {
                    anchors.fill: parent
                    color: theme.selection
                    visible: artImage.status !== Image.Ready
                }
                Rectangle {
                    anchors.fill: parent
                    visible: playButton.hovered || row.playing
                    color: Qt.rgba(0, 0, 0, playButton.down ? 0.5 : 0.38)
                }
                IconButton {
                    id: playButton
                    anchors.fill: parent
                    icon.name: row.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                    icon.width: Math.max(16 * theme.textScale, page.cover * 0.375)
                    icon.height: icon.width
                    glyph: theme.foreground
                    // Only on hover (or while this one plays); still clickable when hidden.
                    opacity: hovered || row.playing ? 1 : 0
                    tip: row.playing ? "Pause" : "Play"
                    background: Item {}
                    onClicked: backend.playEpisode(row.model.episodeId)
                }
            }

            Column {
                anchors.left: art.right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 24
                spacing: 3
                Text {
                    width: parent.width
                    text: row.model.titleHtml
                    textFormat: Text.StyledText
                    color: row.model.played ? theme.dim : theme.foreground
                    font.pixelSize: theme.titleSize
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Text {
                    width: parent.width
                    color: theme.dim
                    font.pixelSize: theme.caption
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: row.model.showHtml
                          + (row.model.published > 0 ? " · " + backend.formatDay(row.model.published) : "")
                          + (row.model.duration > 0 ? " · " + page.clock(row.model.duration) : "")
                          + (row.model.played ? " · Played"
                             : row.model.positionMs > 5000 ? " · In progress" : "")
                }
                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: row.model.snippetHtml
                    textFormat: Text.StyledText
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
                anchors.leftMargin: art.x + art.width
                z: 0
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        page.menuEpisode = row.model.episodeId
                        page.menuPlayed = row.model.played
                        page.menuQueued = backend.isQueued(row.model.episodeId)
                        rowMenu.popup()
                    } else {
                        // Coming back lands on this row, keyboard-ready.
                        page.selected = row.index
                        page.resultsFocused = true
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
            text: "Mark as played"
            enabled: !page.menuPlayed
            onTriggered: backend.markPlayed(page.menuEpisode, true)
        }
        AppMenuItem {
            text: "Mark as unplayed"
            enabled: page.menuPlayed
            onTriggered: backend.markPlayed(page.menuEpisode, false)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: "Play next"
            onTriggered: backend.playNext(page.menuEpisode)
        }
        AppMenuItem {
            text: page.menuQueued ? "Remove from queue" : "Add to queue"
            onTriggered: page.menuQueued ? backend.removeFromQueue(page.menuEpisode)
                                         : backend.addToQueue(page.menuEpisode)
        }
        AppMenuSeparator {}
        AppMenuItem {
            text: "Episode details"
            onTriggered: win.openEpisodePage(page.menuEpisode)
        }
        AppMenuItem {
            text: "Go to show"
            onTriggered: win.openShowPage(backend.episodeShowId(page.menuEpisode))
        }
    }

    function toggleField(bit) {
        if (!librarySearch.toggleField(bit))
            refusedChip = bit
    }
    // Set when the last enabled chip was clicked; that chip nods briefly.
    property int refusedChip: 0
    Timer {
        interval: 450
        running: page.refusedChip !== 0
        onTriggered: page.refusedChip = 0
    }

    Shortcut { sequence: "Alt+1"; enabled: page.visible; onActivated: page.toggleField(1) }
    Shortcut { sequence: "Alt+2"; enabled: page.visible; onActivated: page.toggleField(2) }
    Shortcut { sequence: "Alt+3"; enabled: page.visible; onActivated: page.toggleField(4) }

    component FieldChip: Rectangle {
        id: chip
        property string label
        property int bit
        property string keys
        property string blurb
        readonly property bool on: (librarySearch.fields & bit) !== 0
        readonly property bool last: on && (librarySearch.fields & ~bit) === 0
        implicitWidth: chipText.implicitWidth + 18
        implicitHeight: chipText.implicitHeight + 6
        radius: height / 2
        color: on ? Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b,
                            chipMouse.containsMouse ? 0.16 : 0.10)
                  : chipMouse.containsMouse ? Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.06)
                  : "transparent"
        border.width: 1
        border.color: page.refusedChip === bit ? theme.foreground
                    : on ? Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.35)
                    : Qt.rgba(theme.muted.r, theme.muted.g, theme.muted.b, 0.6)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? theme.foreground : theme.muted
            font.pixelSize: theme.caption
            font.weight: Font.Normal
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.toggleField(chip.bit)
        }
        AppTip {
            visible: chipMouse.containsMouse
            text: (chip.last ? "Searching " + chip.blurb + " only. Turn on another field first"
                             : (chip.on ? "Searching " : "Not searching ") + chip.blurb + ". Click to turn "
                               + (chip.on ? "off" : "on")) + " (" + chip.keys + ")"
        }
    }
}
