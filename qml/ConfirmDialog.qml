import QtQuick

// The one dialog panel for OmaEar, after Omarchy's shell/Ui/ConfirmDialog.qml:
// Cancel first, then the action, in a right-aligned row. Keyboard focus starts
// on the action (selectedIndex 1) unless startOnCancel is set; Left/Right/Tab/
// Shift+Tab move between the two, Enter/Space press the focused one, Esc cancels.
// Destructive actions use the theme's urgent colour, others the accent.
// Panel corners are R, buttons min(R, 4). Extra content (e.g. a text field)
// goes between the message and the buttons.
Rectangle {
    id: dialog
    property string title: ""
    property string message: ""
    // Optional dimmed second line under the message (e.g. "This can't be undone.").
    property string detail: ""
    property string actionLabel: ""
    property string cancelLabel: "Cancel"
    property bool destructive: false
    // Approved exception: step 2 of "Unsubscribe from all" starts on Cancel.
    property bool startOnCancel: false
    property int selectedIndex: 1
    // Item that takes focus when the dialog opens (e.g. a text field); null = buttons.
    property Item initialFocusItem: null
    default property alias extra: extraColumn.data
    readonly property color actionColor: destructive ? theme.urgent : theme.accent
    readonly property Item cancelButton: cancelBtn
    readonly property Item actionButton: actionBtn

    signal accepted()
    signal canceled()

    width: Math.min(parent ? parent.width - 48 : 460, 460)
    height: content.implicitHeight + 36
    color: theme.background
    border.color: theme.selection
    border.width: 1
    radius: theme.rCard

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
        spacing: 14

        Text {
            visible: dialog.title.length > 0
            text: dialog.title
            color: theme.foreground
            font.pixelSize: theme.heading
            font.weight: Font.Normal
        }
        Text {
            visible: dialog.message.length > 0
            width: parent.width
            wrapMode: Text.Wrap
            text: dialog.message
            color: theme.foreground
            font.pixelSize: theme.body
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
                switch (event.key) {
                case Qt.Key_Left:
                case Qt.Key_Backtab:
                    dialog.selectedIndex = 0; event.accepted = true; break
                case Qt.Key_Right:
                    dialog.selectedIndex = 1; event.accepted = true; break
                case Qt.Key_Tab:
                    dialog.selectedIndex = dialog.selectedIndex === 0 ? 1 : 0; event.accepted = true; break
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    dialog.activate(dialog.selectedIndex); event.accepted = true; break
                case Qt.Key_Escape:
                    dialog.canceled(); event.accepted = true; break
                }
            }
            Row {
                id: buttons
                anchors.right: parent.right
                spacing: 8
                DialogButton {
                    id: cancelBtn
                    label: dialog.cancelLabel
                    ink: theme.foreground
                    selected: dialog.selectedIndex === 0 && keys.activeFocus
                    onClicked: dialog.canceled()
                }
                DialogButton {
                    id: actionBtn
                    label: dialog.actionLabel
                    ink: dialog.actionColor
                    selected: dialog.selectedIndex === 1 && keys.activeFocus
                    onClicked: dialog.accepted()
                }
            }
        }
    }

    component DialogButton: Rectangle {
        id: button
        property string label: ""
        property color ink: theme.foreground
        property bool selected: false
        signal clicked()
        implicitWidth: text.implicitWidth + 24
        implicitHeight: text.implicitHeight + 12
        radius: theme.rButton
        color: selected ? Qt.rgba(ink.r, ink.g, ink.b, 0.22)
             : mouse.containsMouse ? Qt.rgba(ink.r, ink.g, ink.b, 0.10) : "transparent"
        border.width: selected ? 1 : 0
        border.color: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
        Text {
            id: text
            anchors.centerIn: parent
            text: button.label
            color: button.ink
            font.pixelSize: theme.body
            font.weight: Font.Normal
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
