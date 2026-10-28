import QtQuick

// Thin thumb for a Flickable, GridView, or ListView. Hidden unless the
// loaded content is taller than the viewport, so short pages stay bare.
// Thumb length is the visible fraction of contentHeight. Count is part of
// that binding: a later append (more shows or episodes) must shrink and
// shift the thumb, not leave the first-paint ratio in place.
// The bar can be dragged or clicked. Wheel events pass through to the view.
Item {
    id: bar
    property var view: null
    // Bind to the view's count where it has one. Plain Flickables stay at 0.
    property int loadedCount: 0

    width: 14
    z: 2

    // Bumped from contentHeight and loadedCount so a var-typed view cannot
    // freeze the geometry on the first height it happened to paint.
    property int layoutRev: 0
    property real scrollY: 0
    property bool scrolling: false

    function noteLayout() {
        layoutRev = layoutRev + 1
        if (view)
            scrollY = view.contentY
    }

    function noteScroll() {
        if (!view)
            return
        scrollY = view.contentY
        scrolling = true
        idle.restart()
    }

    onLoadedCountChanged: noteLayout()
    onViewChanged: noteLayout()
    Component.onCompleted: noteLayout()

    Connections {
        target: bar.view
        ignoreUnknownSignals: true
        function onContentHeightChanged() { bar.noteLayout() }
        function onContentYChanged() { bar.noteScroll() }
        function onCountChanged() { bar.noteLayout() }
        function onVisibleChanged() { bar.noteLayout() }
    }

    Timer {
        id: idle
        interval: 900
        onTriggered: bar.scrolling = false
    }

    readonly property real inset: 3
    readonly property real track: Math.max(0, height - inset * 2)

    readonly property real contentSpan: {
        var rev = layoutRev
        if (!view)
            return 0
        var span = view.contentHeight + view.topMargin + view.bottomMargin
        // loadedCount is a real dependency even when span is unchanged in
        // the same frame the model grows.
        return span + loadedCount * 0
    }

    readonly property bool overflows: {
        var rev = layoutRev
        if (!view || !view.visible || view.height <= 0)
            return false
        // A few pixels of margin is not a scrolling page.
        return contentSpan > view.height + 8
    }

    readonly property real thumbLen: {
        var rev = layoutRev
        if (!overflows || contentSpan <= 0 || track <= 0)
            return 0
        var natural = track * (view.height / contentSpan)
        var floor = Math.min(track, 24)
        if (natural < floor)
            return floor
        if (natural > track)
            return track
        return natural
    }

    readonly property real thumbY: {
        var rev = layoutRev
        var y = scrollY
        if (!view || !overflows || thumbLen <= 0)
            return inset
        var minPos = view.originY - view.topMargin
        var span = contentSpan - view.height
        if (span < 1)
            return inset
        var offset = y - minPos
        if (offset < 0)
            offset = 0
        if (offset > span)
            offset = span
        return inset + (offset / span) * (track - thumbLen)
    }

    visible: overflows

    Rectangle {
        x: parent.width - width - 2
        y: bar.thumbY
        height: Math.max(0, bar.thumbLen)
        radius: theme.rButton
        width: (grab.containsMouse || grab.pressed) ? 8 : 6
        color: (grab.pressed || grab.containsMouse) ? theme.foreground : theme.muted
        // Hidden at rest; appears instantly on scroll or hover, fades out after.
        readonly property bool shown: bar.scrolling || grab.pressed || grab.containsMouse
        opacity: shown ? 0.9 : 0
        Behavior on opacity {
            enabled: !parent.shown
            NumberAnimation { duration: 350; easing.type: Easing.OutQuad }
        }
    }

    function scrollTo(thumbTop) {
        if (!view || track <= thumbLen)
            return
        var minPos = view.originY - view.topMargin
        var span = contentSpan - view.height
        var f = (thumbTop - inset) / (track - thumbLen)
        f = Math.max(0, Math.min(1, f))
        view.contentY = minPos + f * span
    }

    MouseArea {
        id: grab
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        property real grabOffset: 0
        onPressed: (mouse) => {
            if (typeof bar.view.cancelFlick === "function")
                bar.view.cancelFlick()
            var onThumb = mouse.y >= bar.thumbY && mouse.y <= bar.thumbY + bar.thumbLen
            // Clicking the track jumps there; the thumb then follows the drag.
            grabOffset = onThumb ? mouse.y - bar.thumbY : bar.thumbLen / 2
            if (!onThumb)
                bar.scrollTo(mouse.y - grabOffset)
        }
        onPositionChanged: (mouse) => { if (pressed) bar.scrollTo(mouse.y - grabOffset) }
        onWheel: (wheel) => wheel.accepted = false
    }
}
