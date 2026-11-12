import QtQuick

// The quiet theme-foreground outline around a cover. Shelf and Explore share it.
// glide: one ring parked in the grid's content item, moved by `cellIndex` with the
// Navigation animation (~120 ms, eased both ends). A Behavior retargets from
// wherever it is, so fast presses never queue. Without glide, the caller places
// it inside a delegate (static ring, the animation off).
Rectangle {
    id: ring
    property real coverSize: 0
    property bool glide: false
    property int cellIndex: 0
    property int columns: 1
    property real cellWidth: 0
    property real cellHeight: 0
    readonly property int col: cellIndex % Math.max(1, columns)
    readonly property int row: Math.floor(cellIndex / Math.max(1, columns))
    x: col * cellWidth + (cellWidth - coverSize) / 2 - 4
    y: row * cellHeight - 4
    width: coverSize + 8
    height: coverSize + 8
    radius: theme.rButton
    color: "transparent"
    border.width: 2
    border.color: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.7)
    scale: glide ? (win.keyRepeating ? 1 : 1.03) : 1 // glide: hugs the lifted cover
    Behavior on x { enabled: ring.glide && ring.visible; NumberAnimation { duration: 120; easing.type: Easing.InOutQuad } }
    Behavior on y { enabled: ring.glide && ring.visible; NumberAnimation { duration: 120; easing.type: Easing.InOutQuad } }
}
