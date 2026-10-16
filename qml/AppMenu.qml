import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Menu {
    id: menu
    font.family: "monospace"
    font.pixelSize: theme.titleSize
    font.weight: Font.Normal
    padding: 1
    topPadding: 4
    bottomPadding: 4
    Material.elevation: 0
    // Esc / Back close the open menu first (Main.back), then hand keys back
    // to page navigation with the ring where it was.
    onOpened: win.openPopup = menu
    onClosed: {
        if (win.openPopup === menu)
            win.openPopup = null
        if (win.navPages.indexOf(win.pageKind) >= 0)
            Qt.callLater(win.navRestoreFocus)
    }

    // Keyboard open (Menu key / Shift+F10): beside the item, first usable entry lit.
    function popupAt(item) {
        if (item)
            popup(item, Math.min(item.width * 0.5, 160), Math.min(item.height * 0.5, 80))
        else
            popup()
        for (var i = 0; i < count; ++i) {
            var entry = itemAt(i)
            if (entry && entry.enabled && entry.text !== undefined && entry.text.length > 0) {
                currentIndex = i
                break
            }
        }
        forceActiveFocus()
    }

    // List content reports no implicit width, so the panel would collapse to the border.
    implicitWidth: {
        var widest = 0
        for (var i = 0; i < count; ++i) {
            var entry = itemAt(i)
            if (entry)
                widest = Math.max(widest, entry.implicitWidth)
        }
        return Math.ceil(widest + leftPadding + rightPadding)
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 90; easing.type: Easing.OutQuad }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 70; easing.type: Easing.InQuad }
    }

    background: Rectangle {
        color: theme.background
        border.color: theme.foreground
        border.width: 1
    }

    Overlay.modal: Rectangle { color: "transparent" }
    Overlay.modeless: Rectangle { color: "transparent" }
}
