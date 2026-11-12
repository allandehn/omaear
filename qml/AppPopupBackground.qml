import QtQuick

// Shared card for context menus and the volume/speed/region popups, after
// Omarchy Stable 4.5's popup card: [popups] background and border from the live
// theme (theme.popupBackground / theme.border: the theme's Hyprland active border,
// accent when it has none), 1px wide, corner radius = the live Hyprland rounding
// (theme.rounding), never a fixed value.
Rectangle {
    color: theme.popupBackground
    border.color: theme.border
    border.width: 1
    radius: theme.rounding
}
