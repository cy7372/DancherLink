import QtQuick 2.15
import QtQuick.Controls 2.15

import ".."

import StreamingPreferences 1.0

SettingsGroupBox {
    id: hostSettings
    title: qsTr("Host Settings")

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 5

        CheckBox {
            id: optimizeGameSettingsCheck
            text: qsTr("Optimize game settings for streaming")
            font.pointSize: 12
            checked: StreamingPreferences.gameOptimizations
            onCheckedChanged: {
                StreamingPreferences.gameOptimizations = checked
            }
        }

        CheckBox {
            id: quitAppAfter
            width: parent.width
            text: qsTr("Quit app on host PC after ending stream")
            font.pointSize: 12
            checked: StreamingPreferences.quitAppAfter
            onCheckedChanged: {
                StreamingPreferences.quitAppAfter = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("This will close the app or game you are streaming when you end your stream. You will lose any unsaved progress!")
        }
    }
}
