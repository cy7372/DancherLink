import QtQuick 2.15
import QtQuick.Controls 2.15

import ComputerManager 1.0

Item {
    function onSearchingComputer() {
        stageLabel.text = qsTr("Establishing connection to PC...")
    }

    function onSearchingApp() {
        stageLabel.text = qsTr("Loading app list...")
    }

    function onSessionCreated(appName, session) {
        var component = Qt.createComponent("StreamSegue.qml")
        if (component.status !== Component.Ready) {
            console.error("Failed to create StreamSegue component:", component.errorString())
            onLaunchFailed("Failed to create stream view: " + component.errorString())
            return
        }
        var segue = component.createObject(stackView, {
            "appName": appName,
            "session": session,
            "quitAfter": true,
            "previousVisibility": window.visibility
        })
        if (!segue) {
            console.error("Failed to create StreamSegue object")
            onLaunchFailed("Failed to create stream view")
            return
        }
        stackView.push(segue)
    }

    function onLaunchFailed(message) {
        errorDialog.text = message
        errorDialog.open()
        console.error(message)
    }

    function onAppQuitRequired(appName) {
        quitAppDialog.appName = appName
        quitAppDialog.open()
    }

    StackView.onActivated: {
        if (!launcher.isExecuted()) {
            toolBar.visible = false

            // Connect signals
            launcher.searchingComputer.connect(onSearchingComputer)
            launcher.searchingApp.connect(onSearchingApp)
            launcher.sessionCreated.connect(onSessionCreated)
            launcher.failed.connect(onLaunchFailed)
            launcher.appQuitRequired.connect(onAppQuitRequired)
            launcher.execute(ComputerManager)
        }
    }

    StackView.onDeactivating: {
        // Disconnect signals to prevent memory leaks and duplicate triggers
        launcher.searchingComputer.disconnect(onSearchingComputer)
        launcher.searchingApp.disconnect(onSearchingApp)
        launcher.sessionCreated.disconnect(onSessionCreated)
        launcher.failed.disconnect(onLaunchFailed)
        launcher.appQuitRequired.disconnect(onAppQuitRequired)
    }

    Row {
        anchors.centerIn: parent
        spacing: 5

        BusyIndicator {
            id: stageSpinner
            running: visible
        }

        Label {
            id: stageLabel
            height: stageSpinner.height
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.Wrap
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        onClosed: {
            Qt.quit();
        }
    }

    NavigableMessageDialog {
        id: quitAppDialog
        text:qsTr("Are you sure you want to quit %1? Any unsaved progress will be lost.").arg(appName)
        standardButtons: Dialog.Yes | Dialog.No
        property string appName : ""

        function quitApp() {
            var component = Qt.createComponent("QuitSegue.qml")
            if (component.status !== Component.Ready) {
                console.error("Failed to create QuitSegue component:", component.errorString())
                return
            }
            var params = {"appName": appName, "quitRunningAppFn": function() { launcher.quitRunningApp() }}
            var segue = component.createObject(stackView, params)
            if (!segue) {
                console.error("Failed to create QuitSegue object")
                return
            }
            stackView.push(segue)
        }

        onAccepted: quitApp()
        onRejected: Qt.quit()
    }
}

