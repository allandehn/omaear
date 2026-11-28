import QtQuick
import QtQuick.Controls

ToolTip {
    id: tip
    delay: 400
    enabled: false
    font.family: "monospace"
    font.pixelSize: theme.bodySmall
    font.weight: Font.Normal
    leftPadding: 10
    rightPadding: 10
    topPadding: 6
    bottomPadding: 6
    x: {
        if (!parent)
            return 0
        var desired = Math.round((parent.width - width) / 2)
        if (typeof win === "undefined" || !win || !tip.visible)
            return desired
        var px = parent.mapToItem(null, desired, 0).x
        var clamped = Math.max(8, Math.min(px, win.width - width - 8))
        return desired + (clamped - px)
    }
    y: {
        if (!parent)
            return -implicitHeight - 8
        if (typeof win === "undefined" || !win || !tip.visible)
            return -implicitHeight - 8
        var py = parent.mapToItem(null, 0, 0).y
        var desired = py < implicitHeight + 16 ? parent.height + 8 : -implicitHeight - 8
        var wy = py + desired
        var clamped = Math.max(8, Math.min(wy, win.height - implicitHeight - 8))
        return desired + (clamped - wy)
    }

    enter: null
    exit: null

    Connections {
        target: typeof win !== "undefined" ? win : null
        function onActiveChanged() {
            if (win && !win.active)
                tip.close()
        }
    }

    // Long text (e.g. a full episode title or explore summary) wraps inside the window.
    width: Math.min(implicitWidth, (typeof win !== "undefined" && win ? win.width : 600) - 24)

    contentItem: Text {
        wrapMode: Text.Wrap
        text: tip.text
        font: tip.font
        color: theme.tooltipFg
    }

    background: Rectangle {
        color: theme.tooltipBg
        border.color: theme.tooltipBorder
        border.width: 1
        radius: Math.min(theme.rounding, Math.floor(height / 2))
    }
}
