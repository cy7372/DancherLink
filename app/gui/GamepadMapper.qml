import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls.Material 2.15
import SdlGamepadKeyNavigation 1.0

Page {
    id: gamepadMapperPage
    objectName: qsTr("Gamepad Mapping")

    background: Rectangle {
        color: Material.background
    }

    Component.onCompleted: {
        refreshGamepads()
    }

    function refreshGamepads() {
        gamepadModel.clear()
        var names = SdlGamepadKeyNavigation.getGamepadNames()
        for (var i = 0; i < names.length; i++) {
            gamepadModel.append({ "name": names[i] })
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        Label {
            text: qsTr("Connected Gamepads")
            font.pointSize: 20
            Layout.alignment: Qt.AlignHCenter
        }

        ListView {
            id: gamepadList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ListModel { id: gamepadModel }

            delegate: ItemDelegate {
                width: parent.width
                text: model.name
                font.pointSize: 16
                
                contentItem: RowLayout {
                    Label {
                        text: model.name
                        font.pointSize: 16
                        Layout.fillWidth: true
                        color: Material.foreground
                    }
                    Button {
                        text: qsTr("Map")
                        onClicked: {
                            console.log("Mapping requested for: " + model.name)
                            mappingDialog.gamepadIndex = index
                            mappingDialog.gamepadName = model.name
                            mappingDialog.open()
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Material.accent
                border.width: 1
                visible: gamepadList.count === 0
                
                Label {
                    anchors.centerIn: parent
                    text: qsTr("No gamepads detected")
                    color: Material.hintTextColor
                    font.pointSize: 14
                }
            }
        }

        Button {
            text: qsTr("Refresh")
            Layout.alignment: Qt.AlignHCenter
            onClicked: refreshGamepads()
        }
    }

    // Gamepad Mapping Dialog
    NavigableDialog {
        id: mappingDialog
        property int gamepadIndex: -1
        property string gamepadName: ""
        property int currentMappingStep: 0
        property var mappingResults: ({})

        readonly property var mappingButtons: [
            { name: "A", label: qsTr("A Button") },
            { name: "B", label: qsTr("B Button") },
            { name: "X", label: qsTr("X Button") },
            { name: "Y", label: qsTr("Y Button") },
            { name: "LeftShoulder", label: qsTr("Left Shoulder") },
            { name: "RightShoulder", label: qsTr("Right Shoulder") },
            { name: "LeftTrigger", label: qsTr("Left Trigger") },
            { name: "RightTrigger", label: qsTr("Right Trigger") },
            { name: "Back", label: qsTr("Back Button") },
            { name: "Start", label: qsTr("Start Button") },
            { name: "LeftStick", label: qsTr("Left Stick Press") },
            { name: "RightStick", label: qsTr("Right Stick Press") },
            { name: "DPadUp", label: qsTr("D-Pad Up") },
            { name: "DPadDown", label: qsTr("D-Pad Down") },
            { name: "DPadLeft", label: qsTr("D-Pad Left") },
            { name: "DPadRight", label: qsTr("D-Pad Right") }
        ]

        title: qsTr("Map %1").arg(gamepadName)
        width: 500
        height: 300
        standardButtons: Dialog.Ok | Dialog.Cancel

        function startMapping() {
            currentMappingStep = 0
            mappingResults = {}
            instructionLabel.text = qsTr("Press %1 on your gamepad").arg(mappingButtons[currentMappingStep].label)
        }

        function nextStep() {
            currentMappingStep++
            if (currentMappingStep >= mappingButtons.length) {
                // Mapping complete
                instructionLabel.text = qsTr("Mapping completed successfully!")
                mappingProgress.value = 100
                standardButton(Dialog.Ok).enabled = true
                return
            }

            instructionLabel.text = qsTr("Press %1 on your gamepad").arg(mappingButtons[currentMappingStep].label)
            mappingProgress.value = (currentMappingStep / mappingButtons.length) * 100
        }

        onOpened: {
            startMapping()
            standardButton(Dialog.Ok).enabled = false
        }

        onAccepted: {
            // Save mapping results
            console.log("Mapping completed for " + gamepadName)
            console.log(JSON.stringify(mappingResults))
            // TODO: Save to configuration file
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20

            Label {
                id: instructionLabel
                text: ""
                font.pointSize: 16
                Layout.fillWidth: true
                horizontalAlignment: Qt.AlignHCenter
            }

            ProgressBar {
                id: mappingProgress
                Layout.fillWidth: true
                value: 0
            }

            Label {
                text: qsTr("Press ESC to cancel mapping at any time")
                color: Material.hintTextColor
                font.pointSize: 12
                Layout.fillWidth: true
                horizontalAlignment: Qt.AlignHCenter
            }
        }

        // TODO: Add gamepad input handling to detect button presses
        // This requires backend support from SdlGamepadKeyNavigation
    }
}
