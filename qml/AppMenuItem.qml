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
    property string shortcut: ""
    // The mouse is on the row (own handler, so it doesn't depend on the style's hover setting).
    readonly property bool mouseOver: rowHover.hovered
    // Unified single active row driven by menu.currentIndex (mouse hover updates
    // currentIndex so two rows are never highlighted at once).
    readonly property bool activeRow: highlighted && enabled
    readonly property bool cursor: activeRow

    font.family: "monospace"
    font.pixelSize: theme.body
    font.weight: Font.Normal
    leftPadding: 10
    rightPadding: 10 + (markable ? Math.ceil(font.pixelSize * 1.2) + 10 : 0)
                 + (shortcut.length > 0 && !markable ? Math.ceil(shortcutLabel.implicitWidth) + 16 : 0)
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
        color: item.activeRow ? theme.menuSelectedFg : theme.menuFg
        opacity: item.enabled ? 1.0 : 0.45
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        color: item.activeRow ? theme.menuSelectedBg : "transparent"
        border.width: item.activeRow ? 1 : 0
        border.color: theme.menuSelectedBorder
        radius: Math.min(theme.rounding, Math.floor(height / 2))
    }

    Text {
        id: shortcutLabel
        visible: item.shortcut.length > 0 && !item.markable
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: item.shortcut
        font: item.font
        color: item.activeRow ? theme.menuSelectedFg : Qt.alpha(theme.menuFg, 0.55)
        opacity: item.enabled ? 1.0 : 0.45
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
        onHoveredChanged: {
            if (!hovered || !item.menu)
                return
            for (var i = 0; i < item.menu.count; ++i) {
                if (item.menu.itemAt(i) === item) {
                    item.menu.currentIndex = i
                    break
                }
            }
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
        if (item.menu)
            item.menu.handleKey(event)
    }
}
