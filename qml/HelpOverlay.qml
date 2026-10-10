import QtQuick

// Info sheet. Shown by Main when helpOpen is set. No enter/exit animation:
// the panel is already built, so "?" and the header button open it on this frame.
Item {
    id: root

    property bool open: false
    signal dismiss()

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

    function escapeHtml(value) {
        return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function escapeAttr(value) {
        return root.escapeHtml(value).replace(/"/g, "&quot;")
    }

    visible: open

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
        onWheel: (wheel) => wheel.accepted = true
    }

    Rectangle {
        id: card
        z: 1
        anchors.centerIn: parent
        readonly property real pad: 28
        readonly property real gap: 20
        readonly property real limit: Math.max(120, root.height - 48 - pad * 2 - gap - footer.implicitHeight)
        readonly property real bodyHeight: Math.min(column.implicitHeight, limit)
        width: Math.min(root.width - 48, 860)
        height: pad + bodyHeight + gap + footer.implicitHeight + pad
        color: theme.background
        border.color: theme.selection
        border.width: 1
        radius: 8
        clip: true

        // Clicks on the padding stay in the card. The dim area behind it dismisses.
        MouseArea {
            anchors.fill: parent
            z: 0
        }

        Flickable {
            id: scroller
            z: 1
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: card.pad
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            height: card.bodyHeight
            contentWidth: width
            contentHeight: column.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            FastWheel { }

            Column {
                id: column
                width: scroller.width
                spacing: 26

                Text {
                    text: "Info"
                    color: theme.foreground
                    font.pixelSize: theme.heading
                    font.family: "monospace"
                    font.weight: Font.Normal
                }

                ShortcutGroup {
                    title: "Playback"
                    ShortcutRow { keys: "Space"; blurb: "Play or pause" }
                }
                ShortcutGroup {
                    title: "Navigation"
                    ShortcutRow { keys: "?"; blurb: "Show or hide this Info page" }
                    ShortcutRow { keys: "Mouse back / forward"; blurb: "Previous or next page" }
                    ShortcutRow { keys: "Alt+Left / Alt+Right"; blurb: "Previous or next page" }
                    ShortcutRow { keys: "Back / Forward keys"; blurb: "Previous or next page" }
                    ShortcutRow { keys: "Esc"; blurb: "Go back. Closes this panel, dialogs, and page overlays first" }
                    ShortcutRow { keys: "Backspace"; blurb: "Go back, outside a text field" }
                    ShortcutRow { keys: "Ctrl+Q"; blurb: "Close the window. Audio keeps playing" }
                }
                ShortcutGroup {
                    title: "Artwork"
                    ShortcutRow { keys: "Ctrl+mouse wheel"; blurb: "Resize Now Playing art, shelf covers, and episode art" }
                    ShortcutRow { keys: "Ctrl+= / Ctrl+\u2212"; blurb: "Resize shelf covers and episode art" }
                    ShortcutRow { keys: "Ctrl+0"; blurb: "Reset art to its default size on this page" }
                    ShortcutRow { keys: "Ctrl+click Refresh"; blurb: "Refresh and reload artwork" }
                }
                ShortcutGroup {
                    title: "Mouse tricks"
                    ShortcutRow { keys: "Click volume"; blurb: "Mute or unmute" }
                    ShortcutRow { keys: "Hover volume"; blurb: "Volume slider" }
                    ShortcutRow { keys: "Click speed"; blurb: "Step through speeds" }
                    ShortcutRow { keys: "Hover speed"; blurb: "Speed picker in the player bar" }
                    ShortcutRow { keys: "Mono"; blurb: "Mix left and right channels" }
                    ShortcutRow { keys: "Select text"; blurb: "Copies automatically" }
                    ShortcutRow { keys: "Right-click a cover"; blurb: "Copy or save artwork, copy the image URL. Unsubscribe on the shelf" }
                    ShortcutRow { keys: "Right-click an episode"; blurb: "Play next, add to queue, mark played\u2026" }
                    ShortcutRow { keys: "Right-click in the queue"; blurb: "Play now, move, or remove" }
                    ShortcutRow { keys: "Right-click a link"; blurb: "Copy the link" }
                    ShortcutRow { keys: "Right-click in Explore"; blurb: "Subscribe, preview, or copy the feed URL" }
                    ShortcutRow { keys: "Click a timestamp"; blurb: "Jump to it in the episode notes" }
                    ShortcutRow { keys: "Drag in the queue"; blurb: "Reorder" }
                    ShortcutRow { keys: "Click the playing title"; blurb: "Open that episode" }
                    ShortcutRow { keys: "Click Now Playing art"; blurb: "Play or pause" }
                }
            }
        }

        Column {
            id: footer
            z: 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            anchors.bottomMargin: card.pad
            spacing: 4

            Rectangle {
                width: parent.width
                height: 1
                color: theme.selection
            }
            Item { width: 1; height: 8 }
            Text {
                id: updateText
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.RichText
                color: theme.dim
                font.pixelSize: theme.caption
                font.family: "monospace"
                font.weight: Font.Normal
                text: {
                    var head = "OmaEar " + root.escapeHtml(backend.appVersion)
                    if (backend.updatePhase !== "available")
                        return backend.updateMessage.length > 0
                                ? head + " - " + root.escapeHtml(backend.updateMessage) : head
                    var hex = root.colorHex(theme.accent)
                    var version = root.escapeHtml(backend.updateLatest)
                    var href = backend.updateUrl
                    var linked = href.length > 0
                            ? "<a href=\"" + root.escapeAttr(href) + "\" style=\"color:" + hex
                              + "; text-decoration: underline\">" + version + "</a>"
                            : version
                    var upd = "<a href=\"omaear:update\" style=\"color:" + hex + "; text-decoration: underline\">update now</a>"
                    return head + " - Version " + linked + " is available, " + upd
                }
                onLinkActivated: function (link) {
                    if (link === "omaear:update") {
                        if (!backend.runSystemUpdate())
                            Qt.openUrlExternally(backend.updateUrl)
                    } else {
                        Qt.openUrlExternally(link)
                    }
                }

                HoverHandler {
                    cursorShape: updateText.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
    }

    component ShortcutGroup: Column {
        id: group
        property string title: ""
        width: parent.width
        spacing: 9

        Text {
            bottomPadding: 3
            text: group.title
            color: theme.dim
            font.pixelSize: theme.caption
            font.family: "monospace"
            font.weight: Font.Normal
        }
    }

    component ShortcutRow: Item {
        id: row
        property string keys: ""
        property string blurb: ""
        readonly property int keyColumn: Math.min(Math.round(theme.body * 15), Math.max(80, width * 0.46))
        width: parent ? parent.width : 0
        height: Math.max(keyLabel.implicitHeight, blurbLabel.implicitHeight)

        Text {
            id: keyLabel
            width: row.keyColumn
            text: row.keys
            color: theme.foreground
            font.pixelSize: theme.body
            font.family: "monospace"
            font.weight: Font.Normal
            wrapMode: Text.Wrap
        }
        Text {
            id: blurbLabel
            x: row.keyColumn + 16
            width: Math.max(0, row.width - x)
            text: row.blurb
            color: theme.dim
            font.pixelSize: theme.body
            font.family: "monospace"
            font.weight: Font.Normal
            wrapMode: Text.Wrap
        }
    }
}
