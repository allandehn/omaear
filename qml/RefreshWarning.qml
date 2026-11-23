import QtQuick

// Cover-corner badge for a show whose last refresh failed: theme.urgent plus
// our warning glyph (colour never alone). Hover shows the reason. Empty
// reason hides it; the next good refresh of that show clears it.
Rectangle {
    id: badge
    property string reason: ""
    property real size: 22 * theme.textScale
    // The cover's MouseArea sits on top and takes hover, so the host passes its
    // pointer in: hoverArea is that MouseArea (containsMouse, mouseX/mouseY).
    property Item hoverArea: null
    readonly property bool hovered: visible && hoverArea !== null && hoverArea.containsMouse
        && contains(mapFromItem(hoverArea, hoverArea.mouseX, hoverArea.mouseY))
    visible: reason.length > 0
    width: size
    height: size
    // Same rule as the episodes counter (theme.rButton, 0 when Hyprland
    // decoration:rounding is 0), scaled if this badge is a different size.
    readonly property real referenceSize: 22 * theme.textScale
    radius: theme.rounding > 0
        ? Math.min(Math.round(theme.rButton * (size / referenceSize)), Math.round(size / 2))
        : 0
    color: theme.urgent

    function ink(swatch) {
        var l = 0.299 * swatch.r + 0.587 * swatch.g + 0.114 * swatch.b
        var lb = 0.299 * theme.background.r + 0.587 * theme.background.g + 0.114 * theme.background.b
        var lf = 0.299 * theme.foreground.r + 0.587 * theme.foreground.g + 0.114 * theme.foreground.b
        return Math.abs(l - lb) > Math.abs(l - lf) ? theme.background : theme.foreground
    }

    Image {
        anchors.centerIn: parent
        // Lift only in a circle badge. The cover warning follows the counter
        // (a slightly rounded square), so this stays 0 unless the radius is a circle.
        anchors.verticalCenterOffset: radius >= Math.round(size / 2) ? -0.75 * (width / 18) : 0
        width: Math.round(badge.size * 0.68)
        height: width
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        source: badge.visible ? theme.tintedSvg("status-warning.svg", badge.ink(theme.urgent)) : ""
    }

    AppTip {
        visible: badge.hovered && badge.reason.length > 0
        text: badge.reason
    }
}
