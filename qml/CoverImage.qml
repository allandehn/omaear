import QtQuick
import QtQuick.Window

// Local cover that keeps the last ready frame visible until a new source
// reports Image.Ready, so a path or revision change cannot paint an empty
// frame. Used for shelf tiles and list thumbs.
Item {
    id: root
    property url source
    property int sourceSide: coverCache.tileSide
    property bool crop: true
    readonly property alias front: live
    readonly property alias status: live.status
    property url held: ""

    Image {
        id: heldImage
        anchors.fill: parent
        source: root.held
        visible: live.status !== Image.Ready && held !== "" && held !== live.source
        fillMode: root.crop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        asynchronous: false
        cache: true
        smooth: true
        mipmap: true
        sourceSize.width: root.sourceSide / Screen.devicePixelRatio
        sourceSize.height: root.sourceSide / Screen.devicePixelRatio
    }

    Image {
        id: live
        anchors.fill: parent
        source: root.source
        fillMode: root.crop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        // Sync when the memory cache already has this source, so the first
        // frame is the art. Otherwise load off-thread; heldImage covers the gap.
        asynchronous: !coverCache.ready(source, root.sourceSide)
        cache: true
        smooth: true
        mipmap: true
        sourceSize.width: root.sourceSide / Screen.devicePixelRatio
        sourceSize.height: root.sourceSide / Screen.devicePixelRatio
        visible: status === Image.Ready || !heldImage.visible
        onStatusChanged: if (status === Image.Ready) root.held = source
    }

    onSourceChanged: if (source === "") root.held = ""
}
