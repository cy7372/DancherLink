import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls.Material 2.15

import "."

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

// =============================================================================
// Main Application Window
// =============================================================================
// Structure:
//   - Properties & State (pollingActive, currentNetworkModel, etc.)
//   - Early Initialization (doEarlyInit, Component.onCompleted)
//   - Timers (inactivityTimer, checkUpdateTimer)
//   - Event Handlers (onVisibleChanged, onActiveChanged)
//   - Dialogs (wow64Dialog, noHardwareAccelDialog, etc.)
//   - UI Components (header, StackView, network indicator)
// =============================================================================

ApplicationWindow {
    id: root

    property bool pollingActive: false

    // Set by SettingsView to force the back operation to pop all
    // pages except the initial view. This is required when doing
    // a retranslate() because AppView breaks for some reason.
    property bool clearOnBack: false

    // Current network model for latency indicator
    // Updated via setCurrentNetworkModel() when stack changes or AppView initializes
    property var currentNetworkModel: null
    property var currentStackItem: null

    function updateCurrentNetworkModel() {
        var item = stackView.currentItem
        if (!item) {
            currentNetworkModel = null
            return
        }
        // Check AppView's networkModel property first
        if (item.networkModel !== undefined && item.networkModel !== null) {
            currentNetworkModel = item.networkModel
            return
        }
        // Check for ComputerModel (PcView)
        if (item.computerModel !== undefined && item.computerModel !== null) {
            currentNetworkModel = item.computerModel
            return
        }
        currentNetworkModel = null
    }

    // Update currentStackItem when stack changes, and schedule network model update
    // Use double Qt.callLater to ensure PcView/AppView Component.onCompleted runs first
    function updateCurrentStackItem() {
        currentStackItem = stackView.currentItem
        // Double Qt.callLater ensures we run after the current item's Component.onCompleted
        Qt.callLater(function() {
            Qt.callLater(function() {
                updateCurrentNetworkModel()
            })
        })
    }

    // Set minimum window size to prevent UI elements from overlapping or being cut off
    minimumWidth: 1024
    minimumHeight: 576

    // Start invisible to prevent flicker before Component.onCompleted applies the user's
    // preferred window state (maximized/fullscreen/windowed). We explicitly show the
    // window in Component.onCompleted after applying the desired state.
    visible: false

    // No fixed width/height bindings here - they interfere with Qt's window state
    // restoration on Windows. When the window is restored from minimize, QML property
    // bindings are re-evaluated, which can override Qt's restored geometry.
    // Instead, we set the initial size imperatively in Component.onCompleted.

    // This function runs prior to creation of the initial StackView item
    function doEarlyInit() {
        // Override the background color to Material 2 colors for Qt 6.5+
        // in order to improve contrast between GFE's placeholder box art
        // and the background of the app grid.
        if (SystemProperties.usesMaterial3Theme) {
            Material.background = AppTheme.backgroundPrimary
        }

        SdlGamepadKeyNavigation.enable()
    }

    Component.onCompleted: {
        // Update network model for latency indicator
        updateCurrentNetworkModel()

        // Delay the update check slightly to allow UI to render first
        checkUpdateTimer.start()

        // Show the window according to the user's preferences
        // Note: For maximized/fullscreen modes, we don't set width/height first
        // because that can interfere with the window state on Windows.
        if (SystemProperties.hasDesktopEnvironment) {
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED) {
                root.showMaximized()
            }
            else if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_FULLSCREEN) {
                root.showFullScreen()
            }
            else {
                // For windowed mode, set initial size before showing
                root.width = 1280
                root.height = 600
                root.show()
            }
        } else {
            root.showFullScreen()
        }

        // Display any modal dialogs for configuration warnings
        if (SystemProperties.isWow64) {
            wow64Dialog.open()
        }
        else if (!SystemProperties.hasHardwareAcceleration && StreamingPreferences.videoDecoderSelection !== StreamingPreferences.VDS_FORCE_SOFTWARE) {
            if (SystemProperties.isRunningXWayland) {
                xWaylandDialog.open()
            }
            else {
                noHwDecoderDialog.open()
            }
        }

        if (SystemProperties.unmappedGamepads) {
            unmappedGamepadDialog.unmappedGamepads = SystemProperties.unmappedGamepads
            unmappedGamepadDialog.open()
        }
    }

    // Use Connections to handle singleton signals globally
    Connections {
        target: AutoUpdateChecker

        function onUpdateAvailable(newVersion, url, isManual) {
            console.log("QML: Update available " + newVersion + " (manual: " + isManual + ")")
            updateButton.updateAvailable(newVersion, url, isManual)
        }

        function onNoUpdateAvailable(isManual) {
            console.log("QML: No update available (manual: " + isManual + ")")
            if (isManual) {
                console.log("QML: Opening noUpdateDialog")
                noUpdateDialog.open()
            }
        }

        function onUpdateCheckFailed(errorMessage, isManual) {
            console.log("QML: Update check failed: " + errorMessage + " (manual: " + isManual + ")")
            if (isManual) {
                updateErrorDialog.text = qsTr("Update check failed: %1").arg(errorMessage)
                updateErrorDialog.open()
            }
        }
    }

    function goBack() {
        if (clearOnBack) {
            // Pop all items except the first one
            stackView.pop(null)
            clearOnBack = false
        }
        else {
            stackView.pop()
        }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        focus: true

        // This configures the maximum width of the singleton attached QML ToolTip.
        // Must be inside an Item-derived component (StackView), not ApplicationWindow.
        ToolTip.toolTip.contentWidth: Math.min(tooltipTextLayoutHelper.width, 400)

        Component.onCompleted: {
            // Perform our early initialization before constructing
            // the initial view and pushing it to the StackView
            doEarlyInit()
            push("qrc:/gui/PcView.qml")
        }

        onCurrentItemChanged: {
            // Ensure focus travels to the next view when going back
            if (currentItem) {
                currentItem.forceActiveFocus()
            }

            // Force footer to hide immediately for StreamSegue/QuitSegue to prevent layout gap
            if (currentItem && (currentItem.objectName === "StreamSegue" ||
                currentItem.objectName === "QuitSegue")) {
                footerItem.shouldBeVisible = false
            } else {
                // Recalculate footer visibility for other views
                footerItem.shouldBeVisible = currentNetworkModel !== null && currentItem &&
                                             !(currentItem instanceof PcView)
            }

            // Update currentStackItem for Connections target
            updateCurrentStackItem()
            // Also update network model (in case signal was already emitted)
            Qt.callLater(updateCurrentNetworkModel)

            // Force layout recalculation to prevent bottom gap
            Qt.callLater(function() {
                stackView.update()
            })
        }

        // It would be better to use TextMetrics here, but it always lays out
        // the text slightly more compactly than real Text does in ToolTip,
        // causing unexpected line breaks to be inserted
        Text {
            id: tooltipTextLayoutHelper
            visible: false
            font: ToolTip.toolTip.font
            text: ToolTip.toolTip.text
        }

        Keys.onEscapePressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onBackPressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onMenuPressed: {
            settingsButton.clicked()
        }

        // This is a keypress we've reserved for letting the
        // SdlGamepadKeyNavigation object tell us to show settings
        // when Menu is consumed by a focused control.
        Keys.onHangupPressed: {
            settingsButton.clicked()
        }
    }

    // This timer keeps us polling for 5 minutes of inactivity
    // to allow the user to work with Moonlight on a second display
    // while dealing with configuration issues. This will ensure
    // machines come online even if the input focus isn't on Moonlight.
    Timer {
        id: inactivityTimer
        interval: 5 * 60000
        onTriggered: {
            if (!active && pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
    }

    Timer {
        id: checkUpdateTimer
        interval: 1000
        repeat: false
        onTriggered: AutoUpdateChecker.start(false)
    }

    onVisibleChanged: {
        // When we become invisible while streaming is going on,
        // stop polling immediately.
        if (!visible) {
            inactivityTimer.stop()

            if (pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
        else if (active) {
            // When we become visible and active again, start polling
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        if (active) {
            // Stop the inactivity timer
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }
        else {
            // Start the inactivity timer to stop polling
            // if focus does not return within a few minutes.
            inactivityTimer.restart()
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onClosing: {
        // Save preferences before closing to ensure settings like uiDisplayMode are preserved
        StreamingPreferences.save()
    }

    function navigateTo(url, objectType)
    {
        var existingItem = stackView.find(function(item, index) {
            return item instanceof objectType
        })

        if (existingItem !== null) {
            // Pop to the existing item
            stackView.pop(existingItem)
        }
        else {
            // Create a new item
            stackView.push(url)
        }
    }

    header: ToolBar {
        id: toolBar
        height: 60
        anchors.topMargin: 5
        anchors.bottomMargin: 5

        Label {
            id: titleLabel
            visible: toolBar.width > 700
            anchors.fill: parent
            text: stackView.currentItem.objectName
            font.pointSize: 20
            elide: Label.ElideRight
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
        }

        RowLayout {
            id: toolBarRowLayout
            spacing: 10
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.fill: parent

            NavigableToolButton {
                // Only make the button visible if the user has navigated somewhere.
                // Use opacity instead of visible to preserve layout space
                opacity: stackView.depth > 1 ? 1 : 0
                enabled: stackView.depth > 1

                iconSource: "qrc:/res/arrow_left.svg"

                onClicked: goBack()

                Keys.onDownPressed: {
                    if (stackView.currentItem) {
                        stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                    }
                }
            }

            // This label will appear when the window gets too small and
            // we need to ensure the toolbar controls don't collide
            Label {
                id: titleRowLabel
                font.pointSize: titleLabel.font.pointSize
                elide: Label.ElideRight
                horizontalAlignment: Qt.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true

                // We need this label to always be visible so it can occupy
                // the remaining space in the RowLayout. To "hide" it, we
                // just set the text to empty string.
                text: !titleLabel.visible ? (stackView.currentItem ? stackView.currentItem.objectName : "") : ""
            }

            NavigableToolButton {
                id: addPcButton
                visible: stackView.currentItem && stackView.currentItem instanceof PcView

                iconSource:  "qrc:/res/ic_add_to_queue_white_48px.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add PC manually") + (newPcShortcut.nativeText ? (" ("+newPcShortcut.nativeText+")") : "")

                Shortcut {
                    id: newPcShortcut
                    sequences: [StandardKey.New]
                    onActivated: addPcButton.clicked()
                }

                onClicked: {
                    addPcDialog.open()
                }

                Keys.onDownPressed: {
                    if (stackView.currentItem) {
                        stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                    }
                }
            }

            NavigableToolButton {
                property string browserUrl: ""

                id: updateButton

                iconSource: "qrc:/res/update.svg"

                Rectangle {
                    width: 10
                    height: 10
                    radius: width / 2
                    color: "red"
                    border.color: "white"
                    border.width: 1
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.bottomMargin: 10
                    anchors.rightMargin: 10
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Update Available")

                // Invisible until we get a callback notifying us that
                // an update is available
                visible: false

                onClicked: {
                    updateDialog.open()
                }

                function updateAvailable(version, url, isManual)
                {
                    updateButton.browserUrl = url
                    updateButton.visible = true

                    updateDialog.text = qsTr("A new version of DancherLink (%1) is available. Do you want to download it now?").arg(version)
                    updateDialog.updateUrl = url

                    // Only auto-open for manual checks; automatic checks show the toolbar badge only
                    if (isManual) {
                        updateDialog.open()
                    }
                }

                Keys.onDownPressed: {
                    if (stackView.currentItem) {
                        stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                    }
                }
            }

            NavigableToolButton {
                // Only show Gamepad Mapper when at least one gamepad is connected
                visible: SdlGamepadKeyNavigation.getConnectedGamepads() > 0

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Gamepad Mapper") + (SdlGamepadKeyNavigation.getConnectedGamepads() > 0 ? " (" + SdlGamepadKeyNavigation.getConnectedGamepads() + ")" : "")

                iconSource: "qrc:/res/ic_videogame_asset_white_48px.svg"

                onClicked: navigateTo("qrc:/gui/GamepadMapper.qml", GamepadMapper)

                Keys.onDownPressed: {
                    if (stackView.currentItem) {
                        stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                    }
                }
            }

            NavigableToolButton {
                id: settingsButton

                iconSource:  "qrc:/res/settings.svg"

                onClicked: navigateTo("qrc:/gui/SettingsView.qml", SettingsView)

                Keys.onDownPressed: {
                    if (stackView.currentItem) {
                        stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                    }
                }

                Shortcut {
                    id: settingsShortcut
                    sequences: [StandardKey.Preferences]
                    onActivated: settingsButton.clicked()
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Settings") + (settingsShortcut.nativeText ? (" ("+settingsShortcut.nativeText+")") : "")
            }

            // Version label - only visible on Settings page, placed at far right
            Label {
                id: versionLabel
                visible: stackView.currentItem && stackView.currentItem instanceof SettingsView
                text: qsTr("Version %1").arg(SystemProperties.versionString)
                font.pointSize: 12
                horizontalAlignment: Qt.AlignRight
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            }
        }
    }

    // Network latency indicator - fixed position at bottom center
    // Only shown in App View (not PC View) to avoid confusion when multiple PCs are listed
    footer: Item {
        id: footerItem

        // Only show footer in App View, not PC View (to avoid confusion about which PC it represents)
        // Also hide during streaming transitions (StreamSegue/QuitSegue) to avoid layout issues
        // Check by object name to reliably identify StreamSegue and QuitSegue
        property bool shouldBeVisible: currentNetworkModel !== null && stackView.currentItem &&
                                       !(stackView.currentItem instanceof PcView) &&
                                       stackView.currentItem.objectName !== "StreamSegue" &&
                                       stackView.currentItem.objectName !== "QuitSegue"

        // Use PropertyAnimation to smoothly hide/show footer and prevent visual glitches
        visible: shouldBeVisible
        height: visible ? 32 : 0
        onVisibleChanged: {
            // Force layout update to prevent gap during transitions
            if (!visible) {
                Qt.callLater(function() {
                    footerItem.height = 0
                    footerItem.anchors.bottomMargin = 0
                })
            }
        }

        Rectangle {
            id: networkIndicator
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            width: networkIndicatorRow.implicitWidth + 16
            radius: 4
            color: {
                var ms = currentNetworkModel ? currentNetworkModel.networkLatencyMs : -2
                if (ms < 0)   return "#555555"      // Unknown (gray)
                if (ms < 20)  return "#2E7D32"      // Good (green)
                if (ms < 50)  return "#F9A825"      // Fair (yellow)
                return "#C62828"                    // Poor (red)
            }

            Row {
                id: networkIndicatorRow
                anchors.centerIn: parent
                spacing: 6

                Label {
                    id: latencyLabel
                    text: {
                        if (!currentNetworkModel) return ""
                        var ms = currentNetworkModel.networkLatencyMs
                        if (ms === -2) return qsTr("Measuring...")  // Initial measurement in progress
                        if (ms === -1) return qsTr("Measuring...")  // Unknown/stopped
                        if (ms < 0)   return qsTr("N/A")
                        return ms + " ms"
                    }
                    color: "white"
                    font.pointSize: 10
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }

                Label {
                    id: qualityLabel
                    visible: currentNetworkModel !== null && currentNetworkModel.networkLatencyMs >= 0
                    text: {
                        if (!currentNetworkModel || currentNetworkModel.networkLatencyMs < 0) return ""
                        return currentNetworkModel.networkQualityString
                    }
                    color: "white"
                    font.pointSize: 9
                    verticalAlignment: Text.AlignVCenter
                }

                Label {
                    id: adaptiveLabel
                    visible: currentNetworkModel !== null && currentNetworkModel.networkLatencyMs >= 0 && StreamingPreferences.networkAdaptiveBitrate
                    text: {
                        if (!currentNetworkModel || currentNetworkModel.networkLatencyMs < 0 || !StreamingPreferences.networkAdaptiveBitrate) return ""
                        var ms = currentNetworkModel.networkLatencyMs
                        if (ms < 0) return ""

                        // Calculate FPS reduction based on RTT thresholds
                        // Poor (30-50ms): reduce 1 tier, Bad (>=50ms): reduce 2 tiers
                        var baseFps = StreamingPreferences.fps
                        var fpsReduced = baseFps
                        var fpsSteps = 0
                        if (ms >= 50) fpsSteps = 2
                        else if (ms >= 30) fpsSteps = 1

                        if (fpsSteps > 0 && baseFps > 30) {
                            // Standard FPS tiers: 30, 60, 90, 120, 144
                            // Match appmodel.cpp reduceFpsBySteps() logic
                            var fpsTiers = [30, 60, 90, 120, 144]
                            var tierIndex = 0
                            for (var i = 0; i < fpsTiers.length; i++) {
                                if (baseFps >= fpsTiers[i]) tierIndex = i
                            }
                            tierIndex -= fpsSteps
                            if (tierIndex < 0) tierIndex = 0
                            fpsReduced = fpsTiers[tierIndex]
                        }

                        // Calculate bitrate multiplier based on RTT
                        // Excellent <10ms, Good 10-20ms, Fair 20-30ms, Poor 30-50ms, Bad >=50ms
                        var mult = ms < 10 ? 1.00 : ms < 20 ? 0.90 : ms < 30 ? 0.70 : ms < 50 ? 0.50 : 0.30
                        var kbps = Math.max(2000, Math.floor(StreamingPreferences.bitrateKbps * mult))
                        kbps = Math.min(kbps, StreamingPreferences.bitrateKbps)
                        return " → " + fpsReduced + "fps / " + (kbps/1000).toFixed(0) + "M"
                    }
                    color: "#81C784"
                    font.pointSize: 9
                    verticalAlignment: Text.AlignVCenter
                }
            }

            HoverHandler {
                id: networkIndicatorHover
            }

            ToolTip.delay: 500
            ToolTip.timeout: 5000
            ToolTip.visible: networkIndicatorHover.hovered
            ToolTip.text: {
                if (!currentNetworkModel || currentNetworkModel.networkLatencyMs < 0) return ""
                var ms = currentNetworkModel.networkLatencyMs
                var quality = currentNetworkModel.networkQualityString
                var fps = StreamingPreferences.fps
                var bitrate = StreamingPreferences.bitrateKbps / 1000

                // Calculate adaptive FPS and bitrate based on RTT thresholds
                var fpsReduced = fps
                var fpsSteps = 0
                if (ms >= 50) fpsSteps = 2
                else if (ms >= 30) fpsSteps = 1

                if (fpsSteps > 0 && fps > 30) {
                    if (fps >= 144) fpsReduced = (fpsSteps >= 1) ? 120 : fps
                    else if (fps >= 120) fpsReduced = (fpsSteps >= 1) ? 90 : (fpsSteps >= 2) ? 60 : fps
                    else if (fps >= 90)  fpsReduced = (fpsSteps >= 1) ? 60 : (fpsSteps >= 2) ? 30 : fps
                    else if (fps >= 60)  fpsReduced = (fpsSteps >= 1) ? 30 : fps
                    if (fpsReduced < 30) fpsReduced = 30
                }

                var mult = ms < 10 ? 1.00 : ms < 20 ? 0.90 : ms < 30 ? 0.70 : ms < 50 ? 0.50 : 0.30
                var adaptiveBitrate = Math.max(2, Math.floor(bitrate * mult))
                adaptiveBitrate = Math.min(adaptiveBitrate, bitrate)

                if (StreamingPreferences.networkAdaptiveBitrate) {
                    return qsTr("Network Latency: %1 ms (%2)\nConfigured: %3fps / %4M\nAdaptive: %5fps / %6M")
                        .arg(ms).arg(quality).arg(fps).arg(bitrate.toFixed(0))
                        .arg(fpsReduced).arg(adaptiveBitrate.toFixed(0))
                } else {
                    return qsTr("Network Latency: %1 ms (%2)\nConfigured: %3fps / %4M")
                        .arg(ms).arg(quality).arg(fps).arg(bitrate.toFixed(0))
                }
            }
        }
    }

    ErrorMessageDialog {
        id: noHwDecoderDialog
        text: qsTr("No functioning hardware accelerated video decoder was detected by DancherLink. " +
                   "Your streaming performance may be severely degraded in this configuration.")
        helpText: qsTr("Click the Help button for more information on solving this problem.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    ErrorMessageDialog {
        id: xWaylandDialog
        text: qsTr("Hardware acceleration doesn't work on XWayland. Continuing on XWayland may result in poor streaming performance. " +
                   "Try running with QT_QPA_PLATFORM=wayland or switch to X11.")
        helpText: qsTr("Click the Help button for more information.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    NavigableMessageDialog {
        id: wow64Dialog
        standardButtons: Dialog.Ok | Dialog.Cancel
        text: qsTr("This version of DancherLink isn't optimized for your PC. Please download the '%1' version of DancherLink for the best streaming performance.").arg(SystemProperties.friendlyNativeArchName)
        onAccepted: {
            Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-qt/releases");
        }
    }

    ErrorMessageDialog {
        id: unmappedGamepadDialog
        property string unmappedGamepads : ""
        text: qsTr("DancherLink detected gamepads without a mapping:") + "\n" + unmappedGamepads
        helpTextSeparator: "\n\n"
        helpText: qsTr("Click the Help button for information on how to map your gamepads.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Gamepad-Mapping"
    }

    // This dialog appears when quitting via keyboard or gamepad button
    NavigableMessageDialog {
        id: quitConfirmationDialog
        standardButtons: Dialog.Yes | Dialog.No
        text: qsTr("Are you sure you want to quit?")
        // For keyboard/gamepad navigation
        onAccepted: Qt.quit()
    }

    NavigableMessageDialog {
        id: updateDialog
        property string updateUrl

        standardButtons: Dialog.Yes | Dialog.No
        title: qsTr("Update Available")

        onAccepted: {
            console.log("Attempting to open update URL: " + updateUrl)
            if (!AutoUpdateChecker.openUpdateUrl(updateUrl)) {
                console.warn("Failed to open update URL via AutoUpdateChecker: " + updateUrl)
                
                // Show an error dialog with the path
                // Try to clean up the path for display
                var displayPath = updateUrl
                if (displayPath.startsWith("file:///")) {
                    displayPath = displayPath.substring(8).replace(/\//g, "\\")
                } else if (displayPath.startsWith("file://")) {
                     displayPath = displayPath.substring(7).replace(/\//g, "\\")
                }
                
                updateErrorDialog.text = qsTr("Failed to open update file. Please manually navigate to:\n%1").arg(displayPath)
                updateErrorDialog.open()
            }
        }
    }

    NavigableMessageDialog {
        id: noUpdateDialog
        standardButtons: Dialog.Ok
        title: qsTr("No Update Available")
        text: qsTr("You are already running the latest version of DancherLink.")
    }

    NavigableMessageDialog {
        id: updateErrorDialog
        standardButtons: Dialog.Ok
        title: qsTr("Update Check Failed")
        // text set dynamically
    }

    InputDialog {
        id: addPcDialog
        label: qsTr("Enter the IP address of your host PC:")

        onValueAccepted: function(value) {
            ComputerManager.addNewHostManually(value)
        }
    }
}

