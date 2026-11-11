import QtQuick
import QtQuick.Controls

// One context-menu row, after the dock menu of Omarchy Stable 4.5:
// 28px high, 10px left padding, text at the theme's body size.
//   mouse hover:     foreground at 8%, text colour unchanged
//   keyboard cursor: the same 8% fill with the text turned to the accent
//                    (the Omarchy launcher's convention)
//   disabled:        45% opacity, no fill
//   state:           a setting or the current choice sets markable (reserves the
//                    column so labels don't shift) and marked (an accent check
//                    mark at the right edge, 10px in). Menus have no pills.
MenuItem {
    id: item
    property bool markable: false
    property bool marked: false
    // The mouse is on the row (own handler, so it doesn't depend on the style's hover setting).
    readonly property bool mouseOver: rowHover.hovered
    // The keyboard cursor: the row Qt highlights while the mouse is not on it.
    readonly property bool cursor: highlighted && !mouseOver && enabled

    font.family: "monospace"
    font.pixelSize: theme.body
    font.weight: Font.Normal
    leftPadding: 10
    rightPadding: 10 + (markable ? Math.ceil(font.pixelSize * 1.2) + 10 : 0)
    topPadding: 0
    bottomPadding: 0
    implicitHeight: Math.round(28 * theme.textScale)
    spacing: 0

    // Choosing (left click, right-drag release, Enter) dismisses the menu at
    // once; the action runs on the next event-loop turn, so a slow handler
    // never holds the menu open or delays its fade-out. Callers use onChosen.
    signal chosen()
    onTriggered: Qt.callLater(item.chosen)

    contentItem: Text {
        text: item.text
        font: item.font
        color: item.cursor ? theme.accent : theme.popupText
        opacity: item.enabled ? 1.0 : 0.45
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        color: (item.highlighted || item.mouseOver) && item.enabled ? Qt.alpha(theme.foreground, 0.08) : "transparent"
        radius: theme.rounding
    }

    Text {
        visible: item.marked
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: "\u2713"
        font.pixelSize: item.font.pixelSize
        color: theme.accent
        opacity: item.enabled ? 1.0 : 0.45
    }

    HoverHandler {
        id: rowHover
        enabled: item.enabled
        cursorShape: Qt.PointingHandCursor
    }
}
