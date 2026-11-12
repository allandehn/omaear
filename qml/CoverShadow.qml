import QtQuick

// Pre-baked soft shadow (static PNG) under a lifted cover; only its opacity and
// scale animate. Put it in a tile delegate, centred on the cover column.
// `target` is the cover Item whose scale it follows.
BorderImage {
    id: shadow
    property bool lifted: false
    property real coverSize: 0
    property Item target: null
    visible: opacity > 0
    x: (parent.width - coverSize) / 2 - 24
    y: -24
    width: coverSize + 48
    height: coverSize + 48
    source: "qrc:/cover-shadow.png"
    border { left: 32; right: 32; top: 32; bottom: 32 }
    opacity: lifted ? 1 : 0
    scale: target ? target.scale : 1
    Behavior on opacity { NumberAnimation { duration: shadow.lifted ? 120 : 100; easing.type: Easing.OutQuad } }
}
