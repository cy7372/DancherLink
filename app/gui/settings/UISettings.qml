import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Window 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0

SettingsGroupBox {
    id: uiSettings
    title: qsTr("UI Settings")

    signal languageChanged()

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 5

        Label {
            text: qsTr("Language")
            font.pointSize: 12
            wrapMode: Text.Wrap
        }

        AutoResizingComboBox {
            id: languageComboBox
            textRole: "text"

            Component.onCompleted: {
                var saved_language = StreamingPreferences.language
                currentIndex = 0
                for (var i = 0; i < languageListModel.count; i++) {
                    var el_language = languageListModel.get(i).val;
                    if (saved_language === el_language) {
                        currentIndex = i
                        break
                    }
                }

                activated(currentIndex)
            }

            model: ListModel {
                id: languageListModel
                ListElement {
                    text: qsTr("Automatic")
                    val: StreamingPreferences.LANG_AUTO
                }
                ListElement {
                    text: "English"
                    val: StreamingPreferences.LANG_EN
                }
                ListElement {
                    text: "简体中文" // Simplified Chinese
                    val: StreamingPreferences.LANG_ZH_CN
                }
            }

            onActivated: {
                // Retranslating is expensive, so only do it if the language actually changed
                var new_language = languageListModel.get(currentIndex).val
                if (StreamingPreferences.language !== new_language) {
                    StreamingPreferences.language = languageListModel.get(currentIndex).val
                    if (!StreamingPreferences.retranslate()) {
                        ToolTip.show(qsTr("You must restart DancherLink for this change to take effect"), 5000)
                    }
                    else {
                        // Force the back operation to pop any AppView pages that exist.
                        // The AppView stops working after retranslate() for some reason.
                        Window.window.clearOnBack = true

                        // Signal other controls to adjust their text
                        uiSettings.languageChanged()
                    }
                }
            }
        }

        Label {
            width: parent.width
            text: qsTr("GUI display mode")
            font.pointSize: 12
            wrapMode: Text.Wrap
            visible: SystemProperties.hasDesktopEnvironment
        }

        AutoResizingComboBox {
            id: uiDisplayModeComboBox
            visible: SystemProperties.hasDesktopEnvironment
            textRole: "text"

            Component.onCompleted: {
                if (!visible) {
                    return
                }

                var saved_uidisplaymode = StreamingPreferences.uiDisplayMode
                currentIndex = 0
                for (var i = 0; i < uiDisplayModeListModel.count; i++) {
                    var el_uidisplaymode = uiDisplayModeListModel.get(i).val;
                    if (saved_uidisplaymode === el_uidisplaymode) {
                        currentIndex = i
                        break
                    }
                }

                activated(currentIndex)
            }

            model: ListModel {
                id: uiDisplayModeListModel
                ListElement {
                    text: qsTr("Windowed")
                    val: StreamingPreferences.UI_WINDOWED
                }
                ListElement {
                    text: qsTr("Maximized")
                    val: StreamingPreferences.UI_MAXIMIZED
                }
                ListElement {
                    text: qsTr("Fullscreen")
                    val: StreamingPreferences.UI_FULLSCREEN
                }
            }

            onActivated: {
                StreamingPreferences.uiDisplayMode = uiDisplayModeListModel.get(currentIndex).val
                StreamingPreferences.save()
            }
        }

        CheckBox {
            id: connectionWarningsCheck
            width: parent.width
            text: qsTr("Show connection quality warnings")
            font.pointSize: 12
            checked: StreamingPreferences.connectionWarnings
            onCheckedChanged: {
                StreamingPreferences.connectionWarnings = checked
            }
        }

        CheckBox {
            id: configurationWarningsCheck
            width: parent.width
            text: qsTr("Show configuration warnings")
            font.pointSize: 12
            checked: StreamingPreferences.configurationWarnings
            onCheckedChanged: {
                StreamingPreferences.configurationWarnings = checked
            }
        }

        CheckBox {
            id: discordPresenceCheck
            width: parent.width
            text: qsTr("Discord Rich Presence integration")
            font.pointSize: 12
            visible: SystemProperties.hasDiscordIntegration
            checked: StreamingPreferences.richPresence
            onCheckedChanged: {
                StreamingPreferences.richPresence = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Updates your Discord status to display the name of the game you're streaming.")
        }

        CheckBox {
            id: keepAwakeCheck
            width: parent.width
            text: qsTr("Keep the display awake while streaming")
            font.pointSize: 12
            checked: StreamingPreferences.keepAwake
            onCheckedChanged: {
                StreamingPreferences.keepAwake = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Prevents the screensaver from starting or the display from going to sleep while streaming.")
        }
    }
}
