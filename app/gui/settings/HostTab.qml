import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls.Material 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0
import ComputerManager 1.0
import AutoUpdateChecker 1.0

// =============================================================================
// Host Tab - Host and network settings
// =============================================================================
// Contains:
//   - Host optimization settings
//   - Automatic app quitting
//   - Network discovery (mDNS)
//   - Connection blocking detection
//   - Update settings
// =============================================================================

ScrollView {
    id: hostTab

    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
        id: contentColumn
        width: hostTab.width - 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: AppTheme.spacingMd
        padding: AppTheme.spacingMd

        // Section: Host Settings
        SettingsGroupBox {
            title: qsTr("Host Settings")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: optimizeGameSettingsCheck
                    text: qsTr("Optimize game settings for streaming")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.gameOptimizations
                    onCheckedChanged: {
                        StreamingPreferences.gameOptimizations = checked
                    }
                }

                CheckBox {
                    id: quitAppAfter
                    width: parent.width
                    text: qsTr("Quit app on host PC after ending stream")
                    font.pointSize: AppTheme.fontBody
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

        // Section: Network Discovery
        SettingsGroupBox {
            title: qsTr("Network Discovery")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: enableMdns
                    width: parent.width
                    text: qsTr("Automatically find PCs on the local network (Recommended)")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.enableMdns
                    onCheckedChanged: {
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
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.detectNetworkBlocking
                    onCheckedChanged: {
                        StreamingPreferences.detectNetworkBlocking = checked
                    }
                }
            }
        }

        // Section: Update Settings
        SettingsGroupBox {
            title: qsTr("Update Settings")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                Label {
                    text: qsTr("Subscription URL")
                    font.pointSize: AppTheme.fontCaption
                    wrapMode: Text.Wrap
                }

                Label {
                    width: parent.width
                    text: qsTr("Enter the URL to check for updates.")
                    font.pointSize: AppTheme.fontSmall
                    wrapMode: Text.Wrap
                    color: Material.hintTextColor
                }

                TextField {
                    id: subscriptionUrlField
                    width: parent.width
                    placeholderText: "https://example.com/updates.json"
                    text: StreamingPreferences.updateSubscriptionUrl

                    onTextEdited: {
                        StreamingPreferences.updateSubscriptionUrl = text
                    }
                }

                Button {
                    text: qsTr("Check for Updates Now")
                    onClicked: {
                        if (subscriptionUrlField.text !== StreamingPreferences.updateSubscriptionUrl) {
                            StreamingPreferences.updateSubscriptionUrl = subscriptionUrlField.text
                        }
                        AutoUpdateChecker.start(true)
                    }
                }
            }
        }
    }
}
