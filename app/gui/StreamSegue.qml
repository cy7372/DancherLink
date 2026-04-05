import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

import "."

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import StreamingPreferences 1.0
import AutoUpdateChecker 1.0

Item {
    objectName: "StreamSegue"
    property Session session
    property string appName
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false
    property bool connectionEstablished : false

    // Fill parent StackView
    anchors.fill: parent

    // Opaque background to hide the previous view
    // Use parent (StackView) instead of Window.window to avoid anchor conflicts
    Rectangle {
        anchors.fill: parent
        color: "black"
        z: -100
    }

    // =============================================================================
    // Session Signal Management
    // =============================================================================
    // Single source of truth for session signals and their handlers.
    // Used by Component.onCompleted (connect) and StackView.onDeactivating (disconnect).
    // Adding a new signal? Just add one entry here — both sides stay in sync.
    readonly property var sessionSignals: [
        ["stageStarting",                 stageStarting],
        ["stageFailed",                   stageFailed],
        ["connectionStarted",             connectionStarted],
        ["displayLaunchError",            displayLaunchError],
        ["quitStarting",                  quitStarting],
        ["sessionFinished",               sessionFinished],
        ["sessionRestartRequested",       restartRequested],
        ["resolutionChangedDuringRestart", onResolutionChangedDuringRestart],
        ["hostReady",                     hostReady],
        ["readyForDeletion",              sessionReadyForDeletion]
    ]

    function onResolutionChangedDuringRestart(width, height) {
        console.log("Resolution changed to " + width + "x" + height +
                    " during restart - restarting debounce timer")
        waitingForResolutionDebouncing = true
        debounceResolutionWidth = width
        debounceResolutionHeight = height
        resolutionDebounceTimer.restart()
    }

    // =============================================================================
    // Component Lifecycle
    // =============================================================================
    Component.onCompleted: {
        // CRITICAL: Connect signals IMMEDIATELY when component is created.
        // This is earlier than StackView.onActivated and eliminates the race condition
        // where user presses Back button before signals are connected.
        if (session) {
            console.log("StreamSegue: Component.onCompleted - connecting signals early")
            for (var i = 0; i < sessionSignals.length; i++) {
                session[sessionSignals[i][0]].connect(sessionSignals[i][1])
            }
        } else {
            console.error("StreamSegue: session is null in Component.onCompleted")
        }
    }

    // =============================================================================
    // Cancellation Management
    // =============================================================================
    // Unified method to request session cancellation. This is the single entry point
    // for all cancellation requests (Esc key, Back button, Qt back button).
    //
    // Usage:
    // - Keys.onPressed: call requestCancel() directly
    // - main.qml goBack(): call stackView.currentItem.requestCancel()
    // =============================================================================
    function requestCancel() {
        if (session && !cancelRequested) {
            cancelRequested = true
            lastCancelTime = Date.now()
            if (stackView && stackView.parent && stackView.parent.lastCancelTime !== undefined) {
                stackView.parent.lastCancelTime = lastCancelTime
            }
            session.requestCancel()
        }
    }

    // CRITICAL: Intercept back key to cancel streaming during initialization.
    // This only works during the loading phase before the stream starts.
    // Once streaming begins, the SDL window covers the screen and Qt window is hidden,
    // so the user can no longer interact with this QML interface.
    //
    // After connectionStarted(), this back key handler won't be reachable by the user.
    // The only way to exit streaming is via:
    // - Ctrl+Alt+Shift+Q hotkey
    // - Monitor power off / laptop lid close (if enabled in settings)
    // - Game-side quit
    property bool cancelRequested: false

    // CRITICAL: Track last cancel timestamp to implement reconnect cooldown.
    // This prevents users from reconnecting too quickly after manually canceling,
    // which would hit the server-side session reuse bug (foundation-sunshine).
    // Server needs ~10s to clean up pending session state.
    property int lastCancelTime: 0
    readonly property int reconnectCooldownMs: 5000  // 5s cooldown after manual cancel

    focus: true

    // Handle multiple "back" key types for cross-platform support:
    // - Key_Back: Android TV / webOS physical back button
    // - Key_Escape: Windows/Linux desktop Escape key
    Keys.onPressed: {
        if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
            if (session && !cancelRequested) {
                event.accepted = true
                requestCancel()
            }
        }
    }

    signal restartRequested()

    // Property to track if we're waiting for resolution change debounce during restart
    property bool waitingForResolutionDebouncing: false
    property int debounceResolutionWidth: 0
    property int debounceResolutionHeight: 0

    // CRITICAL: Track restart count to prevent infinite restart loops
    // If we restart too many times in a short period, we'll stop requesting restarts
    property int restartCount: 0
    property int lastRestartTime: 0
    readonly property int maxRestartsPerMinute: 5  // Max 5 restarts per minute
    readonly property int restartCooldownMs: 5000  // Min 5s between restarts

    // Timer for resolution change debounce during restart
    Timer {
        id: resolutionDebounceTimer
        interval: 200  // 200ms debounce
        onTriggered: {
            // Debounce period ended - proceed with restart
            waitingForResolutionDebouncing = false
            if (session) {
                console.log("Resolution debounce ended, proceeding with restart: " +
                            debounceResolutionWidth + "x" + debounceResolutionHeight)
                // Trigger the actual restart
                restartWithDebouncedResolution()
            }
        }
    }

    // Function to handle restart after debounce
    function restartWithDebouncedResolution() {
        // CRITICAL: Check if we're in a restart loop
        var now = Date.now()
        if (restartCount > 0 && now - lastRestartTime < restartCooldownMs) {
            console.warn("Restart cooldown active - skipping restart. Count: " + restartCount +
                         ", Last restart: " + (now - lastRestartTime) + "ms ago")
            // Still pop the segue to exit the transition screen
            stackView.pop(StackView.Immediate)
            // Return without requesting restart - user can manually restart if needed
            return
        }

        // Check if we've exceeded max restarts
        if (restartCount >= maxRestartsPerMinute) {
            console.error("Max restarts per minute exceeded (" + restartCount + "). " +
                          "Please manually restart the stream.")
            // Show error dialog instead of restarting
            displayLaunchError(qsTr("Too many resolution changes detected. Please manually restart the stream."))
            return
        }

        // Record this restart
        restartCount++
        lastRestartTime = now
        console.log("Restarting stream (count: " + restartCount + "/" + maxRestartsPerMinute + ")")

        // Pop the old segue immediately
        stackView.pop(StackView.Immediate)
        // The caller (AppView) should handle recreating the segue
        // We emit a special signal to indicate we need a delayed restart
        // CRITICAL: Capture the resolution values NOW before the closure runs
        // This ensures we use the latest resolution even if more changes arrive
        delayedRestartRequested(debounceResolutionWidth, debounceResolutionHeight)
    }

    signal delayedRestartRequested(int width, int height)

    // =============================================================================
    // Window State Management
    // =============================================================================
    // previousVisibility tracks the window state BEFORE streaming started.
    // This is used to restore the correct window state when streaming ends.
    //
    // Capture flow:
    // 1. AppView captures Window.visibility before creating StreamSegue
    // 2. AppView passes previousVisibility to StreamSegue via createObject()
    // 3. StreamSegue uses previousVisibility in restoreWindowState() to restore
    //
    // Fallback logic (if previousVisibility is -1):
    // - Use StreamingPreferences.uiDisplayMode
    // - Default to Windowed mode
    // =============================================================================
    property int previousVisibility: -1

    function computeTargetVisibility(savedPreviousVisibility) {
        return savedPreviousVisibility === Window.Maximized ? Window.Maximized :
               savedPreviousVisibility === Window.FullScreen ? Window.FullScreen :
               Window.Windowed
    }

    function applyVisibilityToWindow(win, targetVisibility) {
        if (!win) return
        try {
            if (targetVisibility === Window.Maximized) win.showMaximized()
            else if (targetVisibility === Window.FullScreen) win.showFullScreen()
            else win.showNormal()
            win.raise()
            win.requestActivate()
        } catch (e) {
            console.log("  applyVisibilityToWindow: Exception:", e)
            try { win.showNormal(); win.raise() } catch (e2) {}
        }
    }

    // Common pattern: save session, show window in target state, then restore after pop.
    // Eliminates the 3x repetition in sessionFinished()'s exit paths.
    function prepareAndRestore(savedPrevVis, postRestoreCallback) {
        var savedSession = session
        var targetVis = computeTargetVisibility(savedPrevVis)
        makeWindowVisibleInTargetState(targetVis)
        restoreWindowToPreviousState(savedSession, savedPrevVis, postRestoreCallback)
    }

    // CRITICAL: Restore window to a previous state after streaming ends.
    //
    // Uses the stored mainWindow reference (captured at component creation time)
    // instead of Window.window attached property, because Window.window becomes
    // null after stackView.pop() removes this component from the window hierarchy.
    //
    // Parameters:
    // - savedSession: Session reference captured before stackView.pop()
    // - savedPreviousVisibility: Window visibility state to restore
    // - postRestoreCallback: Optional callback to execute after window restoration
    function restoreWindowToPreviousState(savedSession, savedPreviousVisibility, postRestoreCallback) {
        Qt.callLater(function() {
            var win = mainWindow
            if (!win) return

            // Restore window style first (Windows only)
            if (savedSession && typeof savedSession.restoreWindowStyle === "function") {
                try { savedSession.restoreWindowStyle() } catch (e) {}
            }

            var targetVisibility = computeTargetVisibility(savedPreviousVisibility)
            applyVisibilityToWindow(win, targetVisibility)

            if (typeof postRestoreCallback === "function") {
                postRestoreCallback()
            }
        })
    }

    // CRITICAL: Show the window in the TARGET state before stackView.pop().
    //
    // Previously this always called showNormal(), which caused two problems:
    // 1) On Windows 11, showNormal() on a hidden-fullscreen window may not
    //    properly exit fullscreen mode — the window appears but stays fullscreen.
    // 2) The deferred restoreWindowToPreviousState() callback used Window.window
    //    which becomes null after pop(), so the target state was never applied.
    //
    // Now we directly apply the target state (e.g., showMaximized) so the window
    // transitions from hidden-fullscreen to the correct final state in one step.
    function makeWindowVisibleInTargetState(targetVisibility) {
        var win = Window.window
        if (win) applyVisibilityToWindow(win, targetVisibility)
    }

    onRestartRequested: {
        // Show window fullscreen during restart transition.
        // Note: previousVisibility is NOT updated here — AppView preserves
        // the original value captured at launch time across restarts.
        if (Window.window) {
            Window.window.show()
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
        connectionEstablished = true

        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        stageSpinner.visible = false
        stageLabel.visible = false
        hintText.visible = false

        // Keep window visible — Session::exec() hides it after SDL window creation
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        errorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        // Update text before creating QuitSegue for smooth transition
        // In case StreamSegue is briefly visible during the replace operation
        stageText = qsTr("Quitting %1...").arg(appName)
        stageSpinner.visible = true
        stageLabel.visible = true
        hintText.visible = false

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
        console.log("sessionFinished: canceled=", cancelRequested,
                    "portTest=", portTestResult,
                    "error=", !!errorDialog.text,
                    "debouncing=", waitingForResolutionDebouncing)

        if (portTestResult !== 0 && portTestResult !== -1 && errorDialog.text) {
            errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking DancherLink. Streaming over the Internet may not work while connected to this network.")
        }

        // Re-enable GUI gamepad usage (unconditional, before any early return)
        SdlGamepadKeyNavigation.enable()

        // Check if we're waiting for resolution debounce
        if (waitingForResolutionDebouncing) {
            return
        }

        // User canceled via back key - just restore and return
        if (cancelRequested) {
            console.log("  User canceled, restoring window BEFORE pop")
            prepareAndRestore(previousVisibility)
            stackView.pop()
            return
        }

        // CLI launch without errors - exit now
        if (quitAfter && !errorDialog.text) {
            Qt.quit()
        }
        else if (errorDialog.text) {
            // Update text to show exiting state, then restore and show error
            stageText = qsTr("Quitting %1...").arg(appName)
            shouldShowErrorDialog = true
            // Cannot pop() here — errorDialog.onClosed() handles it after user dismisses
            prepareAndRestore(previousVisibility, function() {
                errorDialogTimer.start()
            })
        }
        else {
            // Normal exit - update text to show exiting state for a smooth transition
            stageText = qsTr("Quitting %1...").arg(appName)
            stageSpinner.visible = true
            stageLabel.visible = true
            hintText.visible = false

            prepareAndRestore(previousVisibility, function() {
                AutoUpdateChecker.start(false)
            })
            stackView.pop()
            return
        }
    }

    // CRITICAL: Track whether we should show the error dialog
    // This is needed because stackView becomes inaccessible after component is popped,
    // but we still need to know if errorDialog should be shown
    property bool shouldShowErrorDialog: false

    // Store a reference to the main window at component creation time
    // This avoids Window.window becoming null when the component is popped
    property var mainWindow: Window.window

    Timer {
        id: errorDialogTimer
        interval: 50
        onTriggered: {
            if (!mainWindow) {
                if (stackView) stackView.pop()
                return
            }
            if (!shouldShowErrorDialog || !errorDialog.text) return
            mainWindow.requestActivate()
            mainWindow.raise()
            errorDialog.open()
        }
    }

    ErrorMessageDialog {
        id: errorDialog
        onClosed: {
            if (quitAfter) {
                Qt.quit()
            } else {
                shouldShowErrorDialog = false
                Qt.callLater(function() {
                    if (stackView) stackView.pop()
                })
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
        if (Window.window && Window.window.header) {
            Window.window.header.visible = true
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Disconnect all session signals using the same list as Component.onCompleted.
        // Session may be destroyed already (C++ object gone but QML reference still exists).
        try {
            for (var i = 0; i < sessionSignals.length; i++) {
                if (session && session[sessionSignals[i][0]])
                    session[sessionSignals[i][0]].disconnect(sessionSignals[i][1])
            }
        } catch (e) {}

        // Note: session.interrupt() is called in Keys.onBackPressed when user presses back,
        // or by sessionFinished()/quitAppCompleted() flow when streaming ends normally.
        // No need to call it here as it may be called twice.
    }

    StackView.onActivated: {
        // Signals are already connected in Component.onCompleted.
        // Just verify session exists before proceeding.
        if (!session) {
            console.error("StreamSegue: session is null in onActivated, cannot proceed")
            return
        }

        console.log("StreamSegue: StackView.onActivated - signals already connected, proceeding with initialization")

        if (Window.window) {
            // Hide toolbar
            if (Window.window.header) {
                Window.window.header.visible = false
            }

            // Go directly from maximized to fullscreen.
            // No showNormal() — it restores stale "normal" geometry that
            // Windows may reject (e.g. taskbar reduces work area), causing
            // setGeometry warnings and breaking showFullScreen().
            Window.window.showFullScreen()
        }

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

