import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Menu {
    id: menu
    font.family: "monospace"
    font.pixelSize: theme.body
    font.weight: Font.Normal
    // Omarchy Stable 4.5 popup card (dock menu): 4px padding inside the
    // 1px-border card (AppPopupBackground), rows of 28px (AppMenuItem), at
    // least 150px wide.
    padding: 4
    Material.elevation: 0
    // Click-through: a press outside closes the menu (normal fade) and still
    // reaches whatever is under it (Back, another cover's right-click, …).
    // Non-modal, undimmed popups don't block the overlay's press.
    modal: false
    dim: false
    // Outside presses are handled by Main.closePopupsAt (C++ window filter),
    // which closes the menu without eating the press.
    closePolicy: Popup.CloseOnEscape
    popupType: Popup.Item
    focus: true
    // Optional target that regains focus when this menu closes (e.g. a TextField).
    property Item returnFocusItem: null
    property bool closing: false
    enabled: !closing
    // When it last started closing, so the button that opened it can toggle:
    // the press that closes it must not reopen it on release.
    property double closedAt: 0
    onAboutToShow: {
        closing = false
        currentIndex = -1
        win.openPopup = menu
    }
    // Hand Back/Esc back to the page as soon as the menu starts closing,
    // not after the fade (a click on Back lands mid-fade).
    onAboutToHide: {
        closing = true
        closedAt = Date.now()
        if (win.openPopup === menu)
            win.openPopup = null
    }
    // Close without the fade (right-click on another target reopens at once).
    function closeNow() {
        exit = null
        close()
        exit = Qt.binding(function() { return theme.reduceMotion ? null : exitAnim })
    }
    function toggleAt(item, x, y, fromKeyboard) {
        if (visible) { close(); return }
        if (Date.now() - closedAt < 300) return
        if (fromKeyboard) {
            popupAt(item)
        } else if (item && menu.parent) {
            var pt = item.mapToItem(menu.parent, x, y)
            popup(pt.x, pt.y)
        } else {
            popup(item, x, y)
        }
    }
    function isSelectable(i) {
        var entry = itemAt(i)
        return entry && entry.visible && entry.enabled && entry.text !== undefined && entry.text.length > 0
    }
    function jumpEdge(last) {
        var i = last ? count - 1 : 0
        var step = last ? -1 : 1
        for (; i >= 0 && i < count; i += step) {
            if (isSelectable(i)) {
                currentIndex = i
                return true
            }
        }
        return false
    }
    function moveSelection(step) {
        if (count <= 0)
            return false
        var start = currentIndex
        var i = start
        for (var n = 0; n < count; ++n) {
            if (i < 0)
                i = step > 0 ? 0 : count - 1
            else
                i = (i + step + count) % count
            if (isSelectable(i)) {
                currentIndex = i
                return true
            }
        }
        return false
    }
    function activateCurrent() {
        if (!isSelectable(currentIndex))
            return false
        var entry = itemAt(currentIndex)
        entry.triggered()
        close()
        return true
    }
    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            if (moveSelection(1))
                event.accepted = true
            return
        case Qt.Key_Up:
        case Qt.Key_K:
            if (moveSelection(-1))
                event.accepted = true
            return
        case Qt.Key_Home:
            if (jumpEdge(false))
                event.accepted = true
            return
        case Qt.Key_End:
            if (jumpEdge(true))
                event.accepted = true
            return
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (activateCurrent())
                event.accepted = true
            return
        }
    }
    // Esc / Back close the open menu first (Main.back), then hand keys back
    // to page navigation with the ring where it was (or a returnFocusItem).
    onOpened: {
        win.openPopup = menu
        if (contentItem)
            contentItem.forceActiveFocus()
    }
    onClosed: {
        closing = false
        if (win.openPopup === menu)
            win.openPopup = null
        if (returnFocusItem && returnFocusItem.visible) {
            var target = returnFocusItem
            Qt.callLater(function() {
                if (target && target.visible)
                    target.forceActiveFocus()
            })
        } else if (!win.modalOpen && win.navPages.indexOf(win.pageKind) >= 0) {
            Qt.callLater(win.navRestoreFocus)
        }
    }

    // Keyboard open (Menu key / Shift+F10): beside the item, first usable entry lit.
    // Map coordinates to menu.parent instead of calling popup(item, x, y), which
    // in Qt 6 reparents the Menu onto transient grid/list delegates.
    function popupAt(item) {
        if (item && menu.parent) {
            var pt = item.mapToItem(menu.parent, Math.min(item.width * 0.5, 160), Math.min(item.height * 0.5, 80))
            popup(pt.x, pt.y)
        } else if (item) {
            popup(item, Math.min(item.width * 0.5, 160), Math.min(item.height * 0.5, 80))
        } else {
            popup()
        }
        jumpEdge(false)
        if (contentItem)
            contentItem.forceActiveFocus()
        else
            forceActiveFocus()
    }

    // List content reports no implicit width, so the panel would collapse to the border.
    // Rows that are hidden (visible: false) don't widen it.
    readonly property int minWidth: 150
    readonly property real maxContentHeight: Math.max(
        Math.round(80 * theme.textScale),
        Math.min(Math.round(28 * theme.textScale) * 8, win.height - 16 - topPadding - bottomPadding))
    implicitWidth: {
        var widest = 0
        for (var i = 0; i < count; ++i) {
            var entry = itemAt(i)
            if (entry && entry.visible)
                widest = Math.max(widest, entry.implicitWidth)
        }
        return Math.max(minWidth, Math.ceil(widest + leftPadding + rightPadding))
    }

    contentItem: ListView {
        focus: true
        implicitHeight: Math.min(contentHeight, menu.maxContentHeight)
        model: menu.contentModel
        interactive: contentHeight > height
        clip: true
        currentIndex: menu.currentIndex
        boundsBehavior: Flickable.StopAtBounds
        ScrollIndicator.vertical: ScrollIndicator {}
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { menu.handleKey(event) }
    }

    property Transition enterAnim: Transition {
        NumberAnimation { property: "scale"; from: 0.97; to: 1.0; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]; duration: win.popupOpenMs }
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]; duration: win.popupOpenMs }
    }
    property Transition exitAnim: Transition {
        NumberAnimation { property: "scale"; from: 1.0; to: 0.97; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]; duration: win.popupCloseMs }
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]; duration: win.popupCloseMs }
    }

    // Shared PopupCard timing (180ms open / 120ms close, cubic-bezier(0.23, 1, 0.32, 1),
    // 0.97 <-> 1.0, or instant 0ms transitions when reduceMotion is active).
    enter: theme.reduceMotion ? null : enterAnim
    exit: theme.reduceMotion ? null : exitAnim

    background: AppPopupBackground {}

    Overlay.modal: Rectangle { color: "transparent" }
    Overlay.modeless: Rectangle { color: "transparent" }
}
