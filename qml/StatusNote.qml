import QtQuick

SelectableText {
    id: note
    property int holdMs: 3500
    // While feeds update, the line breathes softly instead of sitting still.
    readonly property bool pulsing: backend.busy && backend.status.startsWith("Updating")

    // Fixed box, elided text: a long show name never pushes anything around.
    text: elider.elidedText
    color: theme.dim
    wrapMode: TextEdit.NoWrap
    clip: true
    opacity: 0

    TextMetrics {
        id: elider
        font: note.font
        text: backend.status
        elide: Text.ElideRight
        elideWidth: Math.max(0, note.width)
    }

    Behavior on opacity {
        enabled: !note.pulsing
        NumberAnimation { duration: 500 }
    }

    SequentialAnimation {
        id: pulse
        running: note.pulsing && note.visible
        loops: Animation.Infinite
        NumberAnimation { target: note; property: "opacity"; to: 0.45; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { target: note; property: "opacity"; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
    }
    onPulsingChanged: {
        if (pulsing) {
            hold.stop()
            opacity = 1
        } else {
            reveal()
        }
    }

    function reveal() {
        if (backend.status.length === 0) {
            opacity = 0
            return
        }
        if (pulsing) {
            hold.stop()
            return
        }
        opacity = 1
        hold.restart()
    }

    Timer {
        id: hold
        interval: note.holdMs
        onTriggered: note.opacity = 0
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
