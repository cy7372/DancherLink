import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

NavigableDialog {
    id: dialog

    property string label
    property string placeholderText: ""
    property string inputValue: editText.text
    property var validator: null
    property var inputMethodHints: Qt.ImhNone
    property int maxLength: 32767

    signal valueAccepted(string value)

    standardButtons: Dialog.Ok | Dialog.Cancel

    onOpened: editText.forceActiveFocus()
    onClosed: editText.clear()

    onAccepted: {
        if (editText.text) {
            dialog.valueAccepted(editText.text.trim())
        }
    }

    ColumnLayout {
        Label {
            text: dialog.label
            font.bold: true
        }

        TextField {
            id: editText
            Layout.fillWidth: true
            focus: true
            placeholderText: dialog.placeholderText
            maximumLength: dialog.maxLength
            validator: dialog.validator
            inputMethodHints: dialog.inputMethodHints

            Keys.onReturnPressed: dialog.accept()
            Keys.onEnterPressed: dialog.accept()
        }
    }
}
