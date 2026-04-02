import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls.Material 2.15

import ".."

import StreamingPreferences 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import AutoUpdateChecker 1.0

// =============================================================================
// Settings Window with Tabbed Interface
// =============================================================================
// Organizes settings into 5 tabs:
//   - Video: Resolution, FPS, bitrate, decoder, codec, HDR, etc.
//   - Audio: Audio configuration, microphone, mute on focus loss
//   - Input: Mouse, keyboard, touchscreen, gamepad settings
//   - Host: Host optimizations, update settings, network discovery
//   - Interface: Language, UI mode, warnings, Discord integration
// =============================================================================

Page {
    id: settingsWindow

    Component.onDestruction: {
        StreamingPreferences.save()
    }
    objectName: qsTr("Settings")

    signal languageChanged()

    background: Rectangle {
        color: Material.background
    }

    StackView.onActivated: {
        SdlGamepadKeyNavigation.setUiNavMode(true)
    }

    StackView.onDeactivating: {
        SdlGamepadKeyNavigation.setUiNavMode(false)
        StreamingPreferences.save()
    }

    // Shared properties for cross-tab communication
    property var resolutionListModel: null
    property var resolutionComboBox: null
    property var bitrateSlider: null

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Tab Bar
        TabBar {
            id: tabBar
            Layout.fillWidth: true

            TabButton {
                text: qsTr("Video")
                font.pointSize: AppTheme.fontBody
            }
            TabButton {
                text: qsTr("Audio")
                font.pointSize: AppTheme.fontBody
            }
            TabButton {
                text: qsTr("Input")
                font.pointSize: AppTheme.fontBody
            }
            TabButton {
                text: qsTr("Host")
                font.pointSize: AppTheme.fontBody
            }
            TabButton {
                text: qsTr("Interface")
                font.pointSize: AppTheme.fontBody
            }
        }

        // Tab Content
        StackLayout {
            id: tabStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // Tab 1: Video
            VideoTab {
                id: videoTab
                onResolutionModelReady: {
                    settingsWindow.resolutionListModel = videoTab.resolutionListModel
                    settingsWindow.resolutionComboBox = videoTab.resolutionComboBox
                    settingsWindow.bitrateSlider = videoTab.bitrateSlider
                }
            }

            // Tab 2: Audio
            AudioTab {
                id: audioTab
            }

            // Tab 3: Input
            InputTab {
                id: inputTab
            }

            // Tab 4: Host
            HostTab {
                id: hostTab
            }

            // Tab 5: Interface
            UITab {
                id: uiTab
                onLanguageChanged: settingsWindow.languageChanged()
            }
        }
    }
}
