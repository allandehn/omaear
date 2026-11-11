import QtQuick
import QtQuick.Controls

// The tray-menu separator of Omarchy Stable 4.5: an 11px slot holding a 1px line
// in the border colour at 45%, inset 10px on both sides.
MenuSeparator {
    leftPadding: 10
    rightPadding: 10
    topPadding: 5
    bottomPadding: 5

    contentItem: Rectangle {
        implicitWidth: 1
        implicitHeight: 1
        color: Qt.alpha(theme.border, 0.45 * theme.border.a)
    }
}
