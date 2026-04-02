import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls.Material 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0

// =============================================================================
// UI Tab - User interface settings
// =============================================================================
// Contains:
//   - Language selection
//   - GUI display mode
//   - Connection quality warnings
//   - Configuration warnings
//   - Discord Rich Presence
//   - Keep display awake
// =============================================================================

ScrollView {
    id: uiTab

    signal languageChanged()

    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
        id: contentColumn
        width: uiTab.width - 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: AppTheme.spacingMd
        padding: AppTheme.spacingMd

        // Section: Language
        SettingsGroupBox {
            title: qsTr("Language")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

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
                        var new_language = languageListModel.get(currentIndex).val
                        if (StreamingPreferences.language !== new_language) {
                            StreamingPreferences.language = languageListModel.get(currentIndex).val
                            if (!StreamingPreferences.retranslate()) {
                                ToolTip.show(qsTr("You must restart DancherLink for this change to take effect"), 5000)
                            }
                            else {
                                Window.window.clearOnBack = true
                                uiTab.languageChanged()
                            }
                        }
                    }
                }
            }
        }

        // Section: Display Mode
        SettingsGroupBox {
            title: qsTr("Display Mode")
            width: parent.width - parent.padding * 2
            visible: SystemProperties.hasDesktopEnvironment

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                Label {
                    width: parent.width
                    text: qsTr("GUI display mode")
                    font.pointSize: AppTheme.fontCaption
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
            }
        }

        // Section: Notifications and Warnings
        SettingsGroupBox {
            title: qsTr("Notifications")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: connectionWarningsCheck
                    width: parent.width
                    text: qsTr("Show connection quality warnings")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.connectionWarnings
                    onCheckedChanged: {
                        StreamingPreferences.connectionWarnings = checked
                    }
                }

                CheckBox {
                    id: configurationWarningsCheck
                    width: parent.width
                    text: qsTr("Show configuration warnings")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.configurationWarnings
                    onCheckedChanged: {
                        StreamingPreferences.configurationWarnings = checked
                    }
                }
            }
        }

        // Section: Integrations
        SettingsGroupBox {
            title: qsTr("Integrations")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: discordPresenceCheck
                    width: parent.width
                    text: qsTr("Discord Rich Presence integration")
                    font.pointSize: AppTheme.fontBody
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
                    font.pointSize: AppTheme.fontBody
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
    }
}
