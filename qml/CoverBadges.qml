import QtQuick

// Unheard count and refresh-error badges on a cover. The warning sits just
// left of the count; when there is no count, it takes the count's place
// (top-right). Both follow the episodes counter's corner radius: theme.rButton
// (min of Hyprland decoration:rounding and 4), which is 0 when rounding is 0.
Item {
    id: root
    objectName: "coverBadges"
    property int unheard: 0
    property string refreshError: ""
    property Item hoverArea: null
    property int margins: 8
    property int gap: 4

    // Same height as the usual counter; shrink on a short list-row cover.
    readonly property real badgeHeight: Math.min(22 * theme.textScale,
                                                 height > 0 ? height * 0.5 : 22 * theme.textScale)
    // theme.rButton is already 0 when rounding is 0; say so explicitly.
    readonly property int countRadius: theme.rounding > 0 ? theme.rButton : 0

    anchors.fill: parent

    function inkOnAccent(swatch) {
        var accentLuma = 0.299 * swatch.r + 0.587 * swatch.g + 0.114 * swatch.b
        var backgroundLuma = 0.299 * theme.background.r + 0.587 * theme.background.g + 0.114 * theme.background.b
        var foregroundLuma = 0.299 * theme.foreground.r + 0.587 * theme.foreground.g + 0.114 * theme.foreground.b
        return Math.abs(accentLuma - backgroundLuma) > Math.abs(accentLuma - foregroundLuma)
                ? theme.background : theme.foreground
    }

    Rectangle {
        id: countBadge
        objectName: "unheardBadge"
        visible: root.unheard > 0
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: root.margins
        radius: root.countRadius
        color: theme.accent
        height: root.badgeHeight
        width: Math.max(height, countLabel.implicitWidth + 12)
        Text {
            id: countLabel
            anchors.centerIn: parent
            text: root.unheard > 99 ? "99+" : root.unheard
            color: root.inkOnAccent(theme.accent)
            font.pixelSize: theme.caption
            font.weight: Font.Normal
        }
    }

    RefreshWarning {
        id: warningBadge
        objectName: "refreshWarning"
        reason: root.refreshError
        hoverArea: root.hoverArea
        size: root.badgeHeight
        anchors.top: parent.top
        anchors.topMargin: root.margins
        anchors.right: countBadge.visible ? countBadge.left : parent.right
        anchors.rightMargin: countBadge.visible ? root.gap : root.margins
    }
}
