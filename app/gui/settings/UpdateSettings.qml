import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

import ".."

import StreamingPreferences 1.0
import AutoUpdateChecker 1.0

SettingsGroupBox {
    id: updateSettings
    title: qsTr("Update Settings")

    Column {
        anchors.fill: parent
        spacing: 5

        Label {
            width: parent.width
            text: qsTr("Subscription URL")
            font.pointSize: 12
            wrapMode: Text.Wrap
        }

        Label {
            width: parent.width
            text: qsTr("Enter the URL to check for updates.")
            font.pointSize: 9
            wrapMode: Text.Wrap
            color: Material.hintTextColor
        }

        TextField {
            id: subscriptionUrlField
            width: parent.width
            placeholderText: "https://example.com/updates.json"
            text: StreamingPreferences.updateSubscriptionUrl

            // Use onTextEdited instead of onEditingFinished to update the model in real-time
            // This prevents the case where clicking the button steals focus and the
            // onEditingFinished signal fires AFTER the onClicked handler reads the old value.
            onTextEdited: {
                StreamingPreferences.updateSubscriptionUrl = text
            }
        }

        Button {
            text: qsTr("Check for Updates Now")
            onClicked: {
                // Ensure preference is updated before checking
                // The onTextEdited handler already updates the preference, but we do this for safety
                // in case the user pasted and clicked immediately without triggering onTextEdited somehow (unlikely but safe)
                if (subscriptionUrlField.text !== StreamingPreferences.updateSubscriptionUrl) {
                    StreamingPreferences.updateSubscriptionUrl = subscriptionUrlField.text
                }

                console.log("UpdateSettings: Check for updates clicked. URL: " + StreamingPreferences.updateSubscriptionUrl)
                AutoUpdateChecker.start(true)
            }
        }
    }
}
