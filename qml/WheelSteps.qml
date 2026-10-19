import QtQuick

// Scroll wheel -> whole steps. Mouse notches are 120; touchpads send many small
// deltas, so they add up to a notch first instead of flying. Takes the wheel
// so the page underneath never scrolls while adjusting.
WheelHandler {
    id: steps
    signal step(int notches)
    property real pending: 0
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
        var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y * 2
        pending += delta
        var n = 0
        while (pending >= 120) { pending -= 120; n += 1 }
        while (pending <= -120) { pending += 120; n -= 1 }
        if (n !== 0)
            steps.step(n)
        event.accepted = true
    }
}
