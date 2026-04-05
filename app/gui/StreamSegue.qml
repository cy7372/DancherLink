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
    // Component Lifecycle
    // =============================================================================
    Component.onCompleted: {
        // CRITICAL: Connect signals IMMEDIATELY when component is created.
        // This is earlier than StackView.onActivated and eliminates the race condition
        // where user presses Back button before signals are connected.
        //
        // The session object is already assigned by AppView.createStreamSegue() before
        // createObject() returns, so session is guaranteed to be valid here.
        if (session) {
            console.log("StreamSegue: Component.onCompleted - connecting signals early")
            session.stageStarting.connect(stageStarting)
            session.stageFailed.connect(stageFailed)
            session.connectionStarted.connect(connectionStarted)
            session.displayLaunchError.connect(displayLaunchError)
            session.quitStarting.connect(quitStarting)
            session.sessionFinished.connect(sessionFinished)
            session.sessionRestartRequested.connect(restartRequested)
            session.resolutionChangedDuringRestart.connect(function(width, height) {
                console.log("Resolution changed to " + width + "x" + height +
                            " during restart - restarting debounce timer")
                waitingForResolutionDebouncing = true
                debounceResolutionWidth = width
                debounceResolutionHeight = height
                resolutionDebounceTimer.restart()
            })
            session.hostReady.connect(hostReady)
            session.readyForDeletion.connect(sessionReadyForDeletion)
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
        console.log("====== requestCancel() called ======")
        console.log("  session:", session)
        console.log("  cancelRequested:", cancelRequested)
        console.log("  focus:", focus)
        console.log("  Item.visible:", visible)

        // Guard: Check if session exists and hasn't already requested cancellation
        if (session && !cancelRequested) {
            cancelRequested = true
            // Record the cancel timestamp for reconnect cooldown.
            // CRITICAL: Update both local property AND parent AppView for persistence.
            lastCancelTime = Date.now()
            if (stackView && stackView.parent && stackView.parent.lastCancelTime !== undefined) {
                stackView.parent.lastCancelTime = lastCancelTime
                console.log("  Updated parent.lastCancelTime to", lastCancelTime)
            }
            console.log("====== Calling session.requestCancel() ======")
            session.requestCancel()
            console.log("====== session.requestCancel() completed ======")
            // Keep the transition screen visible until sessionFinished is received.
        } else {
            console.log("  SKIPPED: session=", session, " cancelRequested=", cancelRequested)
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
            console.log("====== Back/Esc key pressed handler invoked ======")
            console.log("  key:", event.key)
            if (session && !cancelRequested) {
                event.accepted = true  // CRITICAL: Accept the event to prevent propagation
                requestCancel()
            } else {
                console.log("  SKIPPED: session=", session, " cancelRequested=", cancelRequested)
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

    // Helper to compute the target visibility from savedPreviousVisibility.
    // Avoids duplicating this logic across multiple functions.
    function computeTargetVisibility(savedPreviousVisibility) {
        if (savedPreviousVisibility === Window.Maximized) {
            return Window.Maximized
        } else if (savedPreviousVisibility === Window.FullScreen) {
            return Window.FullScreen
        }
        return Window.Windowed
    }

    // Helper to apply a target visibility to a window object.
    function applyVisibilityToWindow(win, targetVisibility) {
        if (!win) return
        try {
            if (targetVisibility === Window.Maximized) {
                win.showMaximized()
            } else if (targetVisibility === Window.FullScreen) {
                win.showFullScreen()
            } else {
                win.showNormal()
            }
            win.raise()
            win.requestActivate()
        } catch (e) {
            console.log("  applyVisibilityToWindow: Exception:", e)
            try { win.showNormal(); win.raise() } catch (e2) {}
        }
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
            // Use stored mainWindow reference instead of Window.window.
            // Window.window becomes null after stackView.pop() removes
            // this component from the window hierarchy, causing the old
            // code to silently skip restoration entirely.
            var win = mainWindow
            console.log("  Qt.callLater: restoring window to state", savedPreviousVisibility,
                        "(0=Hidden, 2=Windowed, 4=Maximized, 5=FullScreen)")
            console.log("  Qt.callLater: mainWindow exists:", !!win,
                        "Window.window exists:", !!Window.window)

            if (!win) {
                console.log("  Qt.callLater: mainWindow is null, aborting")
                return
            }

            // Restore window style first (Windows only)
            if (savedSession && typeof savedSession.restoreWindowStyle === "function") {
                try {
                    console.log("  Qt.callLater: calling savedSession.restoreWindowStyle()")
                    savedSession.restoreWindowStyle()
                } catch (e) {
                    console.log("  Qt.callLater: savedSession.restoreWindowStyle() failed:", e)
                }
            }

            // Apply the desired window state
            var targetVisibility = computeTargetVisibility(savedPreviousVisibility)
            applyVisibilityToWindow(win, targetVisibility)

            console.log("  Qt.callLater: AFTER restore - visible:", win.visible,
                        "visibility:", win.visibility)
            console.log("  Qt.callLater: window restoration complete")

            // Execute post-restore callback if provided
            if (typeof postRestoreCallback === "function") {
                console.log("  Qt.callLater: executing post-restore callback")
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
        if (win) {
            console.log("  Pre-pop restore: showing window in target state", targetVisibility,
                        "(0=Hidden, 2=Windowed, 4=Maximized, 5=FullScreen)")
            applyVisibilityToWindow(win, targetVisibility)
        }
    }

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
        console.log("====== connectionStarted() called ======")
        console.log("  connectionEstablished:", connectionEstablished)

        // Mark that the connection was successfully established
        // This affects how we handle cancellation (fast vs graceful shutdown)
        connectionEstablished = true

        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        stageSpinner.visible = false
        stageLabel.visible = false
        hintText.visible = false

        // CRITICAL: Do NOT hide the window here!
        // The Qt window must remain visible (and focused) until Session::exec() completes.
        // If we hide the window now, QML loses focus and Keys.onBackPressed won't work.
        //
        // The window will be hidden in Session::exec() after the SDL window is created,
        // which happens AFTER we've processed any pending interrupt() calls.
        //
        // Previous behavior (buggy):
        // - Hide window here -> QML loses focus -> Back key ignored -> SDL window created anyway
        //
        // New behavior (fixed):
        // - Keep window visible -> QML retains focus -> Back key works -> interrupt() sets flag
        // - Session::exec() checks interrupt flag before creating SDL window
        console.log("  Keeping Qt window visible to allow Back key cancellation")
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
        console.log("====== sessionFinished() called ======")
        console.log("  cancelRequested:", cancelRequested)
        console.log("  portTestResult:", portTestResult)
        console.log("  errorDialog.text:", errorDialog.text)
        console.log("  waitingForResolutionDebouncing:", waitingForResolutionDebouncing)
        console.log("  session:", session)
        console.log("  Window.window:", Window.window)
        console.log("  Window.window.visible:", Window.window ? Window.window.visible : "null")
        console.log("  Window.window.visibility:", Window.window ? Window.window.visibility : "null")
        console.log("  previousVisibility:", previousVisibility,
                    "(Qt6: 0=Hidden, 1=Auto, 2=Windowed, 3=Minimized, 4=Maximized, 5=FullScreen)")

        if (portTestResult !== 0 && portTestResult !== -1 && errorDialog.text) {
            errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking DancherLink. Streaming over the Internet may not work while connected to this network.")
        }

        // Check if we're waiting for resolution debounce
        if (waitingForResolutionDebouncing) {
            SdlGamepadKeyNavigation.enable()
            return
        }

        // Re-enable GUI gamepad usage
        SdlGamepadKeyNavigation.enable()

        // User canceled via back key - just restore and return
        if (cancelRequested) {
            console.log("  User canceled, restoring window BEFORE pop")
            console.log("  Before pop: stackView.depth =", stackView.depth)
            console.log("  Before pop: savedPreviousVisibility =", previousVisibility)

            // Save values before pop
            var savedSession = session
            var savedPreviousVisibility = previousVisibility

            // CRITICAL: Show window in TARGET state directly (not showNormal first).
            // showNormal() on a hidden-fullscreen window may not properly exit fullscreen on Windows.
            var targetVis = computeTargetVisibility(savedPreviousVisibility)
            makeWindowVisibleInTargetState(targetVis)

            console.log("  sessionFinished (cancel): saved previousVisibility =", savedPreviousVisibility,
                        "(0=Hidden, 1=Auto, 2=Windowed, 3=Min, 4=Max, 5=FS)")

            // Now pop the stack - window is already visible so user won't see a flash
            stackView.pop()

            // Safety net: ensure window state is correct after pop
            restoreWindowToPreviousState(savedSession, savedPreviousVisibility)

            return
        }

        // CLI launch without errors - exit now
        if (quitAfter && !errorDialog.text) {
            Qt.quit()
        }
        else if (errorDialog.text) {
            // Update text to show exiting state, then restore and show error
            stageText = qsTr("Quitting %1...").arg(appName)

            // Save session reference and previousVisibility for window restoration.
            // We cannot pop() here because we need errorDialog to be shown first.
            // The stackView.pop() will be called in errorDialog.onClosed() after user dismisses the dialog.
            var savedSession = session
            var savedPreviousVisibility = previousVisibility

            console.log("  sessionFinished (error): saved previousVisibility =", savedPreviousVisibility,
                        "(0=Hidden, 1=Auto, 2=Windowed, 3=Min, 4=Max, 5=FS)")

            // Set the flag to indicate we should show the error dialog
            shouldShowErrorDialog = true

            // CRITICAL: Show window in target state directly.
            var targetVis2 = computeTargetVisibility(savedPreviousVisibility)
            makeWindowVisibleInTargetState(targetVis2)

            // Use helper function to restore window state, then show error dialog
            restoreWindowToPreviousState(savedSession, savedPreviousVisibility, function() {
                errorDialogTimer.start()
            })
        }
        else {
            // Normal exit - update text to show exiting state for a smooth transition
            // User sees: "Starting..." → "Quitting..." → back to main view
            stageText = qsTr("Quitting %1...").arg(appName)
            stageSpinner.visible = true
            stageLabel.visible = true
            hintText.visible = false

            // Save session reference and previousVisibility BEFORE popping.
            var savedSession = session
            var savedPreviousVisibility = previousVisibility

            console.log("  sessionFinished (normal): saved previousVisibility =", savedPreviousVisibility,
                        "(0=Hidden, 1=Auto, 2=Windowed, 3=Min, 4=Max, 5=FS)")

            // CRITICAL: Show window in TARGET state directly (not showNormal first).
            // This avoids the bug where showNormal() on a hidden-fullscreen window
            // leaves the window stuck in fullscreen on Windows 11.
            var targetVis3 = computeTargetVisibility(savedPreviousVisibility)
            makeWindowVisibleInTargetState(targetVis3)

            // Now pop the stack - window is already visible in correct state
            stackView.pop()

            // Safety net: ensure window state after pop (uses mainWindow reference)
            restoreWindowToPreviousState(savedSession, savedPreviousVisibility, function() {
                console.log("  Post-restore: starting auto-update check")
                AutoUpdateChecker.start(false)
            })

            return
        }
    }

    function restoreWindowState() {
        var win = mainWindow || Window.window
        if (!win) {
            console.log("  restoreWindowState(): no window reference, returning")
            return
        }

        console.log("  restoreWindowState(): current visibility=" + win.visibility +
                    " previousVisibility=" + previousVisibility)

        // We only do this if the window isn't minimized, to avoid restoring
        // a window that the user explicitly minimized during the stream.
        if (win.visibility !== Window.Minimized) {
            // Restore window style first (Windows only)
            if (session) {
                session.restoreWindowStyle()
            }

            var targetVisibility = computeTargetVisibility(previousVisibility)
            console.log("  restoreWindowState(): targetVisibility=" + targetVisibility)
            applyVisibilityToWindow(win, targetVisibility)
        } else {
            console.log("  restoreWindowState(): window is minimized, skipping restoration")
        }
    }

    // CRITICAL: Track whether we should show the error dialog
    // This is needed because stackView becomes inaccessible after component is popped,
    // but we still need to know if errorDialog should be shown
    property bool shouldShowErrorDialog: false

    // Store a reference to the main window at component creation time
    // This avoids Window.window becoming null when the component is popped
    property var mainWindow: Window.window

    // Use a hidden Item to host the Timer, avoiding Window.window access issues
    Item {
        id: timerHost
        visible: false

        Timer {
            id: errorDialogTimer
            interval: 50
            onTriggered: {
                // Use stored mainWindow reference instead of Window.window
                if (!mainWindow) {
                    console.log("  errorDialogTimer: mainWindow is null, skipping dialog but popping stackView")
                    // CRITICAL FIX: Even if mainWindow is null, we must pop the stackView
                    // to prevent the app from being stuck on "Quitting..." screen
                    if (stackView) {
                        stackView.pop()
                    }
                    return
                }
                if (!shouldShowErrorDialog) {
                    console.log("  errorDialogTimer: shouldShowErrorDialog is false, skipping dialog")
                    return
                }
                if (!errorDialog.text) {
                    console.log("  errorDialogTimer: no error text, skipping dialog")
                    return
                }
                console.log("  errorDialogTimer: showing error dialog")
                mainWindow.requestActivate()
                mainWindow.raise()
                errorDialog.open()
            }
        } // Timer
    } // Item (timerHost)

    ErrorMessageDialog {
        id: errorDialog
        onClosed: {
            console.log("  errorDialog.onClosed: quitAfter=", quitAfter)
            if (quitAfter) {
                Qt.quit()
            } else {
                // Reset the flag before popping
                shouldShowErrorDialog = false
                // CRITICAL: Use Qt.callLater to ensure dialog is fully closed before popping
                Qt.callLater(function() {
                    if (stackView) {
                        console.log("  errorDialog.onClosed: popping stackView")
                        stackView.pop()
                    } else {
                        console.log("  errorDialog.onClosed: stackView is null, skipping pop")
                    }
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

        // CRITICAL: Hide the toolbar and go fullscreen IMMEDIATELY (not deferred).
        // Previously this used Qt.callLater(), which deferred by one event loop iteration.
        // That caused a race condition: StreamSegue rendered at the previous windowed size
        // (with toolbar taking 60px + footer 32px) for one visible frame, making the
        // content appear to fill only a small portion of the screen.
        //
        // Use Window.window.header (Q_PROPERTY) instead of .toolBar (id from main.qml)
        // to ensure reliable cross-component access.
        if (Window.window) {
            if (Window.window.header) {
                Window.window.header.visible = false
            }

            console.log("StreamSegue: Setting window to fullscreen for transition")
            Window.window.showFullScreen()

            // Foldable screen fix: Re-apply fullscreen after a short delay.
            // On foldable devices, when the screen resolution changes (fold/unfold),
            // Qt's internal QScreen geometry may not be fully updated at the time
            // showFullScreen() is called. The delayed re-application ensures Qt uses
            // the correct screen geometry after processing WM_DISPLAYCHANGE.
            fullscreenRefreshTimer.start()
        }

        // Kick off the stream
        spinnerTimer.start()
        streamLoader.active = true
    }

    // Timer to re-apply fullscreen for foldable screen resolution changes.
    // When the screen resolution changes (e.g., foldable device fold/unfold),
    // the initial showFullScreen() may use stale screen geometry. This timer
    // fires after Qt has processed the display change event, re-applying
    // fullscreen with the correct geometry.
    Timer {
        id: fullscreenRefreshTimer
        interval: 100
        onTriggered: {
            if (Window.window && Window.window.visibility === Window.FullScreen) {
                console.log("StreamSegue: Re-applying fullscreen for foldable screen geometry refresh")
                Window.window.showFullScreen()
            }
        }
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

