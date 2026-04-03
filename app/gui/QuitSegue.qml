import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

import ComputerManager 1.0
import Session 1.0
import AutoUpdateChecker 1.0

Item {
    objectName: "QuitSegue"
    property string appName
    property var quitRunningAppFn
    property Session nextSession : null
    property string nextAppName : ""

    // Track window visibility to restore after transition
    property int previousVisibility: -1

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

    function restoreWindowState() {
        if (!Window.window) {
            return
        }

        // We only do this if the window isn't minimized, to avoid restoring
        // a window that the user explicitly minimized during the stream.
        if (Window.window.visibility !== Window.Minimized) {
            // Apply the desired window state based on previous visibility
            var targetVisibility = Window.Windowed

            if (previousVisibility === Window.Maximized) {
                targetVisibility = Window.Maximized
            } else if (previousVisibility === Window.FullScreen) {
                targetVisibility = Window.FullScreen
            }
            // For Windowed or -1 (not set), default to Windowed

            if (targetVisibility === Window.Maximized) {
                Window.window.showMaximized()
            } else if (targetVisibility === Window.FullScreen) {
                Window.window.showFullScreen()
            } else {
                Window.window.showNormal()
            }
        }
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
            var component = Qt.createComponent("StreamSegue.qml")
            if (component.status !== Component.Ready) {
                console.error("Failed to create StreamSegue component:", component.errorString())
                // Exit this view since we can't proceed
                stackView.pop()
                return
            }
            // Pass the previousVisibility so StreamSegue can restore the correct window state
            var segue = component.createObject(stackView, {
                "appName": nextAppName,
                "session": nextSession,
                "previousVisibility": previousVisibility
            })
            if (!segue) {
                console.error("Failed to create StreamSegue object")
                // Exit this view since we can't proceed
                stackView.pop()
                return
            }
            stackView.replace(segue)

            // StreamSegue is already fullscreen (we captured previousVisibility above)
            // StreamSegue's onActivated will keep fullscreen, so no need to change state
        }
        else {
            // No next session - restore window state before popping
            restoreWindowState()

            // CRITICAL: Check for updates after user manually quits streaming
            // This ensures users are notified of new versions after they finish gaming
            console.log("Stream session ended - checking for updates")
            AutoUpdateChecker.start(false)

            // Exit this view
            stackView.pop()
        }
    }

    StackView.onActivated: {
        // Use Qt.callLater to ensure the component is fully attached to the window
        Qt.callLater(function() {
            // Capture window state before going fullscreen
            if (Window.window) {
                previousVisibility = Window.window.visibility
            }

            // Hide the toolbar before we start loading
            if (Window.window && Window.window.toolBar) {
                Window.window.toolBar.visible = false
            }

            // CRITICAL: Show fullscreen to cover taskbar during transition
            // This ensures the transition screen covers the entire screen, even if
            // the user's windowed mode doesn't cover the taskbar.
            if (Window.window) {
                Window.window.showFullScreen()
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

