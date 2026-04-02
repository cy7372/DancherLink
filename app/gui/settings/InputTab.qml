import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls.Material 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0

// =============================================================================
// Input Tab - Input device settings
// =============================================================================
// Contains:
//   - Mouse settings (absolute mode, button swapping, scroll direction)
//   - Keyboard settings (system key capture)
//   - Touchscreen settings
//   - Gamepad settings (button swapping, mouse control, background input)
// =============================================================================

ScrollView {
    id: inputTab

    // Reinitialize on language change
    function onLanguageChanged() {
        // Input settings don't have combo boxes that need reinitialization
        // All text is qsTr() based and will update automatically
    }

    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
        id: contentColumn
        width: inputTab.width - 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: AppTheme.spacingMd
        padding: AppTheme.spacingMd

        // Section: Mouse Settings
        SettingsGroupBox {
            title: qsTr("Mouse Settings")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: absoluteMouseCheck
                    hoverEnabled: true
                    width: parent.width
                    text: qsTr("Optimize mouse for remote desktop instead of games")
                    font.pointSize: AppTheme.fontBody
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

                CheckBox {
                    id: swapMouseButtonsCheck
                    hoverEnabled: true
                    width: parent.width
                    text: qsTr("Swap left and right mouse buttons")
                    font.pointSize: AppTheme.fontBody
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
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.reverseScrollDirection
                    onCheckedChanged: {
                        StreamingPreferences.reverseScrollDirection = checked
                    }
                }
            }
        }

        // Section: Keyboard Settings
        SettingsGroupBox {
            title: qsTr("Keyboard Settings")
            width: parent.width - parent.padding * 2
            visible: SystemProperties.hasDesktopEnvironment

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                Row {
                    spacing: 5
                    width: parent.width

                    CheckBox {
                        id: captureSysKeysCheck
                        hoverEnabled: true
                        text: qsTr("Capture system keyboard shortcuts")
                        font.pointSize: AppTheme.fontBody
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
            }
        }

        // Section: Touchscreen Settings
        SettingsGroupBox {
            title: qsTr("Touchscreen Settings")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: absoluteTouchCheck
                    hoverEnabled: true
                    width: parent.width
                    text: qsTr("Use touchscreen as a virtual trackpad")
                    font.pointSize: AppTheme.fontBody
                    checked: !StreamingPreferences.absoluteTouchMode
                    onCheckedChanged: {
                        StreamingPreferences.absoluteTouchMode = !checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("When checked, the touchscreen acts like a trackpad. When unchecked, the touchscreen will directly control the mouse pointer.")
                }
            }
        }

        // Section: Gamepad Settings
        SettingsGroupBox {
            title: qsTr("Gamepad Settings")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: swapFaceButtonsCheck
                    width: parent.width
                    text: qsTr("Swap A/B and X/Y gamepad buttons")
                    font.pointSize: AppTheme.fontBody
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
                    font.pointSize: AppTheme.fontBody
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
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.gamepadMouse
                    onCheckedChanged: {
                        StreamingPreferences.gamepadMouse = checked
                    }
                }

                CheckBox {
                    id: backgroundGamepadCheck
                    width: parent.width
                    text: qsTr("Process gamepad input when DancherLink is in the background")
                    font.pointSize: AppTheme.fontBody
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
    }
}
