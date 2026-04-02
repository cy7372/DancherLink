import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

import ComputerManager 1.0
import Session 1.0

Item {
    objectName: "QuitSegue"
    property string appName
    property var quitRunningAppFn
    property Session nextSession : null
    property string nextAppName : ""

    property string stageText : qsTr("Quitting %1...").arg(appName)

    // Ensure QuitSegue fills the entire StackView content area
    anchors.fill: parent

    // Opaque background to hide the previous view
    // Use Window.window as parent to cover the entire window (including footer area)
    Rectangle {
        anchors.fill: Window.window
        color: "black"
        z: -100
    }

    function quitAppCompleted(error)
    {
        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.open()
            console.error(error)
        }

        // If we're supposed to launch another game after this, do so now
        if (error === undefined && nextSession !== null) {
            // Capture the current visibility BEFORE creating the new segue
            // so we can restore to this state after streaming ends
            var currentVisibility = Window.window.visibility

            var component = Qt.createComponent("StreamSegue.qml")
            if (component.status !== Component.Ready) {
                console.error("Failed to create StreamSegue component:", component.errorString())
                // Exit this view since we can't proceed
                stackView.pop()
                return
            }
            var segue = component.createObject(stackView, {
                "appName": nextAppName,
                "session": nextSession,
                "previousVisibility": currentVisibility
            })
            if (!segue) {
                console.error("Failed to create StreamSegue object")
                // Exit this view since we can't proceed
                stackView.pop()
                return
            }
            stackView.replace(segue)

            // StreamSegue's onActivated will handle showing fullscreen
            // We don't need to call showFullScreen() here
        }
        else {
            // Exit this view
            stackView.pop()
        }
    }

    StackView.onActivated: {
        // Use Qt.callLater to ensure the component is fully attached to the window
        Qt.callLater(function() {
            // Hide the toolbar before we start loading
            if (Window.window && Window.window.toolBar) {
                Window.window.toolBar.visible = false
            }
        })

        // Connect the quit completion signal
        ComputerManager.quitAppCompleted.connect(quitAppCompleted)

        // Start the quit operation if requested
        if (quitRunningAppFn) {
            quitRunningAppFn()
        }
    }

    StackView.onDeactivating: {
        // Show the toolbar again
        if (Window.window && Window.window.toolBar) {
            Window.window.toolBar.visible = true
        }

        // Disconnect the signal
        ComputerManager.quitAppCompleted.disconnect(quitAppCompleted)
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
            text: stageText
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.Wrap
        }
    }

    ErrorMessageDialog {
        id: errorDialog
    }
}

