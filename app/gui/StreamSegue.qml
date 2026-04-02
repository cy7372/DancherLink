import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

import "."

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import StreamingPreferences 1.0

Item {
    objectName: "StreamSegue"
    property Session session
    property string appName
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false

    // Fill the entire window (not just StackView content area) to cover footer area
    anchors.fill: Window.window

    // Opaque background to hide the previous view
    Rectangle {
        anchors.fill: parent
        color: "black"
        z: -100
    }

    signal restartRequested()

    // Property to track if we're waiting for resolution change debounce during restart
    property bool waitingForResolutionDebouncing: false
    property int debounceResolutionWidth: 0
    property int debounceResolutionHeight: 0

    // Timer for resolution change debounce during restart
    Timer {
        id: resolutionDebounceTimer
        interval: 200  // 200ms debounce
        onTriggered: {
            // Debounce period ended - proceed with restart
            waitingForResolutionDebouncing = false
            if (session) {
                console.log("Resolution debounce ended, proceeding with restart")
                // Trigger the actual restart
                restartWithDebouncedResolution()
            }
        }
    }

    // Function to handle restart after debounce
    function restartWithDebouncedResolution() {
        // Pop the old segue and create a new one with the debounced resolution
        stackView.pop(StackView.Immediate)
        // The caller (AppView) should handle recreating the segue
        // We emit a special signal to indicate we need a delayed restart
        delayedRestartRequested(debounceResolutionWidth, debounceResolutionHeight)
    }

    signal delayedRestartRequested(int width, int height)

    // Use -1 as default to indicate "not explicitly set"
    // When explicitly passed (e.g., from QuitSegue), this won't be overwritten
    property int previousVisibility: -1

    onRestartRequested: {
        // Save the current window visibility BEFORE showing fullscreen
        // This ensures we can restore to the correct state after streaming ends
        if (Window.window) {
            previousVisibility = Window.window.visibility
        }

        // Reset the UI state to show we are working
        if (Window.window) {
            Window.window.show()

            // Always show the splash screen in fullscreen mode
            Window.window.showFullScreen()
        }
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
        if (Window.window) {
            Window.window.hide()
        }
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
        if (Window.window) {
            Window.window.showNormal()
        }
    }

    function sessionFinished(portTestResult)
    {
        if (portTestResult !== 0 && portTestResult !== -1 && errorDialog.text) {
            errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking DancherLink. Streaming over the Internet may not work while connected to this network.")
        }

        // Check if we're waiting for resolution debounce
        // If so, stay on the transition screen and wait for the debounce timer
        if (waitingForResolutionDebouncing) {
            console.log("Session finished but waiting for resolution debounce - staying on transition screen")
            // Re-enable gamepad for the transition screen
            SdlGamepadKeyNavigation.enable()
            return
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
        if (!Window.window) {
            return
        }

        // We only do this if the window isn't minimized, to avoid restoring
        // a window that the user explicitly minimized during the stream.
        if (Window.window.visibility !== Window.Minimized) {
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

            // Apply the window state immediately before popping the StackView.
            // This ensures the window state is applied in the correct order
            // and avoids conflicts with Qt's window management after pop().
            if (targetVisibility === Window.Maximized) {
                Window.window.showMaximized()
            } else if (targetVisibility === Window.FullScreen) {
                Window.window.showFullScreen()
            } else {
                Window.window.showNormal()
            }
        }
    }

    Timer {
        id: errorDialogTimer
        interval: 50
        onTriggered: {
            if (Window.window) {
                Window.window.requestActivate()
                Window.window.raise()
            }
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
        if (Window.window && Window.window.toolBar) {
            Window.window.toolBar.visible = true
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Safely disconnect signals only if session still exists
        // Session may be destroyed before this handler runs
        // Use try-catch because session may be a dangling pointer (C++ destroyed but QML ref exists)
        try {
            if (session && session.stageStarting) session.stageStarting.disconnect(stageStarting)
            if (session && session.stageFailed) session.stageFailed.disconnect(stageFailed)
            if (session && session.connectionStarted) session.connectionStarted.disconnect(connectionStarted)
            if (session && session.displayLaunchError) session.displayLaunchError.disconnect(displayLaunchError)
            if (session && session.quitStarting) session.quitStarting.disconnect(quitStarting)
            if (session && session.sessionFinished) session.sessionFinished.disconnect(sessionFinished)
            if (session && session.sessionRestartRequested) session.sessionRestartRequested.disconnect(restartRequested)
            if (session && session.hostReady) session.hostReady.disconnect(hostReady)
            if (session && session.readyForDeletion) session.readyForDeletion.disconnect(sessionReadyForDeletion)
        } catch (e) {
            // Session may be destroyed already
        }
    }

    StackView.onActivated: {
        // Use Qt.callLater to ensure the component is fully attached to the window
        // before we try to access Window.window. StackView.onActivated can fire
        // before the component is in the window hierarchy.
        Qt.callLater(function() {
            // Capture the window state immediately to record the user's pre-stream
            // window state before any potential modifications by Qt or the streaming session.
            // Only capture if not explicitly passed in (e.g., from QuitSegue).
            if (previousVisibility === -1 && Window.window) {
                previousVisibility = Window.window.visibility
            }

            // Hide the toolbar before we start loading
            if (Window.window && Window.window.toolBar) {
                Window.window.toolBar.visible = false
            }

            // Show the splash screen according to user's UI display mode preference
            if (Window.window) {
                if (StreamingPreferences.uiDisplayMode === StreamingPreferences.UI_MAXIMIZED) {
                    Window.window.showMaximized()
                } else if (StreamingPreferences.uiDisplayMode === StreamingPreferences.UI_FULLSCREEN) {
                    Window.window.showFullScreen()
                }
            }
            // For UI_WINDOWED, keep current window state (just hide toolbar)
        })

        // Hook up our signals
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.sessionRestartRequested.connect(restartRequested)
        session.resolutionChangedDuringRestart.connect(function(width, height) {
            // New resolution detected during restart - start debounce timer
            console.log("Resolution changed to " + width + "x" + height + " during restart - starting debounce")
            waitingForResolutionDebouncing = true
            debounceResolutionWidth = width
            debounceResolutionHeight = height
            resolutionDebounceTimer.restart()
        })
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
            if (!session.initialize(Window.window)) {
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

