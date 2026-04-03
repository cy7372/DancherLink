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

    // Fill parent StackView
    anchors.fill: parent

    // Opaque background to hide the previous view
    // Use Window.window as parent to cover the entire window (including footer area)
    Rectangle {
        anchors.fill: Window.window
        color: "black"
        z: -100
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

        if (session && !cancelRequested) {
            cancelRequested = true
            console.log("====== Calling session.interrupt() ======")
            session.interrupt()
            console.log("====== session.interrupt() completed ======")
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
            console.log("  User canceled, popping stackView first")

            // CRITICAL: Save session reference and previousVisibility BEFORE popping.
            // After pop(), stackView.currentItem will be AppView (no session property),
            // and the StreamSegue properties will be inaccessible.
            // We need these saved values in the Qt.callLater callback to restore the window.
            var savedSession = session
            var savedPreviousVisibility = previousVisibility

            // CRITICAL: This is the fundamental fix for the intermittent window restoration issue.
            //
            // Problem analysis:
            // When stackView.pop() is called, the StreamSegue component is marked for destruction.
            // However, window operations like showNormal()/showMaximized() are asynchronous - they
            // require the Qt event loop to process them. If the component is destroyed before the
            // event loop processes these operations, the window may not be properly restored.
            //
            // Solution:
            // 1. Pop the stack FIRST to return to AppView
            // 2. Use Qt.callLater to restore the window AFTER the pop completes
            // 3. Save session reference before pop to ensure it's accessible in the callback
            // 4. Window operations are performed in the callback, ensuring they complete

            stackView.pop()

            // Use Qt.callLater to restore the window after the stack pop completes.
            // This ensures the QML stack is stable before we manipulate the window.
            Qt.callLater(function() {
                console.log("  Qt.callLater: restoring window state after pop")
                if (!Window.window) {
                    console.log("  Qt.callLater: Window.window is null, aborting")
                    return
                }

                // Restore window style first (Windows only)
                // Use the saved session reference (captured before pop)
                if (savedSession) {
                    console.log("  Qt.callLater: calling savedSession.restoreWindowStyle()")
                    savedSession.restoreWindowStyle()
                } else {
                    console.log("  Qt.callLater: savedSession is null, skipping restoreWindowStyle()")
                }

                // Apply the desired window state based on previous visibility
                // Use the saved previousVisibility value (captured before pop)
                var targetVisibility = Window.Windowed
                if (savedPreviousVisibility === Window.Maximized) {
                    targetVisibility = Window.Maximized
                } else if (savedPreviousVisibility === Window.FullScreen) {
                    targetVisibility = Window.FullScreen
                }

                console.log("  Qt.callLater: targetVisibility=" + targetVisibility +
                            " savedPreviousVisibility=" + savedPreviousVisibility)

                if (targetVisibility === Window.Maximized) {
                    Window.window.showMaximized()
                } else if (targetVisibility === Window.FullScreen) {
                    Window.window.showFullScreen()
                } else {
                    Window.window.showNormal()
                }

                // CRITICAL: Explicitly raise and activate the window
                Window.window.raise()
                Window.window.requestActivate()

                console.log("  Qt.callLater: window restoration complete")
            })

            return
        }

        // CLI launch without errors - exit now
        if (quitAfter && !errorDialog.text) {
            Qt.quit()
        }
        else if (errorDialog.text) {
            // Update text to show exiting state, then restore and show error
            stageText = qsTr("Quitting %1...").arg(appName)
            restoreWindowState()
            errorDialogTimer.start()
        }
        else {
            // Normal exit - update text to show exiting state for a smooth transition
            // User sees: "Starting..." → "Quitting..." → back to main view
            stageText = qsTr("Quitting %1...").arg(appName)
            stageSpinner.visible = true
            stageLabel.visible = true
            hintText.visible = false

            // CRITICAL: Save session reference and previousVisibility BEFORE popping.
            // Same fix as the cancelRequested path.
            var savedSession = session
            var savedPreviousVisibility = previousVisibility

            stackView.pop()

            Qt.callLater(function() {
                console.log("  Qt.callLater (normal exit): restoring window state after pop")
                if (!Window.window) {
                    console.log("  Qt.callLater (normal exit): Window.window is null")
                    return
                }

                // Restore window style first (Windows only)
                // Use the saved session reference (captured before pop)
                if (savedSession) {
                    savedSession.restoreWindowStyle()
                }

                // Apply the desired window state based on previous visibility
                // Use the saved previousVisibility value (captured before pop)
                var targetVisibility = Window.Windowed
                if (savedPreviousVisibility === Window.Maximized) {
                    targetVisibility = Window.Maximized
                } else if (savedPreviousVisibility === Window.FullScreen) {
                    targetVisibility = Window.FullScreen
                }

                if (targetVisibility === Window.Maximized) {
                    Window.window.showMaximized()
                } else if (targetVisibility === Window.FullScreen) {
                    Window.window.showFullScreen()
                } else {
                    Window.window.showNormal()
                }

                Window.window.raise()
                Window.window.requestActivate()

                console.log("  Qt.callLater (normal exit): window restoration complete")

                // Start auto-update check after window is restored
                AutoUpdateChecker.start(false)
            })

            return
        }
    }

    function restoreWindowState() {
        if (!Window.window) {
            console.log("  restoreWindowState(): Window.window is null, returning")
            return
        }

        console.log("  restoreWindowState(): current visibility=" + Window.window.visibility +
                    " previousVisibility=" + previousVisibility)

        // We only do this if the window isn't minimized, to avoid restoring
        // a window that the user explicitly minimized during the stream.
        if (Window.window.visibility !== Window.Minimized) {
            // Restore window style first (Windows only)
            if (session) {
                session.restoreWindowStyle()
            }

            // Apply the desired window state based on previous visibility
            var targetVisibility = Window.Windowed

            if (previousVisibility === Window.Maximized) {
                targetVisibility = Window.Maximized
            } else if (previousVisibility === Window.FullScreen) {
                targetVisibility = Window.FullScreen
            }
            // For Windowed or -1 (not set), default to Windowed

            console.log("  restoreWindowState(): targetVisibility=" + targetVisibility)

            if (targetVisibility === Window.Maximized) {
                console.log("  restoreWindowState(): calling showMaximized()")
                Window.window.showMaximized()
            } else if (targetVisibility === Window.FullScreen) {
                console.log("  restoreWindowState(): calling showFullScreen()")
                Window.window.showFullScreen()
            } else {
                console.log("  restoreWindowState(): calling showNormal()")
                Window.window.showNormal()
            }

            // CRITICAL: Explicitly raise and activate the window to ensure it's visible
            // This is necessary because stackView.pop() may happen before the window
            // has a chance to be shown
            console.log("  restoreWindowState(): calling raise() and requestActivate()")
            Window.window.raise()
            Window.window.requestActivate()
        } else {
            console.log("  restoreWindowState(): window is minimized, skipping restoration")
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

        // Note: session.interrupt() is called in Keys.onBackPressed when user presses back,
        // or by sessionFinished()/quitAppCompleted() flow when streaming ends normally.
        // No need to call it here as it may be called twice.
    }

    StackView.onActivated: {
        // Use Qt.callLater to ensure the component is fully attached to the window
        // before we try to access Window.window. StackView.onActivated can fire
        // before the component is in the window hierarchy.
        Qt.callLater(function() {
            // Hide the toolbar before we start loading
            if (Window.window && Window.window.toolBar) {
                Window.window.toolBar.visible = false
            }

            // CRITICAL: Show fullscreen to cover taskbar during transition
            // This ensures the transition screen covers the entire screen, even if
            // the user's windowed mode doesn't cover the taskbar.
            // Note: previousVisibility is passed from AppView, so we don't capture it here
            if (Window.window) {
                Window.window.showFullScreen()
            }
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
            // New resolution detected during restart - restart debounce timer
            // This ensures we always use the LATEST resolution after changes stop
            console.log("Resolution changed to " + width + "x" + height +
                        " during restart - restarting debounce timer")
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

