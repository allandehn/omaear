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
    // Click-through: a press outside closes the menu (normal fade) and still
    // reaches whatever is under it (Back, another cover's right-click, …).
    // Non-modal, undimmed popups don't block the overlay's press.
    modal: false
    dim: false
    // Outside presses are handled by Main.closePopupsAt (C++ window filter),
    // which closes the menu without eating the press.
    closePolicy: Popup.CloseOnEscape
    // When it last started closing, so the button that opened it can toggle:
    // the press that closes it must not reopen it on release.
    property double closedAt: 0
    // Hand Back/Esc back to the page as soon as the menu starts closing,
    // not after the fade (a click on Back lands mid-fade).
    onAboutToHide: {
        closedAt = Date.now()
        if (win.openPopup === menu)
            win.openPopup = null
    }
    // Close without the fade (right-click on another target reopens at once).
    function closeNow() {
        var t = exit
        exit = null
        close()
        exit = t
    }
    function toggleAt(item, x, y, fromKeyboard) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        if (fromKeyboard) popupAt(item)
        else popup(item, x, y)
    }
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

    // Shared popup timing (Main: popupFadeInMs / popupFadeOutMs).
    enter: Transition {
        NumberAnimation { property: "scale"; from: 0.9; to: 1.0; easing.type: Easing.OutQuint; duration: win.popupScaleMs }
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; easing.type: Easing.OutCubic; duration: win.popupFadeInMs }
    }
    exit: Transition {
        NumberAnimation { property: "scale"; from: 1.0; to: 0.9; easing.type: Easing.OutQuint; duration: win.popupScaleMs }
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; easing.type: Easing.OutCubic; duration: win.popupFadeOutMs }
    }

    background: AppPopupBackground {}

    Overlay.modal: Rectangle { color: "transparent" }
    Overlay.modeless: Rectangle { color: "transparent" }
}
