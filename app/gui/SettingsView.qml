import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls.Material 2.15

import "."
import "settings"

import StreamingPreferences 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import AutoUpdateChecker 1.0

// =============================================================================
// Settings View - Tabbed Interface
// =============================================================================
// Organizes settings into 5 tabs:
//   - Video: Resolution, FPS, bitrate, decoder, codec, HDR, etc.
//   - Audio: Audio configuration, microphone, mute on focus loss
//   - Input: Mouse, keyboard, touchscreen, gamepad settings
//   - Host: Host optimizations, update settings, network discovery
//   - Interface: Language, UI mode, warnings, Discord integration
// =============================================================================

Page {
    id: settingsPage

    Component.onDestruction: {
        StreamingPreferences.save()
    }
    objectName: qsTr("Settings")

    signal languageChanged()

    // Handle language change - notify all tabs to reinitialize
    onLanguageChanged: {
        videoTab.onLanguageChanged()
        audioTab.onLanguageChanged()
        inputTab.onLanguageChanged()
        hostTab.onLanguageChanged()
    }

    background: Rectangle {
        color: Material.background
    }

    StackView.onActivated: {
        SdlGamepadKeyNavigation.setUiNavMode(true)
        // Focus the resolution combo box if gamepads are connected
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0 && videoTab.resolutionComboBox) {
            videoTab.resolutionComboBox.forceActiveFocus(Qt.TabFocus)
        }
    }

    StackView.onDeactivating: {
        SdlGamepadKeyNavigation.setUiNavMode(false)
        StreamingPreferences.save()
    }

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

        // Divider line between tabs and content
        Rectangle {
            Layout.fillWidth: true
            height: 2
            color: Material.hintTextColor
            opacity: 0.3
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
                onLanguageChanged: settingsPage.languageChanged()
            }
        }
    }
}
