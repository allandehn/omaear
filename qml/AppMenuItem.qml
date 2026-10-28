import QtQuick
import QtQuick.Controls

MenuItem {
    id: item
    font.family: "monospace"
    font.pixelSize: theme.titleSize
    font.weight: Font.Normal
    leftPadding: 14
    rightPadding: 14
    topPadding: 6
    bottomPadding: 6
    spacing: 0

    // Choosing (left click, right-drag release, Enter) dismisses the menu at
    // once; the action runs on the next event-loop turn, so a slow handler
    // never holds the menu open or delays its fade-out. Callers use onChosen.
    signal chosen()
    onTriggered: Qt.callLater(item.chosen)

    contentItem: Text {
        text: item.text
        font: item.font
        color: item.enabled ? theme.foreground : theme.dim
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        color: item.highlighted && item.enabled ? theme.selection : "transparent"
        radius: theme.rButton
    }

    HoverHandler {
        enabled: item.enabled
        cursorShape: Qt.PointingHandCursor
    }
}
