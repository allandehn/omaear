import QtQuick
import QtQuick.Controls.impl

Item {
    id: page

    // Episode art when present; otherwise the parent show's cover.
    readonly property string art: backend.openEpisodeCover !== ""
                                  ? backend.openEpisodeCover
                                  : backend.openShowCover


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
    // Menu key: the art menu (same as Now Playing's), beside the art.
    function openNavMenu() {
        artMenu.openFor(backend.openEpisodeId, backend.openShowId, artFrame.visible ? artFrame : back)
    }
    // PgUp / PgDn scroll the show notes.
    function scrollPage(dir) {
        var max = Math.max(0, scroller.contentHeight - scroller.height)
        scroller.contentY = Math.max(0, Math.min(max, scroller.contentY + dir * scroller.height * 0.85))
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

    function metaLine() {
        var parts = []
        var published = page.day(backend.openEpisodePublished)
        if (published.length > 0)
            parts.push(published)
        if (backend.openEpisodeDuration > 0)
            parts.push(page.clock(backend.openEpisodeDuration))
        if (backend.openEpisodePlayed)
            parts.push("Played")
        else if (backend.openEpisodePositionMs > 5000)
            parts.push("In progress (" + page.clock(backend.openEpisodePositionMs / 1000) + ")")
        return parts.join(" · ")
    }

    function escapeHtml(value) {
        return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function escapeAttr(value) {
        return page.escapeHtml(value).replace(/"/g, "&quot;")
    }

    function countChar(value, ch) {
        var n = 0
        for (var i = 0; i < value.length; ++i) {
            if (value.charAt(i) === ch)
                n++
        }
        return n
    }

    function peelUrl(url) {
        var trail = ""
        while (url.length > 0) {
            var ch = url.charAt(url.length - 1)
            if (".,;:!?\"'".indexOf(ch) !== -1) {
                trail = ch + trail
                url = url.slice(0, -1)
                continue
            }
            if ((ch === ")" && page.countChar(url, "(") < page.countChar(url, ")"))
                    || (ch === "]" && page.countChar(url, "[") < page.countChar(url, "]"))) {
                trail = ch + trail
                url = url.slice(0, -1)
                continue
            }
            break
        }
        return { url: url, trail: trail }
    }

    function stampSeconds(stamp) {
        var parts = stamp.split(":")
        if (parts.length === 3)
            return Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Number(parts[2])
        if (parts.length === 2)
            return Number(parts[0]) * 60 + Number(parts[1])
        return -1
    }

    // #RRGGBB. Qt RichText ignores Text.linkColor (that property is StyledText
    // only) and paints anchors palette(link) blue unless the <a> carries a color.
    function colorHex(color) {
        function byte(channel) {
            var n = Math.round(channel * 255)
            if (n < 0)
                n = 0
            else if (n > 255)
                n = 255
            var hex = n.toString(16)
            return hex.length < 2 ? "0" + hex : hex
        }
        return "#" + byte(color.r) + byte(color.g) + byte(color.b)
    }

    function anchorHtml(href, label, color) {
        return "<a href=\"" + page.escapeAttr(href)
                + "\" style=\"color:" + page.colorHex(color)
                + "; text-decoration: underline\">"
                + page.escapeHtml(label) + "</a>"
    }

    // Plain show notes -> quiet underlined links. seek: offsets stay on this page.
    // `color` is part of the HTML so the notes binding rebuilds when the theme changes.
    function linkify(plain, color) {
        if (!plain || plain.length === 0)
            return ""
        var re = /https?:\/\/[^\s<]+|www\.[^\s<]+|\d{1,2}:[0-5]\d:[0-5]\d|\d{1,4}:[0-5]\d/gi
        var out = ""
        var last = 0
        var match
        while ((match = re.exec(plain)) !== null) {
            var start = match.index
            var token = match[0]
            var prev = start > 0 ? plain.charAt(start - 1) : ""
            var end = start + token.length
            var next = end < plain.length ? plain.charAt(end) : ""
            var head = token.charAt(0)
            var isUrl = head === "h" || head === "H" || head === "w" || head === "W"
            if (isUrl) {
                if (prev && /[A-Za-z0-9]/.test(prev))
                    continue
                var peeled = page.peelUrl(token)
                if (peeled.url.length === 0)
                    continue
                var href = /^www\./i.test(peeled.url) ? "https://" + peeled.url : peeled.url
                out += page.escapeHtml(plain.slice(last, start)).replace(/\n/g, "<br>")
                out += page.anchorHtml(href, peeled.url, color)
                out += page.escapeHtml(peeled.trail)
                last = end
                continue
            }
            if ((prev && /[0-9:A-Za-z]/.test(prev)) || (next && /[0-9:A-Za-z]/.test(next)))
                continue
            if (next === "." && end + 1 < plain.length && /[0-9]/.test(plain.charAt(end + 1)))
                continue
            var seconds = page.stampSeconds(token)
            if (!(seconds >= 0))
                continue
            out += page.escapeHtml(plain.slice(last, start)).replace(/\n/g, "<br>")
            out += page.anchorHtml("seek:" + seconds, token, color)
            last = end
        }
        out += page.escapeHtml(plain.slice(last)).replace(/\n/g, "<br>")
        return out
    }

    function playFrom(seconds) {
        var id = backend.openEpisodeId
        if (!id)
            return
        // Already loaded: seek in place. playEpisode() would pause if it is playing.
        var loaded = backend.playerEpisodeId === id
        if (!loaded)
            backend.playEpisode(id)
        backend.seekTo(seconds)
        if (loaded && backend.playerStatus !== "playing")
            backend.togglePlayback()
    }

    function openDescriptionLink(link) {
        if (link.indexOf("seek:") === 0) {
            var seconds = Number(link.slice(5))
            if (!(seconds >= 0))
                return
            page.playFrom(seconds)
            return
        }
        Qt.openUrlExternally(link)
    }

    // Right-click copies the web URL. Timestamps are seek: links and stay on the page.
    function copyWebLink(link) {
        if (!link || link.length === 0)
            return
        if (link.indexOf("http://") !== 0 && link.indexOf("https://") !== 0)
            return
        linkClip.text = link
        linkClip.selectAll()
        linkClip.copy()
        linkClip.deselect()
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
            icon.source: "qrc:/icons/back-symbolic.svg"
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
                icon.name: backend.playerEpisodeId === backend.openEpisodeId
                           && backend.playerStatus === "playing"
                           ? "media-playback-pause-symbolic"
                           : "media-playback-start-symbolic"
                tip: backend.playerEpisodeId === backend.openEpisodeId
                     && backend.playerStatus === "playing" ? "Pause" : "Play"
                onClicked: backend.playEpisode(backend.openEpisodeId)
            }
            IconButton {
                // queueCount in the binding re-evaluates isQueued when the queue changes.
                readonly property bool queued: backend.queueCount >= 0 && backend.isQueued(backend.openEpisodeId)
                icon.source: queued ? "qrc:/icons/queue-remove-symbolic.svg"
                                    : "qrc:/icons/queue-add-symbolic.svg"
                tip: queued ? "Remove from queue" : "Add to queue"
                onClicked: queued ? backend.removeFromQueue(backend.openEpisodeId)
                                  : backend.addToQueue(backend.openEpisodeId)
            }
            IconButton {
                icon.source: "qrc:/icons/info-symbolic.svg"
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
                text: backend.openEpisodeTitle
                color: theme.foreground
                font.pixelSize: theme.heading
                wrapMode: TextEdit.NoWrap
                clip: true
            }
            SelectableText {
                width: parent.width
                text: backend.openShowTitle
                color: theme.dim
                font.pixelSize: theme.caption
                wrapMode: TextEdit.NoWrap
                clip: true
            }
        }
    }

    Flickable {
        id: scroller
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: body.implicitHeight + 48 * theme.textScale
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        FastWheel { }

        Column {
            id: body
            width: Math.min(parent.width - 48, 720)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            spacing: 16

            Item {
                width: parent.width
                height: Math.max(artFrame.height, metaColumn.implicitHeight)

                Rectangle {
                    id: artFrame
                    width: 160 * theme.textScale
                    height: width
                    color: theme.selection
                    visible: page.art !== ""
                    Image {
                        anchors.fill: parent
                        source: page.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    // Right-click: the same art menu as Now Playing.
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: artMenu.openFor(backend.openEpisodeId, backend.openShowId)
                    }
                }
                Rectangle {
                    width: 160 * theme.textScale
                    height: width
                    color: theme.selection
                    visible: page.art === ""
                    Text {
                        anchors.centerIn: parent
                        text: "No art"
                        color: theme.dim
                        font.pixelSize: theme.caption
                        font.weight: Font.Normal
                    }
                }

                Column {
                    id: metaColumn
                    anchors.left: artFrame.right
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    SelectableText {
                        width: parent.width
                        text: page.metaLine()
                        color: theme.dim
                        font.pixelSize: theme.body
                        wrapMode: TextEdit.Wrap
                    }
                    Rectangle {
                        visible: !backend.openEpisodePlayed
                                 && backend.openEpisodeDuration > 0
                                 && backend.openEpisodePositionMs > 0
                        width: Math.min(parent.width, 280 * theme.textScale)
                        height: 3
                        radius: theme.rIcon
                        color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.15)
                        Rectangle {
                            width: parent.width * Math.min(1, backend.openEpisodePositionMs
                                                           / (backend.openEpisodeDuration * 1000))
                            height: parent.height
                            color: theme.accent
                        }
                    }
                    // Queue membership, live: "In queue, #2 of 5".
                    Row {
                        readonly property int slot: backend.queueCount >= 0
                                                    ? backend.queueSlot(backend.openEpisodeId) : 0
                        visible: slot > 0
                        spacing: 6
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(theme.bodySmall * 1.1)
                            height: width
                            sourceSize: Qt.size(width, height)
                            source: "qrc:/icons/queued-symbolic.svg"
                            color: theme.dim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "In queue, #" + parent.slot + " of " + backend.queueCount
                            color: theme.dim
                            font.pixelSize: theme.bodySmall
                            font.family: "monospace"
                        }
                    }
                }
            }

            SelectableText {
                id: notes
                width: parent.width
                visible: backend.openEpisodeDescription.length > 0
                text: page.linkify(backend.openEpisodeDescription, theme.blue)
                textFormat: TextEdit.RichText
                color: theme.foreground
                // RichText ignores linkColor. Each <a> has style color = theme.blue (Omarchy blue / ls folder color).
                font.family: "monospace"
                font.pixelSize: theme.body
                wrapMode: TextEdit.Wrap
                // TextEdit has no lineHeight; spacing stays readable via body size.
                onLinkActivated: function (link) { page.openDescriptionLink(link) }
                onLinkCopyRequested: function (link) { page.copyWebLink(link) }
            }
            SelectableText {
                width: parent.width
                visible: backend.openEpisodeDescription.length === 0
                text: "No description in the feed for this episode."
                color: theme.dim
                font.pixelSize: theme.body
                wrapMode: TextEdit.Wrap
            }
        }
    }

    QuietScroll {
        view: scroller
        anchors.top: scroller.top
        anchors.bottom: scroller.bottom
        anchors.right: parent.right
        anchors.rightMargin: 2
    }


    ArtMenu { id: artMenu }

    TextEdit {
        id: linkClip
        visible: false
        width: 0
        height: 0
    }
}
