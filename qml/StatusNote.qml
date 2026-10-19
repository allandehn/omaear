import QtQuick

SelectableText {
    id: note
    property int holdMs: 3500
    // While feeds update, the line fades in once and holds steady until done.
    readonly property bool updating: backend.busy && backend.status.startsWith("Updating")

    // Fixed box, elided text: a long show name never pushes anything around.
    text: elider.elidedText
    color: theme.dim
    wrapMode: TextEdit.NoWrap
    clip: true
    // Animated visibility; a host may show it on a container instead.
    property real fade: 0
    opacity: fade

    // Unelided width, so a floating pill can hug short messages.
    readonly property real naturalWidth: full.advanceWidth
    TextMetrics {
        id: full
        font: note.font
        text: backend.status
    }

    TextMetrics {
        id: elider
        font: note.font
        text: backend.status
        elide: Text.ElideRight
        elideWidth: Math.max(0, note.width)
    }

    Behavior on fade {
        NumberAnimation { duration: 500 }
    }

    onUpdatingChanged: {
        if (updating) {
            hold.stop()
            fade = 1
        } else {
            reveal()
        }
    }

    function reveal() {
        if (backend.status.length === 0) {
            fade = 0
            return
        }
        if (updating) {
            hold.stop()
            return
        }
        fade = 1
        hold.restart()
    }

    Timer {
        id: hold
        interval: note.holdMs
        onTriggered: note.fade = 0
    }

    Connections {
        target: backend
        function onStatusChanged() { note.reveal() }
    }

    // Do not reveal onCompleted. Cold show pages are created after a shelf
    // refresh has already set backend.status; resurrecting that string made
    // every first open look like "Refresh finished with errors." Warm pages
    // already existed (and had faded), so they never showed it. Live updates
    // still arrive through statusChanged while the note exists.
}
