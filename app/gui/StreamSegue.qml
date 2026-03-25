import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

import "."

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import StreamingPreferences 1.0

Item {
    property Session session
    property string appName
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false

    // Opaque background to hide the previous view
    Rectangle {
        anchors.fill: parent
        color: "black"
        z: -100
    }

    signal restartRequested()

    // Use -1 as default to indicate "not explicitly set"
    // When explicitly passed (e.g., from QuitSegue), this won't be overwritten
    property int previousVisibility: -1

    onRestartRequested: {
        // Reset the UI state to show we are working
        window.show()

        // Always show the splash screen in fullscreen mode
        window.showFullScreen()
    }

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        errorDialog.text = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)

        if (failingPorts) {
            errorDialog.text += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function connectionStarted()
    {
        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        stageSpinner.visible = false
        stageLabel.visible = false
        hintText.visible = false

        // Hide the window now that streaming has begun.
        // Note: The Qt window is set to WS_EX_TOOLWINDOW style in Session::startConnectionAsync()
        // before this signal is emitted. This prevents Windows from restoring the hidden window
        // when the user presses keys during streaming. The style is restored after streaming ends.
        window.hide()
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        errorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        if (component.status !== Component.Ready) {
            console.error("Failed to create QuitSegue component:", component.errorString())
            return
        }
        var segue = component.createObject(stackView, {"appName": appName})
        if (!segue) {
            console.error("Failed to create QuitSegue object")
            return
        }
        stackView.replace(stackView.currentItem, segue, StackView.Immediate)

        // Show the Qt window again to show quit segue.
        // Use showNormal() to ensure the window is in a known state.
        window.showNormal()
    }

    function sessionFinished(portTestResult)
    {
        if (portTestResult !== 0 && portTestResult !== -1 && errorDialog.text) {
            errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking DancherLink. Streaming over the Internet may not work while connected to this network.")
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        if (quitAfter && !errorDialog.text) {
            // If this was a CLI launch without errors, exit now
            Qt.quit()
        }
        else if (errorDialog.text) {
            // Restore window state and show the Qt window again after streaming
            // Do NOT call window.show() before restoreWindowState() - the restore
            // function handles showing the window itself.
            restoreWindowState()

            // Brief delay to let the layout engine settle before showing the dialog,
            // avoiding rendering glitches when the window reappears after streaming.
            errorDialogTimer.start()
        }
        else {
            // No error, just pop back
            restoreWindowState()
            stackView.pop()
        }
    }

    function restoreWindowState() {
        console.log("StreamSegue: restoreWindowState() called, previousVisibility =", previousVisibility,
                    ", current window.visibility =", window.visibility,
                    ", uiDisplayMode =", StreamingPreferences.uiDisplayMode)

        // We only do this if the window isn't minimized, to avoid restoring
        // a window that the user explicitly minimized during the stream.
        if (window.visibility !== Window.Minimized) {
            // Restore window style first (Windows only)
            if (session) {
                session.restoreWindowStyle()
            }

            // Apply the desired window state based on previous visibility or preferences
            var targetVisibility = Window.Windowed

            // Treat -1 (not set) as Windowed
            if (previousVisibility === Window.Maximized) {
                targetVisibility = Window.Maximized
            } else if (previousVisibility === Window.FullScreen) {
                targetVisibility = Window.FullScreen
            } else if (StreamingPreferences.uiDisplayMode === StreamingPreferences.UI_MAXIMIZED) {
                targetVisibility = Window.Maximized
            } else if (StreamingPreferences.uiDisplayMode === StreamingPreferences.UI_FULLSCREEN) {
                targetVisibility = Window.FullScreen
            }

            console.log("StreamSegue: Setting targetVisibility =", targetVisibility)

            // Apply the window state immediately before popping the StackView.
            // This ensures the window state is applied in the correct order
            // and avoids conflicts with Qt's window management after pop().
            if (targetVisibility === Window.Maximized) {
                window.showMaximized()
            } else if (targetVisibility === Window.FullScreen) {
                window.showFullScreen()
            } else {
                window.showNormal()
            }
            console.log("StreamSegue: Window state applied, current visibility =", window.visibility)
        }
    }

    Timer {
        id: errorDialogTimer
        interval: 50
        onTriggered: {
            window.requestActivate()
            window.raise()
            errorDialog.open()
        }
    }

    ErrorMessageDialog {
        id: errorDialog
        onClosed: {
            if (quitAfter) {
                Qt.quit()
            } else {
                stackView.pop()
            }
        }
    }

    function hostReady()
    {
        streamLoader.active = true
    }

    function sessionReadyForDeletion()
    {
        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        session = null
        gc()
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack
        toolBar.visible = true

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Safely disconnect signals only if session still exists
        // Session may be destroyed before this handler runs
        if (session) {
            session.stageStarting.disconnect(stageStarting)
            session.stageFailed.disconnect(stageFailed)
            session.connectionStarted.disconnect(connectionStarted)
            session.displayLaunchError.disconnect(displayLaunchError)
            session.quitStarting.disconnect(quitStarting)
            session.sessionFinished.disconnect(sessionFinished)
            session.sessionRestartRequested.disconnect(restartRequested)
            session.hostReady.disconnect(hostReady)
            session.readyForDeletion.disconnect(sessionReadyForDeletion)
        }
    }

    StackView.onActivated: {
        // Capture the window state immediately to record the user's pre-stream
        // window state before any potential modifications by Qt or the streaming session.
        // Only capture if not explicitly passed in (e.g., from QuitSegue).
        if (previousVisibility === -1) {
            previousVisibility = window.visibility
        }

        // Hide the toolbar before we start loading
        toolBar.visible = false

        // Show the splash screen in fullscreen mode
        window.showFullScreen()

        // Hook up our signals
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.sessionRestartRequested.connect(restartRequested)
        session.hostReady.connect(hostReady)
        session.readyForDeletion.connect(sessionReadyForDeletion)

        // Kick off the stream
        spinnerTimer.start()
        streamLoader.active = true
    }

    Timer {
        id: spinnerTimer

        // Display the spinner appearance a bit to allow us to reach
        // the code in Session.exec() that pumps the event loop.
        // If we display it immediately, it will briefly hang in the
        // middle of the animation on Windows, which looks very
        // obviously broken.
        interval: 100
        onTriggered: stageSpinner.visible = true
    }

    Timer {
        id: startSessionTimer
        onTriggered: {
            // Garbage collect QML stuff before we start streaming,
            // since we'll probably be streaming for a while and we
            // won't be able to GC during the stream.
            gc()

            // Run the streaming session to completion
            session.start()
        }
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            // Set the hint text. We do this here rather than
            // in the hintText control itself to synchronize
            // with Session.exec() which requires no concurrent
            // gamepad usage.
            hintText.text = qsTr("Tip:") + " " + qsTr("Press %1 to disconnect your session").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ?
                                                  qsTr("Start+Select+L1+R1") : qsTr("Ctrl+Alt+Shift+Q"))

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // Don't wait unless we have toasts to display
            startSessionTimer.interval = 0

            // Display the toasts together in a vertical centered arrangement
            var yOffset = 0
            for (var i = 0; i < session.launchWarnings.length; i++) {
                var text = session.launchWarnings[i]
                console.warn(text)

                // Show the tooltip for 3 seconds
                var toast = Qt.createQmlObject('import QtQuick.Controls 2.15; ToolTip {}', parent, '')
                toast.timeout = 3000
                toast.text = text
                toast.y += yOffset
                toast.visible = true

                // Offset the next toast below the previous one
                yOffset = toast.y + toast.padding + toast.height

                // Allow an extra 500 ms for the tooltip's fade-out animation to finish
                startSessionTimer.interval = toast.timeout + 500;
            }

            // Start the timer to wait for toasts (or start the session immediately)
            startSessionTimer.start()
        }

        sourceComponent: Item {}
    }

    Row {
        anchors.centerIn: parent
        spacing: 5

        BusyIndicator {
            id: stageSpinner
            running: visible
            visible: false
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

    Label {
        id: hintText
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        anchors.horizontalCenter: parent.horizontalCenter
        font.pointSize: 18
        verticalAlignment: Text.AlignVCenter

        wrapMode: Text.Wrap
    }
}

