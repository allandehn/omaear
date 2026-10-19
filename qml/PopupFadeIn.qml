import QtQuick

// Fade-in for overlay panels that are plain Items (dialogs, Info, preview):
// the same timing as the popups (win.popupFadeInMs / OutCubic). Hiding stays
// instant, so a dialog's contents never vanish under a still-fading scrim.
NumberAnimation {
    id: fade
    property Item host: null
    target: host
    property: "opacity"
    from: 0
    to: 1
    duration: win.popupFadeInMs
    easing.type: Easing.OutCubic
    property Connections watcher: Connections {
        target: fade.host
        function onVisibleChanged() {
            if (fade.host.visible)
                fade.restart()
            else
                fade.host.opacity = 1
        }
    }
}
