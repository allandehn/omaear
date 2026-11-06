import QtQuick
import QtQuick.Controls.impl

// Small "in queue" mark for a corner of episode art. A dark backing keeps the
// light glyph legible on any art. Hover-only (HoverHandler), so the play
// button underneath still gets every click.
Rectangle {
    id: badge
    property int slot: 0 // 1-based queue position; 0 hides the badge
    visible: slot > 0
    width: Math.round(18 * theme.textScale)
    height: width
    radius: theme.rButton
    color: Qt.rgba(0, 0, 0, 0.62)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.18)
    IconImage {
        anchors.centerIn: parent
        width: Math.round(parent.width * 0.7)
        height: width
        sourceSize: Qt.size(width, height)
        source: theme.iconBase + "queued-symbolic.svg"
        color: "#f2f2f2"
    }
    HoverHandler { id: hh }
    AppTip { visible: hh.hovered; text: "In queue (#" + badge.slot + ")" }
}
