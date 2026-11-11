import QtQuick

// The one dialog card for OmaEar, after Omarchy Stable 4.5's shell/Ui/ConfirmDialog.qml:
// a question that names the thing, then outlined square buttons at the bottom
// right, Cancel on the left and the action rightmost. The scrim and its
// click-to-cancel live in Main.
//   Keys:   Esc cancels; Left/Right/Tab/Shift+Tab (and h/l) swap the selected
//           button; Enter (or Space) presses it. Hovering a button selects it.
//   Colour: Cancel is idle foreground@38%, selected accent with an 8% fill;
//           the action is urgent (destructive) or accent (anything else):
//           idle border tone@56% with foreground text, selected tone border,
//           tone text and a tone@22% fill.
//   Focus:  4.5 starts on the action (selectedIndex 1). startOnCancel is
//           OmaEar's per-dialog deviation (Main decides which dialogs).
// Extra content (e.g. a text field) goes between the message and the buttons.
Rectangle {
    id: dialog
    // The question, e.g. "Unsubscribe from Alpha Show?". The button carries the verb.
    property string message: ""
    // Optional dimmed second line under the message (e.g. "This can't be undone.").
    property string detail: ""
    property string actionLabel: ""
    property string cancelLabel: "Cancel"
    property bool destructive: false
    // Start on Cancel instead of the action (decided per dialog in Main).
    property bool startOnCancel: false
    property int selectedIndex: 1
    // Item that takes focus when the dialog opens (e.g. a text field); null = buttons.
    property Item initialFocusItem: null
    default property alias extra: extraColumn.data
    readonly property color actionTone: destructive ? theme.urgent : theme.accent
    readonly property int buttonRadius: 0
    readonly property Item cancelButton: cancelBtn
    readonly property Item actionButton: actionBtn

    signal accepted()
    signal canceled()

    width: Math.min(parent ? parent.width - 32 : 370, 370)
    height: content.implicitHeight + 36
    color: theme.background
    border.color: theme.accent
    border.width: 1
    radius: theme.rounding

    function focusButtons(index) {
        selectedIndex = index
        keys.forceActiveFocus()
    }
    function reset() {
        selectedIndex = startOnCancel ? 0 : 1
        if (initialFocusItem)
            initialFocusItem.forceActiveFocus()
        else
            keys.forceActiveFocus()
    }
    function activate(index) {
        if (index === 1)
            accepted()
        else
            canceled()
    }
    function swapSelection() {
        selectedIndex = selectedIndex === 0 ? 1 : 0
    }
    // The key table, apart from the Keys handler so the UI test can drive it.
    function handleKey(key) {
        switch (key) {
        case Qt.Key_Escape:
            canceled(); return true
        case Qt.Key_Left:
        case Qt.Key_Right:
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
        case Qt.Key_H:
        case Qt.Key_L:
            swapSelection(); return true
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            activate(selectedIndex); return true
        }
        return false
    }
    onVisibleChanged: if (visible) Qt.callLater(reset)
    onStartOnCancelChanged: if (visible) Qt.callLater(reset)
    onActionLabelChanged: if (visible) Qt.callLater(reset)

    // Swallow clicks so they don't reach the scrim (which cancels).
    MouseArea { anchors.fill: parent }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 16

        Text {
            visible: dialog.message.length > 0
            width: parent.width
            wrapMode: Text.Wrap
            text: dialog.message
            color: theme.foreground
            font.pixelSize: theme.titleSize
            font.weight: Font.Normal
        }
        Text {
            visible: dialog.detail.length > 0
            width: parent.width
            wrapMode: Text.Wrap
            text: dialog.detail
            color: theme.dim
            font.pixelSize: theme.body
            font.weight: Font.Normal
        }
        Column {
            id: extraColumn
            width: parent.width
            spacing: 12
            visible: children.length > 0
        }
        Item {
            id: keys
            width: parent.width
            height: buttons.implicitHeight
            // A menu that opened this dialog hands focus back when it finishes closing;
            // take it back so the selected button stays highlighted and keys work.
            onActiveFocusChanged: if (!activeFocus && dialog.visible && !dialog.initialFocusItem)
                Qt.callLater(function() { if (dialog.visible && !dialog.initialFocusItem) keys.forceActiveFocus() })
            Keys.onPressed: function(event) {
                if (dialog.handleKey(event.key))
                    event.accepted = true
            }
            Row {
                id: buttons
                anchors.right: parent.right
                spacing: 10
                DialogButton {
                    id: cancelBtn
                    label: dialog.cancelLabel
                    cornerRadius: dialog.buttonRadius
                    selected: dialog.selectedIndex === 0 && (keys.activeFocus || hovered)
                    idleBorder: Qt.alpha(theme.foreground, 0.38)
                    selectedBorder: theme.accent
                    idleText: theme.foreground
                    selectedText: theme.accent
                    selectedFill: Qt.alpha(theme.foreground, 0.08)
                    onEntered: dialog.selectedIndex = 0
                    onClicked: dialog.canceled()
                }
                DialogButton {
                    id: actionBtn
                    label: dialog.actionLabel
                    cornerRadius: dialog.buttonRadius
                    selected: dialog.selectedIndex === 1 && (keys.activeFocus || hovered)
                    idleBorder: Qt.alpha(dialog.actionTone, 0.56)
                    selectedBorder: dialog.actionTone
                    idleText: theme.foreground
                    selectedText: dialog.actionTone
                    selectedFill: Qt.alpha(dialog.actionTone, 0.22)
                    onEntered: dialog.selectedIndex = 1
                    onClicked: dialog.accepted()
                }
            }
        }
    }

    // Outlined, square (radius 0 on every theme, as in 4.5), at least 88x34.
    component DialogButton: Rectangle {
        id: button
        property string label: ""
        property bool selected: false
        property color idleBorder
        property color selectedBorder
        property color idleText
        property color selectedText
        property color selectedFill
        property int cornerRadius: 0
        readonly property bool hovered: mouse.containsMouse
        signal clicked()
        signal entered()
        implicitWidth: Math.max(Math.round(88 * theme.textScale), text.implicitWidth + 24)
        implicitHeight: Math.round(34 * theme.textScale)
        // Omarchy's ConfirmDialog hard-codes square buttons (shell/Ui/ConfirmDialog.qml:107), on
        // every theme. Set this to theme.rounding to make them follow the window corners instead.
        radius: cornerRadius
        color: selected ? selectedFill : "transparent"
        border.width: 1
        border.color: selected ? selectedBorder : idleBorder
        Text {
            id: text
            anchors.centerIn: parent
            text: button.label
            color: button.selected ? button.selectedText : button.idleText
            font.pixelSize: theme.caption
            font.weight: Font.Normal
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: button.entered()
            onClicked: button.clicked()
        }
    }
}
