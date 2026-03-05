import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0

SettingsGroupBox {
    id: inputSettings
    title: qsTr("Input Settings")

    Column {
        anchors.fill: parent
        spacing: 5

        CheckBox {
            id: absoluteMouseCheck
            hoverEnabled: true
            width: parent.width
            text: qsTr("Optimize mouse for remote desktop instead of games")
            font.pointSize: 12
            checked: StreamingPreferences.absoluteMouseMode
            onCheckedChanged: {
                StreamingPreferences.absoluteMouseMode = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 10000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("This enables seamless mouse control without capturing the client's mouse cursor. It is ideal for remote desktop usage but will not work in most games.") + " " +
                          qsTr("You can toggle this while streaming using Ctrl+Alt+Shift+M.") + "\n\n" +
                          qsTr("NOTE: Due to a bug in GeForce Experience, this option may not work properly if your host PC has multiple monitors.")
        }

        Row {
            spacing: 5
            width: parent.width

            CheckBox {
                id: captureSysKeysCheck
                hoverEnabled: true
                text: qsTr("Capture system keyboard shortcuts")
                font.pointSize: 12
                enabled: SystemProperties.hasDesktopEnvironment
                checked: StreamingPreferences.captureSysKeysMode !== StreamingPreferences.CSK_OFF || !SystemProperties.hasDesktopEnvironment

                ToolTip.delay: 1000
                ToolTip.timeout: 10000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("This enables the capture of system-wide keyboard shortcuts like Alt+Tab that would normally be handled by the client OS while streaming.") + "\n\n" +
                              qsTr("NOTE: Certain keyboard shortcuts like Ctrl+Alt+Del on Windows cannot be intercepted by any application, including DancherLink.")
            }

            AutoResizingComboBox {
                id: captureSysKeysComboBox

                Component.onCompleted: {
                    if (!visible) {
                        return
                    }

                    var saved_syskeysmode = StreamingPreferences.captureSysKeysMode
                    currentIndex = 0
                    for (var i = 0; i < captureSysKeysModeListModel.count; i++) {
                        var el_syskeysmode = captureSysKeysModeListModel.get(i).val;
                        if (saved_syskeysmode === el_syskeysmode) {
                            currentIndex = i
                            break
                        }
                    }

                    activated(currentIndex)
                }

                enabled: captureSysKeysCheck.checked && captureSysKeysCheck.enabled
                textRole: "text"
                model: ListModel {
                    id: captureSysKeysModeListModel
                    ListElement {
                        text: qsTr("in fullscreen")
                        val: StreamingPreferences.CSK_FULLSCREEN
                    }
                    ListElement {
                        text: qsTr("always")
                        val: StreamingPreferences.CSK_ALWAYS
                    }
                }

                function updatePref() {
                    if (!enabled) {
                        StreamingPreferences.captureSysKeysMode = StreamingPreferences.CSK_OFF
                    }
                    else {
                        StreamingPreferences.captureSysKeysMode = captureSysKeysModeListModel.get(currentIndex).val
                    }
                }

                onActivated: {
                    updatePref()
                }

                onEnabledChanged: {
                    updatePref()
                }
            }
        }

        CheckBox {
            id: absoluteTouchCheck
            hoverEnabled: true
            width: parent.width
            text: qsTr("Use touchscreen as a virtual trackpad")
            font.pointSize: 12
            checked: !StreamingPreferences.absoluteTouchMode
            onCheckedChanged: {
                StreamingPreferences.absoluteTouchMode = !checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("When checked, the touchscreen acts like a trackpad. When unchecked, the touchscreen will directly control the mouse pointer.")
        }

        CheckBox {
            id: swapMouseButtonsCheck
            hoverEnabled: true
            width: parent.width
            text: qsTr("Swap left and right mouse buttons")
            font.pointSize: 12
            checked: StreamingPreferences.swapMouseButtons
            onCheckedChanged: {
                StreamingPreferences.swapMouseButtons = checked
            }
        }

        CheckBox {
            id: reverseScrollButtonsCheck
            hoverEnabled: true
            width: parent.width
            text: qsTr("Reverse mouse scrolling direction")
            font.pointSize: 12
            checked: StreamingPreferences.reverseScrollDirection
            onCheckedChanged: {
                StreamingPreferences.reverseScrollDirection = checked
            }
        }
    }
}
