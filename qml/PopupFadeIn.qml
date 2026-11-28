import QtQuick

// Fade-in for overlay panels that are plain Items (dialogs, Info, preview):
// matches popupOpenMs / reduceMotion while keeping hide instant.
NumberAnimation {
    id: fade
    property Item host: null
    target: host
    property: "opacity"
    from: 0
    to: 1
    duration: win.popupOpenMs
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]
    property Connections watcher: Connections {
        target: fade.host
        function onVisibleChanged() {
            if (!fade.host.visible || win.popupOpenMs <= 0)
                fade.host.opacity = 1
            else
                fade.restart()
        }
    }
}
