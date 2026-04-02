import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0
import ComputerManager 1.0

SettingsGroupBox {
    id: advancedSettings
    title: qsTr("Advanced Settings")

    // Properties for cross-component communication with BasicSettings
    property var resolutionListModel: null
    property var resolutionComboBox: null
    property var bitrateSlider: null

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 5

        Label {
            text: qsTr("Video decoder")
            font.pointSize: 12
            wrapMode: Text.Wrap
        }

        AutoResizingComboBox {
            id: decoderComboBox
            textRole: "text"

            Component.onCompleted: {
                var saved_vds = StreamingPreferences.videoDecoderSelection
                currentIndex = 0
                for (var i = 0; i < decoderListModel.count; i++) {
                    var el_vds = decoderListModel.get(i).val;
                    if (saved_vds === el_vds) {
                        currentIndex = i
                        break
                    }
                }
                activated(currentIndex)
            }

            model: ListModel {
                id: decoderListModel
                ListElement {
                    text: qsTr("Automatic (Recommended)")
                    val: StreamingPreferences.VDS_AUTO
                }
                ListElement {
                    text: qsTr("Force software decoding")
                    val: StreamingPreferences.VDS_FORCE_SOFTWARE
                }
                ListElement {
                    text: qsTr("Force hardware decoding")
                    val: StreamingPreferences.VDS_FORCE_HARDWARE
                }
            }

            onActivated: {
                if (enabled) {
                    StreamingPreferences.videoDecoderSelection = decoderListModel.get(currentIndex).val
                }
            }
        }

        Label {
            width: parent.width
            text: qsTr("Video codec")
            font.pointSize: 12
            wrapMode: Text.Wrap
        }

        AutoResizingComboBox {
            id: codecComboBox
            textRole: "text"

            Component.onCompleted: {
                var saved_vcc = StreamingPreferences.videoCodecConfig

                // Default to Automatic (relevant if HDR is enabled,
                // where we will match none of the codecs in the list)
                currentIndex = 0

                for (var i = 0; i < codecListModel.count; i++) {
                    var el_vcc = codecListModel.get(i).val;
                    if (saved_vcc === el_vcc) {
                        currentIndex = i
                        break
                    }
                }

                activated(currentIndex)
            }

            model: ListModel {
                id: codecListModel
                ListElement {
                    text: qsTr("Automatic (Recommended)")
                    val: StreamingPreferences.VCC_AUTO
                }
                ListElement {
                    text: qsTr("H.264")
                    val: StreamingPreferences.VCC_FORCE_H264
                }
                ListElement {
                    text: qsTr("HEVC (H.265)")
                    val: StreamingPreferences.VCC_FORCE_HEVC
                }
                ListElement {
                    text: qsTr("AV1 (Experimental)")
                    val: StreamingPreferences.VCC_FORCE_AV1
                }
            }

            onActivated: {
                if (enabled) {
                    StreamingPreferences.videoCodecConfig = codecListModel.get(currentIndex).val
                }
            }
        }

        CheckBox {
            id: enableHdr
            width: parent.width
            text: qsTr("Enable HDR (Experimental)")
            font.pointSize: 12

            enabled: SystemProperties.supportsHdr
            checked: enabled && StreamingPreferences.enableHdr
            onCheckedChanged: {
                StreamingPreferences.enableHdr = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: enabled ?
                              qsTr("The stream will be HDR-capable, but some games may require an HDR monitor on your host PC to enable HDR mode.")
                            :
                              qsTr("HDR streaming is not supported on this PC.")
        }

        CheckBox {
            id: enableYUV444
            width: parent.width
            text: qsTr("Enable YUV 4:4:4 (Experimental)")
            font.pointSize: 12

            checked: StreamingPreferences.enableYUV444
            onCheckedChanged: {
                // This is called on init, so only reset to default bitrate when checked state changes.
                if (StreamingPreferences.enableYUV444 != checked) {
                    StreamingPreferences.enableYUV444 = checked
                    if (StreamingPreferences.autoAdjustBitrate && advancedSettings.bitrateSlider) {
                        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(StreamingPreferences.width,
                                                                                                  StreamingPreferences.height,
                                                                                                  StreamingPreferences.fps,
                                                                                                  StreamingPreferences.enableYUV444);
                        advancedSettings.bitrateSlider.value = StreamingPreferences.bitrateKbps
                    }
                }
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: enabled ?
                              qsTr("Good for streaming desktop and text-heavy games, but not recommended for fast-paced games.")
                            :
                              qsTr("YUV 4:4:4 is not supported on this PC.")
        }

        CheckBox {
            id: unlockBitrate
            width: parent.width
            text: qsTr("Unlock bitrate limit (Experimental)")
            font.pointSize: 12

            checked: StreamingPreferences.unlockBitrate
            onCheckedChanged: {
                StreamingPreferences.unlockBitrate = checked
                StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, advancedSettings.bitrateSlider ? advancedSettings.bitrateSlider.to : 100000)
                if (advancedSettings.bitrateSlider) {
                    advancedSettings.bitrateSlider.value = StreamingPreferences.bitrateKbps
                }
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("This unlocks extremely high video bitrates for use with Sunshine hosts. It should only be used when streaming over an Ethernet LAN connection.")
        }

        CheckBox {
            id: enableMdns
            width: parent.width
            text: qsTr("Automatically find PCs on the local network (Recommended)")
            font.pointSize: 12
            checked: StreamingPreferences.enableMdns
            onCheckedChanged: {
                // This is called on init, so only do the work if we've
                // actually changed the value.
                if (StreamingPreferences.enableMdns != checked) {
                    StreamingPreferences.enableMdns = checked

                    // Restart polling so the mDNS change takes effect
                    if (Window.window.pollingActive) {
                        ComputerManager.stopPollingAsync()
                        ComputerManager.startPolling()
                    }
                }
            }
        }

        CheckBox {
            id: detectNetworkBlocking
            width: parent.width
            text: qsTr("Automatically detect blocked connections (Recommended)")
            font.pointSize: 12
            checked: StreamingPreferences.detectNetworkBlocking
            onCheckedChanged: {
                StreamingPreferences.detectNetworkBlocking = checked
            }
        }

        CheckBox {
            id: showPerformanceOverlay
            width: parent.width
            text: qsTr("Show performance stats while streaming")
            font.pointSize: 12
            checked: StreamingPreferences.showPerformanceOverlay
            onCheckedChanged: {
                StreamingPreferences.showPerformanceOverlay = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Display real-time stream performance information while streaming.") + "\n\n" +
                          qsTr("You can toggle it at any time while streaming using Ctrl+Alt+Shift+S or Select+L1+R1+X.") + "\n\n" +
                          qsTr("The performance overlay is not supported on Steam Link or Raspberry Pi.")
        }

        CheckBox {
            id: quitOnDisplaySleepCheck
            width: parent.width
            text: qsTr("Quit stream on display sleep")
            font.pointSize: 12
            visible: SystemProperties.hasDesktopEnvironment
            checked: StreamingPreferences.quitOnDisplaySleep
            onCheckedChanged: {
                StreamingPreferences.quitOnDisplaySleep = checked
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Automatically quits the stream when the client display goes to sleep or is turned off.")
        }

        CheckBox {
            id: detectResolutionChangeCheck
            width: parent.width
            text: qsTr("Automatically adapt to screen resolution changes")
            font.pointSize: 12
            // This option is only valid when using "Auto" resolution (0x0).
            // If a fixed resolution is selected, we shouldn't prompt the user to change it.
            enabled: Qt.binding(function() {
                if (!advancedSettings.resolutionListModel || !advancedSettings.resolutionComboBox) {
                    // Default to disabled when properties are not initialized yet
                    return false
                }
                return advancedSettings.resolutionListModel.get(advancedSettings.resolutionComboBox.currentIndex).video_width === "0"
            })
            checked: enabled && StreamingPreferences.detectResolutionChange
            onCheckedChanged: {
                if (enabled) {
                    StreamingPreferences.detectResolutionChange = checked
                }
            }

            // Update enabled state when resolution combo box changes
            Connections {
                target: advancedSettings.resolutionComboBox
                function onCurrentIndexChanged() {
                    // Force re-evaluation of enabled binding
                    detectResolutionChangeCheck.enabled = Qt.binding(function() {
                        if (!advancedSettings.resolutionListModel || !advancedSettings.resolutionComboBox) {
                            return false
                        }
                        return advancedSettings.resolutionListModel.get(advancedSettings.resolutionComboBox.currentIndex).video_width === "0"
                    })
                }
            }

            // Update when resolutionListModel is assigned
            Connections {
                target: advancedSettings
                function onResolutionListModelChanged() {
                    // Force re-evaluation of enabled binding
                    detectResolutionChangeCheck.enabled = Qt.binding(function() {
                        if (!advancedSettings.resolutionListModel || !advancedSettings.resolutionComboBox) {
                            return false
                        }
                        return advancedSettings.resolutionListModel.get(advancedSettings.resolutionComboBox.currentIndex).video_width === "0"
                    })
                }
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Prompts to quit and reconnect when the client display resolution changes.")
        }

        CheckBox {
            id: showResolutionChangeDialogCheck
            width: parent.width
            text: qsTr("Show confirmation dialog on resolution change")
            font.pointSize: 12
            enabled: detectResolutionChangeCheck.enabled && detectResolutionChangeCheck.checked
            checked: enabled && StreamingPreferences.showResolutionChangeDialog
            onCheckedChanged: {
                if (enabled) {
                    StreamingPreferences.showResolutionChangeDialog = checked
                }
            }

            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: hovered
            ToolTip.text: qsTr("When unchecked, the stream will restart automatically without prompting.")
        }
    }
}
