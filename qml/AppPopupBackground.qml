import QtQuick

// Shared card for menus and dropdown popups: 1px border and full Hyprland
// rounding. Context menus default to [menu] tokens; dropdowns pass [popups].
Rectangle {
    property color fillColor: theme.menuBg
    property color strokeColor: theme.menuBorder
    color: fillColor
    border.color: strokeColor
    border.width: 1
    radius: theme.rounding
}
