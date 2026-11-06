import QtQuick
import QtQuick.Effects

// Rounds a cover to the live theme radius. Use it as the layer effect of the
// cover's container so the art, its placeholder and any hover tint are clipped
// together:
//
//     readonly property real coverRadius: theme.rCard   // rButton for row thumbs, rInner(p) when snug in a rounded container
//     layer.enabled: coverRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Software // no shader effects there: stay square
//     layer.effect: CoverClip { art: theImage; radius: container.coverRadius }
//
// Cost: none at R = 0 (layer off, the cover draws exactly as before). At R > 0
// each visible cover renders once into its own texture at display size, plus a
// mask texture of at most 128 px, and is drawn with one MultiEffect pass.
//
// Art with baked-in rounded corners on a flat colour (coverCache.preRounded,
// checked once per image and cached in C++) is clipped a little tighter
// (8% of the art size, or R if larger) so those corners disappear.
MultiEffect {
    id: clip
    property Image art: null
    property real radius: theme.rCard

    readonly property bool preRounded: !!art && art.status === Image.Ready && radius > 0
        && coverCache.preRounded(String(art.source))
    readonly property real effectiveRadius: radius <= 0 ? 0
        : preRounded ? Math.max(radius, 0.08 * Math.min(width, height)) : radius

    autoPaddingEnabled: false
    maskEnabled: true
    maskSource: mask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 0.25

    Item {
        id: mask
        width: clip.width
        height: clip.height
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.min(width, 128), Math.min(height, 128))
        Rectangle {
            anchors.fill: parent
            radius: clip.effectiveRadius
            antialiasing: true
        }
    }
}
