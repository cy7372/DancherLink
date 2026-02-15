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
                            // TODO: Implement actual mapping dialog
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
}
