import QtQuick 2.15
import QtQuick.Controls 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0

SettingsGroupBox {
    id: gamepadSettings
    title: qsTr("Gamepad Settings")

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 5

        CheckBox {
            id: swapFaceButtonsCheck
            text: qsTr("Swap A/B and X/Y gamepad buttons")
            font.pointSize: 12
            checked: StreamingPreferences.swapFaceButtons
            onCheckedChanged: {
                StreamingPreferences.swapFaceButtons = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("This switches gamepads into a Nintendo-style button layout")
        }

        CheckBox {
            id: singleControllerCheck
            width: parent.width
            text: qsTr("Force gamepad #1 always connected")
            font.pointSize: 12
            checked: !StreamingPreferences.multiController
            onCheckedChanged: {
                StreamingPreferences.multiController = !checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Forces a single gamepad to always stay connected to the host, even if no gamepads are actually connected to this PC.") + " " +
                          qsTr("Only enable this option when streaming a game that doesn't support gamepads being connected after startup.")
        }

        CheckBox {
            id: gamepadMouseCheck
            hoverEnabled: true
            width: parent.width
            text: qsTr("Enable mouse control with gamepads by holding the 'Start' button")
            font.pointSize: 12
            checked: StreamingPreferences.gamepadMouse
            onCheckedChanged: {
                StreamingPreferences.gamepadMouse = checked
            }
        }

        CheckBox {
            id: backgroundGamepadCheck
            width: parent.width
            text: qsTr("Process gamepad input when DancherLink is in the background")
            font.pointSize: 12
            visible: SystemProperties.hasDesktopEnvironment
            checked: StreamingPreferences.backgroundGamepad
            onCheckedChanged: {
                StreamingPreferences.backgroundGamepad = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Allows DancherLink to capture gamepad inputs even if it's not the current window in focus")
        }
    }
}
