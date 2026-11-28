import QtQuick
import QtQuick.Controls

// Styled cut/copy/paste/select-all context menu for text fields.
// Replaces the toolkit's default Material ContextMenu so it matches the app
// menu palette, Hyprland rounding, keyboard navigation, and reduceMotion.
AppMenu {
    id: menu
    property TextInput targetField: parent instanceof TextInput ? parent : null
    returnFocusItem: targetField

    AppMenuItem {
        text: "Cut"
        shortcut: "Ctrl+X"
        enabled: !!menu.targetField && !menu.targetField.readOnly
                 && menu.targetField.selectedText.length > 0
                 && menu.targetField.echoMode === TextInput.Normal
        onChosen: if (menu.targetField) menu.targetField.cut()
    }
    AppMenuItem {
        text: "Copy"
        shortcut: "Ctrl+C"
        enabled: !!menu.targetField
                 && menu.targetField.selectedText.length > 0
                 && menu.targetField.echoMode === TextInput.Normal
        onChosen: if (menu.targetField) menu.targetField.copy()
    }
    AppMenuItem {
        text: "Paste"
        shortcut: "Ctrl+V"
        enabled: !!menu.targetField && !menu.targetField.readOnly && menu.targetField.canPaste
        onChosen: if (menu.targetField) menu.targetField.paste()
    }
    AppMenuSeparator {}
    AppMenuItem {
        text: "Select all"
        shortcut: "Ctrl+A"
        enabled: !!menu.targetField && menu.targetField.length > 0
                 && menu.targetField.selectedText.length < menu.targetField.length
        onChosen: if (menu.targetField) menu.targetField.selectAll()
    }
}
