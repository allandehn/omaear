import QtQuick

// Shared panel look for context menus and the volume/speed popups:
// corners min(R, 4) (theme.rButton), theme background, foreground border.
Rectangle {
    color: theme.background
    border.color: theme.foreground
    border.width: 1
    radius: theme.rButton
}
