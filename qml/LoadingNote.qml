import QtQuick

// Wording for "Play pressed, audio not started yet" (backend.playerLoading): one
// short line for the player bar and Now playing, and a flag for their spinners.
// The timer only runs while loading, so an idle player costs nothing.
QtObject {
    id: note
    readonly property bool active: backend.playerLoading
    readonly property int percent: backend.playerBufferProgress
    property bool slow: false
    // "Loading… 42%", then "Still loading… 42%" after about 3 s; empty when not loading.
    readonly property string text: !active ? ""
        : (slow ? "Still loading…" : "Loading…") + (percent > 0 ? " " + percent + "%" : "")
    onActiveChanged: slow = false
    property Timer slowTimer: Timer {
        interval: 3000
        running: note.active
        onTriggered: note.slow = true
    }
}
