import QtQuick

Item {
    id: page
    signal dismissRequested()

    // Very short pane: horizontal art + titles, keep transport/scrubber, hide blurb.
    // Full stacked cover layout when page.height is at or above this.
    readonly property real compactThreshold: 320 * theme.textScale
    readonly property bool compact: height < compactThreshold

    // "1×", "1.25×", "1.5×": trailing zeros trimmed.
    function rateLabel(value) {
        return Number((Math.round(value * 100) / 100).toFixed(2)).toString() + "×"
    }

    // Ctrl+wheel art size: fraction of the largest square that fits (0.2 .. 1.0).
    property real zoomPending: 0
    function applyArtZoom(delta) {
        zoomPending += delta
        var steps = 0
        while (zoomPending >= 120) { zoomPending -= 120; steps += 1 }
        while (zoomPending <= -120) { zoomPending += 120; steps -= 1 }
        if (steps !== 0)
            backend.setNowPlayingArtScale(Math.round((backend.nowPlayingArtScale + steps * 0.1) * 10) / 10)
    }

    // Notes links: web links open in the browser; timestamps seek here.
    function openNoteLink(link) {
        if (link.indexOf("seek:") === 0) {
            var seconds = Number(link.slice(5))
            if (!(seconds >= 0))
                return
            backend.seekTo(seconds)
            if (backend.playerStatus !== "playing")
                backend.togglePlayback()
            return
        }
        Qt.openUrlExternally(link)
    }

    function openArtMenu() {
        artMenu.openFor(backend.playerEpisodeId, backend.playerShowId)
    }
    // Menu key: the artwork menu, beside the cover.
    function openNavMenu() {
        artMenu.openFor(backend.playerEpisodeId, backend.playerShowId, page.compact ? compactArt : coverFrame)
    }

    // Keyboard navigation areas (driven by Main.qml).
    function shown(list) {
        return list.filter(function(i) { return i.visible && i.enabled && i.kbdFocus !== undefined })
    }
    function navTop() { return shown([back, helpButton]) }
    function navTransport() { var list = []
        for (var i = 0; i < transport.children.length; ++i) list.push(transport.children[i])
        return shown(list) }
    function navControls() { var list = []
        for (var i = 0; i < controls.children.length; ++i) list.push(controls.children[i])
        return shown(list) }
    function navSeek() { return shown([scrubber]) }

    function nudge(seconds) {
        var next = backend.playerPosition + seconds
        if (next < 0)
            next = 0
        if (backend.playerDuration > 0 && next > backend.playerDuration)
            next = backend.playerDuration
        backend.seekTo(next)
    }

    Rectangle {
        anchors.fill: parent
        color: theme.background
    }

    IconButton {
        id: back
        anchors.left: parent.left
        anchors.leftMargin: page.compact ? 8 : 16
        anchors.top: parent.top
        anchors.topMargin: page.compact ? 8 : 16
        z: 2
        icon.source: theme.iconBase + "back-symbolic.svg"
        tip: "Back"
        onClicked: page.dismissRequested()
    }
    IconButton {
        id: helpButton
        anchors.right: parent.right
        anchors.rightMargin: page.compact ? 8 : 16
        anchors.top: parent.top
        anchors.topMargin: page.compact ? 8 : 16
        z: 2
        icon.source: theme.iconBase + "info-symbolic.svg"
        dot: backend.updatePhase === "available"
        tip: "Info"
        onClicked: win.helpOpen = true
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        // Include top/bottom pads so scrolling reaches scrubber fully above PlayerBar.
        contentHeight: Math.max(height, body.topPad + body.implicitHeight + body.bottomPad)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { }

        Column {
            id: body
            readonly property real sidePad: (page.compact ? 16 : 40) * theme.textScale
            readonly property real topPad: (page.compact ? 48 : 56) * theme.textScale
            // Breathing room above the always-visible PlayerBar (outside this page).
            readonly property real bottomPad: (page.compact ? 12 : 28) * theme.textScale
            width: Math.max(120 * theme.textScale, parent.width - sidePad * 2)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: topPad
            spacing: (page.compact ? 10 : 20) * theme.textScale

            // Height claimed by title, transport, scrubber and gaps. The episode
            // description is left out on purpose: it scrolls below, so a long
            // blurb no longer squeezes the cover down to a thumbnail.
            // PlayerBar lives in Main below this page, so page.height already excludes it.
            // Everything below the cover except the notes.
            readonly property real baseChrome: titles.implicitHeight
                                               + transportBlock.implicitHeight
                                               + scrubberCol.implicitHeight
            // Room the notes may take on a short window, after a small cover:
            // they shrink (and scroll) or step aside rather than run under the bar.
            readonly property real notesRoom: page.height - topPad - bottomPad - baseChrome
                                              - spacing * 4 - 120 * theme.textScale
            readonly property real chromeBelow: {
                var gaps = 3
                var h = baseChrome
                // The notes box is capped (it scrolls inside), so it can claim its
                // room without squeezing the cover to a thumbnail; nothing sits
                // hidden below the fold above the player bar any more.
                if (synopsisBox.visible) {
                    h += synopsisBox.height
                    gaps += 1
                }
                return h + spacing * gaps + bottomPad
            }
            // Square cover: the largest square that fits beside the window edges
            // (24px margin) and above title/transport/scrubber, times the
            // Ctrl+wheel fraction. Re-fits live on resize; never below a small floor.
            readonly property real edgeMargin: 24 * theme.textScale
            readonly property real coverFit: Math.min(page.width - edgeMargin * 2,
                                                      page.height - topPad - chromeBelow)
            readonly property real coverSide: Math.max(56 * theme.textScale,
                                                       Math.floor(coverFit * backend.nowPlayingArtScale))

            // Compact: small art beside title/show. Full: large centered cover above titles.
            Item {
                width: parent.width
                height: coverFrame.height
                visible: !page.compact

                Rectangle {
                    id: coverFrame
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: body.coverSide
                    height: width
                    radius: theme.rCard
                    color: backend.playerArt !== "" ? theme.background : theme.selection // backing: page surface; placeholder keeps its look
                    clip: true
                    readonly property real coverRadius: theme.rCard
                    layer.enabled: coverRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software // no shader effects there: stay square
                    layer.smooth: true
                    layer.effect: CoverClip { art: fullImage; radius: coverFrame.coverRadius }

                    // backend.playerArt already prefers episode art over the show cover.
                    Image {
                        id: fullImage
                        anchors.fill: parent
                        source: backend.playerArt
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Decode once at the 100% size (rounded up to 512px buckets) so
                        // Ctrl+wheel only rescales the texture instead of re-decoding it
                        // asynchronously at every step, which blanked the cover (flicker).
                        readonly property int decodeSide: Math.max(512, Math.ceil(body.coverFit * 2 / 512) * 512)
                        sourceSize.width: decodeSide
                        sourceSize.height: decodeSide
                        smooth: true
                        mipmap: true
                        visible: backend.playerArt !== ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: backend.playerArt === ""
                        text: "No art"
                        color: theme.dim
                        font.pixelSize: theme.body
                        font.weight: Font.Normal
                        font.family: "monospace"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton)
                                page.openArtMenu()
                            else
                                backend.togglePlayback()
                        }
                    }
                }
            }

            Row {
                id: compactHeader
                width: parent.width
                spacing: 12 * theme.textScale
                visible: page.compact

                Rectangle {
                    id: compactArt
                    width: 56 * theme.textScale
                    height: width
                    radius: theme.rCard
                    color: backend.playerArt !== "" ? theme.background : theme.selection // backing: page surface; placeholder keeps its look
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real coverRadius: theme.rCard
                    layer.enabled: coverRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software // no shader effects there: stay square
                    layer.smooth: true
                    layer.effect: CoverClip { art: compactImage; radius: compactArt.coverRadius }

                    Image {
                        id: compactImage
                        anchors.fill: parent
                        source: backend.playerArt
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: Math.max(112, compactArt.width * 2)
                        sourceSize.height: Math.max(112, compactArt.height * 2)
                        visible: backend.playerArt !== ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: backend.playerArt === ""
                        text: "—"
                        color: theme.dim
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                        font.family: "monospace"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton)
                                page.openArtMenu()
                            else
                                backend.togglePlayback()
                        }
                    }
                }

                Column {
                    width: parent.width - compactArt.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    SelectableText {
                        width: parent.width
                        text: backend.playerTitle
                        color: theme.foreground
                        font.pixelSize: theme.titleSize
                        font.family: "monospace"
                        wrapMode: TextEdit.Wrap
                    }
                    SelectableText {
                        width: parent.width
                        text: backend.playerShowTitle
                        color: theme.dim
                        font.pixelSize: theme.caption
                        font.family: "monospace"
                        wrapMode: TextEdit.NoWrap
                        clip: true
                    }
                }
            }

            Column {
                id: titles
                width: Math.min(parent.width, 560 * theme.textScale)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                visible: !page.compact

                SelectableText {
                    width: parent.width
                    horizontalAlignment: TextEdit.AlignHCenter
                    text: backend.playerTitle
                    color: theme.foreground
                    font.pixelSize: theme.heading
                    font.family: "monospace"
                    wrapMode: TextEdit.Wrap
                }
                SelectableText {
                    width: parent.width
                    horizontalAlignment: TextEdit.AlignHCenter
                    text: backend.playerShowTitle
                    color: theme.dim
                    font.pixelSize: theme.body
                    font.family: "monospace"
                    wrapMode: TextEdit.NoWrap
                    clip: true
                }
            }

            // Transport and the controls row sit close together (8 px) as one group;
            // the page spacing separates the group from the titles and progress bar.
            Column {
                id: transportBlock
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: (page.compact ? 4 : 8) * theme.textScale

                // Row 1: queue previous, -15, play/pause, +30, queue next (centred).
                Row {
                    id: transport
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: page.compact ? 6 : 10
                    // Dimmed and skipped by the keyboard when there is nothing to go to.
                    IconButton {
                        // Size tier (queue): shared centre line.
                        anchors.verticalCenter: parent.verticalCenter
                        icon.width: 17 * theme.textScale
                        implicitWidth: 34 * theme.textScale
                        implicitHeight: 34 * theme.textScale
                        icon.name: "media-skip-backward-symbolic"
                        enabled: playerBar.prevId !== 0
                        tip: playerBar.prevTip
                        onClicked: backend.skipToPreviousQueued()
                    }
                    IconButton {
                        // Size tier (seek): shared centre line.
                        anchors.verticalCenter: parent.verticalCenter
                        icon.width: 26 * theme.textScale
                        implicitWidth: 48 * theme.textScale
                        implicitHeight: 48 * theme.textScale
                        icon.name: "media-seek-backward-symbolic"
                        tip: "Back 15 seconds"
                        onClicked: page.nudge(-15)
                    }
                    IconButton {
                        // Size tier (play): shared centre line.
                        anchors.verticalCenter: parent.verticalCenter
                        icon.width: 34 * theme.textScale
                        implicitWidth: 56 * theme.textScale
                        implicitHeight: 56 * theme.textScale
                        icon.name: backend.playerStatus === "playing"
                                   ? "media-playback-pause-symbolic"
                                   : "media-playback-start-symbolic"
                        tip: backend.playerStatus === "playing" ? "Pause" : "Play"
                        onClicked: backend.togglePlayback()
                    }
                    IconButton {
                        // Size tier (seek): shared centre line.
                        anchors.verticalCenter: parent.verticalCenter
                        icon.width: 26 * theme.textScale
                        implicitWidth: 48 * theme.textScale
                        implicitHeight: 48 * theme.textScale
                        icon.name: "media-seek-forward-symbolic"
                        tip: "Forward 30 seconds"
                        onClicked: page.nudge(30)
                    }
                    IconButton {
                        // Size tier (queue): shared centre line.
                        anchors.verticalCenter: parent.verticalCenter
                        icon.width: 17 * theme.textScale
                        implicitWidth: 34 * theme.textScale
                        implicitHeight: 34 * theme.textScale
                        icon.name: "media-skip-forward-symbolic"
                        enabled: playerBar.upNextId !== 0
                        tip: playerBar.upNextTip
                        onClicked: backend.skipToNextQueued()
                    }
                }

                // Row 2: volume, speed, autoplay, mono, in the player bar's order; the same
                // hover popups and scroll steps as there.
                Row {
                    id: controls
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: page.compact ? 6 : 10
                    IconButton {
                        id: volumeButton
                        icon.name: playerBar.volumeIcon(backend.playerVolume)
                        onHoveredChanged: {
                            playerBar.volumeExtHovered = hovered
                            if (hovered)
                                playerBar.openVolumePopupAt(volumeButton)
                            else
                                playerBar.considerCloseVolume()
                        }
                        onClicked: backend.toggleMute()
                        WheelSteps { onStep: function(n) { backend.stepVolume(n); playerBar.openVolumePopupAt(volumeButton) } }
                    }
                    IconButton {
                        id: rateChip
                        caption: page.rateLabel(backend.playerRate)
                        font.features: { "tnum": 1 }
                        // Fixed for the widest value so the row never shifts.
                        TextMetrics { id: rateWidest; font: rateChip.font; text: "1.75×" }
                        implicitWidth: Math.ceil(rateWidest.advanceWidth) + leftPadding + rightPadding
                        onHoveredChanged: {
                            playerBar.chipHovered = hovered
                            if (hovered)
                                playerBar.openSpeedPopupAt(rateChip)
                            else
                                playerBar.considerCloseSpeed()
                        }
                        onClicked: backend.cycleRate()
                        WheelSteps { onStep: function(n) { backend.stepRate(-n); playerBar.openSpeedPopupAt(rateChip) } }
                    }
                    // Autoplay queue (same setting as the player bar and Queue page).
                    IconButton {
                        id: autoplayToggle
                        icon.source: backend.queueAutoplay ? theme.iconBase + "autoplay-b-on-symbolic.svg" : theme.iconBase + "autoplay-b-off-symbolic.svg"
                        glyph: backend.queueAutoplay ? theme.accent : theme.foreground
                        tip: backend.queueAutoplay ? "Autoplay: on" : "Autoplay: off"
                        onClicked: backend.toggleQueueAutoplay()
                    }
                    // Mono downmix: bright when on, dimmed when off (shared with the player bar).
                    IconButton {
                        id: monoToggle
                        icon.source: theme.iconBase + "mono-symbolic.svg"
                        glyph: backend.playerMono ? theme.foreground : theme.muted
                        tip: backend.playerMono ? "Mono: left and right mixed" : "Stereo: left and right separate"
                        onClicked: backend.toggleMono()
                    }
                }
            }

            Column {
                id: scrubberCol
                width: Math.min(parent.width, 560 * theme.textScale)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: page.compact ? 4 : 8

                Row {
                    width: parent.width
                    spacing: page.compact ? 6 : 10
                    Text {
                        id: elapsedLabel
                        text: scrubber.elapsedText
                        color: theme.dim
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                        font.family: "monospace"
                        // As wide as the duration (5:21:57 on long episodes) so the bar never overlaps it.
                        width: Math.max(remainLabel.implicitWidth, 40 * theme.textScale)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Scrubber {
                        id: scrubber
                        width: parent.width
                               - elapsedLabel.width
                               - remainLabel.implicitWidth
                               - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id: remainLabel
                        text: scrubber.durationText
                        color: theme.dim
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                        font.family: "monospace"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Notes: up to about five lines on show; longer notes scroll in place.
            Flickable {
                id: synopsisBox
                width: Math.min(parent.width, 560 * theme.textScale)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !page.compact && backend.playerDescription.length > 0
                         && body.notesRoom >= theme.bodySmall * 1.4 * 2
                height: Math.max(0, Math.min(synopsis.implicitHeight, theme.bodySmall * 1.4 * 5, body.notesRoom))
                contentWidth: width
                contentHeight: synopsis.implicitHeight
                interactive: contentHeight > height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                FastWheel { }
                SelectableText {
                    id: synopsis
                    width: synopsisBox.width
                    horizontalAlignment: TextEdit.AlignHCenter
                    // Links and timestamps as on episode details (same linkify).
                    text: episodePage.linkify(backend.playerDescription, theme.blue)
                    textFormat: TextEdit.RichText
                    onLinkActivated: function (link) { page.openNoteLink(link) }
                    onLinkCopyRequested: function (link) { episodePage.copyWebLink(link) }
                    color: theme.dim
                    font.pixelSize: theme.bodySmall
                    font.family: "monospace"
                    wrapMode: TextEdit.Wrap
                    opacity: 0.9
                }
            }
        }
    }


    ArtMenu { id: artMenu }

    QuietScroll {
        view: scroller
        anchors.top: scroller.top
        anchors.bottom: scroller.bottom
        anchors.right: parent.right
        anchors.rightMargin: 2
    }
}
