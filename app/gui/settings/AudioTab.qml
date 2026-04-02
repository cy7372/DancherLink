import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls.Material 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0

// =============================================================================
// Audio Tab - Audio streaming settings
// =============================================================================
// Contains:
//   - Audio configuration (stereo, surround sound)
//   - Host PC speaker muting
//   - Microphone recording
//   - Mute on focus loss
// =============================================================================

ScrollView {
    id: audioTab

    // Reinitialize on language change
    function retranslate() {
        // Refresh audio config model
        audioListModel.setProperty(0, "text", qsTr("Stereo"))
        audioListModel.setProperty(1, "text", qsTr("5.1 surround sound"))
        audioListModel.setProperty(2, "text", qsTr("7.1 surround sound"))

        // Reinitialize combo box to update current index
        var saved_audio = StreamingPreferences.audioConfig
        for (var i = 0; i < audioListModel.count; i++) {
            var el_audio = audioListModel.get(i).val;
            if (saved_audio === el_audio) {
                audioComboBox.currentIndex = i
                break
            }
        }
    }

    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
        id: contentColumn
        width: audioTab.width - 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: AppTheme.spacingMd
        padding: AppTheme.spacingMd

        // Section: Audio Configuration
        SettingsGroupBox {
            title: qsTr("Audio Configuration")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                Label {
                    text: qsTr("Audio output mode")
                    font.pointSize: AppTheme.fontCaption
                    wrapMode: Text.Wrap
                }

                AutoResizingComboBox {
                    id: audioComboBox
                    textRole: "text"

                    Component.onCompleted: {
                        var saved_audio = StreamingPreferences.audioConfig
                        currentIndex = 0
                        for (var i = 0; i < audioListModel.count; i++) {
                            var el_audio = audioListModel.get(i).val;
                            if (saved_audio === el_audio) {
                                currentIndex = i
                                break
                            }
                        }
                        activated(currentIndex)
                    }

                    model: ListModel {
                        id: audioListModel
                        ListElement {
                            text: qsTr("Stereo")
                            val: StreamingPreferences.AC_STEREO
                        }
                        ListElement {
                            text: qsTr("5.1 surround sound")
                            val: StreamingPreferences.AC_51_SURROUND
                        }
                        ListElement {
                            text: qsTr("7.1 surround sound")
                            val: StreamingPreferences.AC_71_SURROUND
                        }
                    }

                    onActivated: {
                        StreamingPreferences.audioConfig = audioListModel.get(currentIndex).val
                    }
                }

                CheckBox {
                    id: audioPcCheck
                    width: parent.width
                    text: qsTr("Mute host PC speakers while streaming")
                    font.pointSize: AppTheme.fontBody
                    checked: !StreamingPreferences.playAudioOnHost
                    onCheckedChanged: {
                        StreamingPreferences.playAudioOnHost = !checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("You must restart any game currently in progress for this setting to take effect")
                }

                CheckBox {
                    id: enableMicrophoneCheck
                    width: parent.width
                    text: qsTr("Enable microphone recording")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.enableMicrophone
                    onCheckedChanged: {
                        StreamingPreferences.enableMicrophone = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Enable microphone recording during the stream.")
                }

                CheckBox {
                    id: muteOnFocusLossCheck
                    width: parent.width
                    text: qsTr("Mute audio stream when DancherLink is not the active window")
                    font.pointSize: AppTheme.fontBody
                    visible: SystemProperties.hasDesktopEnvironment
                    checked: StreamingPreferences.muteOnFocusLoss
                    onCheckedChanged: {
                        StreamingPreferences.muteOnFocusLoss = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Mutes Moonlight's audio when you Alt+Tab out of the stream or click on a different window.")
                }
            }
        }
    }
}
