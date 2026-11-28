import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Single-line text field with OmaEar's themed Cut/Copy/Paste/Select-all menu.
// Keeps text selection alive while focus moves into the popup menu.
TextField {
    id: field
    readonly property AppMenu contextMenu: fieldMenu
    persistentSelection: true
    font.family: "monospace"
    font.weight: Font.Normal
    Material.accent: theme.accent

    ContextMenu.menu: TextFieldMenu {
        id: fieldMenu
        targetField: field
    }
}
