import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

import "."

import AppModel 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import StreamingPreferences 1.0

CenteredGridView {
    property int computerIndex
    property AppModel appModel : null
    property bool activated
    property bool showHiddenGames
    property bool showGames

    // Expose appModel as networkModel for direct binding in main.qml
    // This allows the network indicator to bind directly without relying on
    // QML's property change detection for dynamically assigned properties
    property var networkModel: appModel

    // CRITICAL: Track keyboard/gamepad selection independently from GridView's currentIndex
    // GridView automatically sets currentIndex when mouse interacts, which causes
    // the highlighted state to be always true. We use this separate property to
    // only highlight when using keyboard/gamepad navigation.
    property int keyboardSelectedIndex: -1

    id: appGrid
    focus: true
    activeFocusOnTab: true
    topMargin: 20
    bottomMargin: 5
    cellWidth: 230; cellHeight: 297;

    function computerLost()
    {
        // Go back to the PC view on PC loss
        stackView.pop()
    }

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1

        // Create the app model
        appModel = createModel()
        // Explicitly update networkModel to trigger bindings
        networkModel = appModel
    }

    StackView.onActivated: {
        if (!appModel) {
            console.error("[AppView] StackView.onActivated called but appModel is null")
            return
        }

        appModel.computerLost.connect(computerLost)
        activated = true

        // Start latency measurement when entering the app list
        appModel.startLatencyMeasurement()

        // CRITICAL: Do NOT auto-select the first app!
        // Setting currentIndex = 0 causes the first card's 'highlighted' property
        // to be always true, which looks like hover is triggered everywhere.
        // Keep currentIndex = -1 until the user actually interacts with the UI.

        if (!showGames && !showHiddenGames) {
            // Check if there's a direct launch app
            var directLaunchAppIndex = appModel.getDirectLaunchAppIndex();
            if (directLaunchAppIndex >= 0) {
                // Start the direct launch app if nothing else is running
                currentIndex = directLaunchAppIndex
                if (currentItem) {
                    currentItem.launchOrResumeSelectedApp(false)
                }

                // Set showGames so we will not loop when the stream ends
                showGames = true
            }
        }
    }

    StackView.onDeactivating: {
        if (appModel) {
            appModel.computerLost.disconnect(computerLost)
            // Stop latency measurement when leaving the app list
            appModel.stopLatencyMeasurement()
        }
        activated = false
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import AppModel 1.0; AppModel {}', parent, '')
        if (!model) {
            console.error("Failed to create AppModel")
            return null
        }
        model.initialize(ComputerManager, computerIndex, showHiddenGames)
        return model
    }

    model: appModel

    delegate: NavigableItemDelegate {
        id: delegateRoot
        // CRITICAL: Match cellWidth/cellHeight from GridView (230x297)
        width: appGrid.cellWidth
        height: appGrid.cellHeight
        grid: appGrid
        cardIndex: index  // CRITICAL: Pass index to NavigableItemDelegate for keyboardSelectedIndex check

        property alias appContextMenu: appContextMenuLoader.item
        property alias appNameText: appNameTextLoader.item

        // Dim the app if it's hidden
        opacity: model.hidden ? 0.4 : 1.0

        // Image content
        Image {
            property bool isPlaceholder: false

            id: appIcon
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10
            source: model.boxart

            onSourceSizeChanged: {
                // Nearly all of Nvidia's official box art does not match the dimensions of placeholder
                // images, however the one known exception is Overcooked. Therefore, we only execute
                // the image size checks if this is not an app collector game. We know the officially
                // supported games all have box art, so this check is not required.
                if (!model.isAppCollectorGame &&
                    ((sourceSize.width === 130 && sourceSize.height === 180) || // GFE 2.0 placeholder image
                     (sourceSize.width === 628 && sourceSize.height === 888) || // GFE 3.0 placeholder image
                     (sourceSize.width === 200 && sourceSize.height === 266)))  // Our no_app_image.png
                {
                    isPlaceholder = true
                }
                else
                {
                    isPlaceholder = false
                }

                width = 200
                height = 267
            }

            // Display a tooltip with the full name if it's truncated
            ToolTip.text: model.name
            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: (delegateRoot.isHovered || delegateRoot.customHighlighted) && (!appNameText || appNameText.truncated)
        }

        Loader {
            active: model.running
            asynchronous: true
            anchors.fill: appIcon

            sourceComponent: Item {
                RoundButton {
                    id: resumeButton
                    anchors.horizontalCenterOffset: appIcon.isPlaceholder ? -47 : 0
                    anchors.verticalCenterOffset: appIcon.isPlaceholder ? -75 : -60
                    anchors.centerIn: parent
                    implicitWidth: 85
                    implicitHeight: 85
                    hoverEnabled: true

                    icon.source: "qrc:/res/play_arrow_FILL1_wght700_GRAD200_opsz48.svg"
                    icon.width: 75
                    icon.height: 75

                    // Scale animation for hover effect
                    scale: 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: AppTheme.animationDurationFast
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Visual feedback on hover
                    Material.elevation: hovered ? 4 : 1
                    Material.background: hovered ? "#E0A0A0A0" : "#D0808080"

                    // CRITICAL: Signal hover state to parent card
                    // When button is hovered, set parent's childHovered property
                    onHoveredChanged: {
                        var p = resumeButton.parent
                        while (p && p.childHovered === undefined) p = p.parent
                        if (p) p.childHovered = hovered
                    }

                    onClicked: {
                        launchOrResumeSelectedApp(true)
                    }

                    ToolTip.text: qsTr("Resume Game")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered
                }

                RoundButton {
                    id: quitButton
                    anchors.horizontalCenterOffset: appIcon.isPlaceholder ? 47 : 0
                    anchors.verticalCenterOffset: appIcon.isPlaceholder ? -75 : 60
                    anchors.centerIn: parent
                    implicitWidth: 85
                    implicitHeight: 85
                    hoverEnabled: true

                    icon.source: "qrc:/res/stop_FILL1_wght700_GRAD200_opsz48.svg"
                    icon.width: 75
                    icon.height: 75

                    // Scale animation for hover effect
                    scale: 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: AppTheme.animationDurationFast
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Visual feedback on hover
                    Material.elevation: hovered ? 4 : 1
                    Material.background: hovered ? "#E0A0A0A0" : "#D0808080"

                    // CRITICAL: Signal hover state to parent card
                    // When button is hovered, set parent's childHovered property
                    onHoveredChanged: {
                        var p = quitButton.parent
                        while (p && p.childHovered === undefined) p = p.parent
                        if (p) p.childHovered = hovered
                    }

                    onClicked: {
                        doQuitGame()
                    }

                    ToolTip.text: qsTr("Quit Game")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered
                }
            }
        }

        Loader {
            id: appNameTextLoader
            active: appIcon.isPlaceholder

            // This loader is not asynchronous to avoid noticeable differences
            // in the time in which the text loads for each game.

            width: appIcon.width
            height: model.running ? 175 : appIcon.height

            anchors.left: appIcon.left
            anchors.right: appIcon.right
            anchors.bottom: appIcon.bottom

            sourceComponent: Label {
                id: appNameText
                text: model.name
                font.pointSize: 22
                leftPadding: 20
                rightPadding: 20
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
            }
        }

        // Internal helper to create StreamSegue with specified previousVisibility.
        // This is used both for initial launch and for restarts (e.g. resolution change).
        // The previousVisibility parameter is critical for restoring the correct window state
        // after streaming ends - it must be the window state from BEFORE streaming started,
        // not the state captured during the stream (which may be fullscreen).
        function createStreamSegue(runningId, previousVisibility)
        {
            var component = Qt.createComponent("StreamSegue.qml")
            if (component.status !== Component.Ready) {
                console.error("Failed to create StreamSegue component:", component.errorString())
                return null
            }

            var segue = component.createObject(stackView, {
                                                   "appName": model.name,
                                                   "session": appModel.createSessionForApp(model.index),
                                                   "isResume": runningId === model.appid,
                                                   "previousVisibility": previousVisibility
                                               })

            if (!segue) {
                console.error("component.createObject returned null")
                return null
            }

            // Save the original previousVisibility before any restarts occur.
            // This is critical for resolution-change restarts: we must preserve
            // the original window state (from before streaming started) across
            // the restart, not capture the state during streaming (which may be
            // fullscreen due to the splash screen).
            var originalPreviousVisibility = segue.previousVisibility

            // When a restart is requested (e.g. resolution change), we destroy the old session
            // and create a brand new one. This avoids complex state reset logic in C++ and
            // ensures we start with a clean slate.
            segue.restartRequested.connect(function() {
                // Pop the old segue immediately. This will trigger the destruction of the old Session.
                stackView.pop(StackView.Immediate)

                // Start a new session for the same app.
                // Pass the ORIGINAL previousVisibility to ensure window state is restored correctly
                // after the stream ends, even after multiple restarts.
                launchOrResumeSelectedAppWithVisibility(false, originalPreviousVisibility)
            })

            // Handle delayed restart after resolution debounce during restart
            // This happens when a new resolution change is detected while we're already restarting
            segue.delayedRestartRequested.connect(function(width, height) {
                console.log("Delayed restart requested after resolution debounce: " + width + "x" + height)
                // Pop the old segue
                stackView.pop(StackView.Immediate)
                // Wait a bit for the pop to complete, then create a new session
                // Capture the value before the closure since segue will be destroyed
                var savedPreviousVisibility = originalPreviousVisibility
                Qt.callLater(function() {
                    launchOrResumeSelectedAppWithVisibility(false, savedPreviousVisibility)
                })
            })

            return segue
        }

        function launchOrResumeSelectedAppWithVisibility(quitExistingApp, previousVisibility)
        {
            var runningId = appModel.getRunningAppId()
            if (runningId !== 0 && runningId !== model.appid) {
                if (quitExistingApp) {
                    quitAppDialog.appName = appModel.getRunningAppName()
                    quitAppDialog.segueToStream = true
                    quitAppDialog.nextAppName = model.name
                    quitAppDialog.nextAppIndex = index
                    quitAppDialog.open()
                }

                return
            }

            var segue = createStreamSegue(runningId, previousVisibility)
            if (segue) {
                stackView.push(segue)
            }
        }

        function launchOrResumeSelectedApp(quitExistingApp)
        {
            // For initial launch, capture the current window visibility
            launchOrResumeSelectedAppWithVisibility(quitExistingApp, stackView.Window.visibility)
        }

        onClicked: {
            // Only allow clicking on the box art for non-running games.
            // For running games, buttons will appear to resume or quit which
            // will handle starting the game and clicks on the box art will
            // be ignored.
            if (!model.running) {
                launchOrResumeSelectedApp(true)
            }
        }

        onPressAndHold: {
            // popup() ensures the menu appears under the mouse cursor
            if (appContextMenu.popup) {
                appContextMenu.popup()
            }
            else {
                // Qt 5.9 doesn't have popup()
                appContextMenu.open()
            }
        }

        // Right-click menu MouseArea
        MouseArea {
            id: rightClickMouseArea
            anchors.fill: delegateRoot
            acceptedButtons: Qt.RightButton
            onClicked: {
                delegateRoot.pressAndHold()
            }
        }

        Keys.onReturnPressed: {
            // Open the app context menu if activated via the gamepad or keyboard
            // for running games. If the game isn't running, the above onClicked
            // method will handle the launch.
            if (model.running) {
                // This will be keyboard/gamepad driven so use
                // open() instead of popup()
                appContextMenu.open()
            }
        }

        Keys.onEnterPressed: {
            // Open the app context menu if activated via the gamepad or keyboard
            // for running games. If the game isn't running, the above onClicked
            // method will handle the launch.
            if (model.running) {
                // This will be keyboard/gamepad driven so use
                // open() instead of popup()
                appContextMenu.open()
            }
        }

        Keys.onMenuPressed: {
            // This will be keyboard/gamepad driven so use open() instead of popup()
            appContextMenu.open()
        }

        function doQuitGame() {
            quitAppDialog.appName = appModel.getRunningAppName()
            quitAppDialog.segueToStream = false
            quitAppDialog.open()
        }

        Loader {
            id: appContextMenuLoader
            asynchronous: true
            sourceComponent: NavigableMenu {
                id: appContextMenu
                NavigableMenuItem {
                    text: model.running ? qsTr("Resume Game") : qsTr("Launch Game")
                    onTriggered: launchOrResumeSelectedApp(true)
                }
                NavigableMenuItem {
                    text: qsTr("Quit Game")
                    onTriggered: doQuitGame()
                    visible: model.running
                }
                NavigableMenuItem {
                    checkable: true
                    checked: model.directLaunch
                    text: qsTr("Direct Launch")
                    onTriggered: appModel.setAppDirectLaunch(model.index, !model.directLaunch)
                    enabled: !model.hidden

                    ToolTip.text: qsTr("Launch this app immediately when the host is selected, bypassing the app selection grid.")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered
                }
                NavigableMenuItem {
                    checkable: true
                    checked: model.hidden
                    text: qsTr("Hide Game")
                    onTriggered: appModel.setAppHidden(model.index, !model.hidden)
                    enabled: model.hidden || (!model.running && !model.directLaunch)

                    ToolTip.text: qsTr("Hide this game from the app grid. To access hidden games, right-click on the host and choose %1.").arg(qsTr("View All Apps"))
                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                }
                NavigableMenuItem {
                    text: qsTr("Create Desktop Shortcut")
                    onTriggered: appModel.createDesktopShortcut(model.index)
                    enabled: !model.hidden
                }
            }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: appGrid.count === 0

        Label {
            text: qsTr("This computer doesn't seem to have any applications or some applications are hidden")
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    NavigableMessageDialog {
        id: quitAppDialog
        property string appName : ""
        property bool segueToStream : false
        property string nextAppName: ""
        property int nextAppIndex: 0
        text:qsTr("Are you sure you want to quit %1? Any unsaved progress will be lost.").arg(appName)
        standardButtons: Dialog.Yes | Dialog.No

        function quitApp() {
            // Stop latency measurement before starting stream
            appModel.stopLatencyMeasurement()

            var component = Qt.createComponent("QuitSegue.qml")
            if (component.status !== Component.Ready) {
                console.error("Failed to create QuitSegue component:", component.errorString())
                return
            }
            var params = {"appName": appName, "quitRunningAppFn": function() { appModel.quitRunningApp() }}
            if (segueToStream) {
                // Store the session and app name if we're going to stream after
                // successfully quitting the old app.
                params.nextAppName = nextAppName
                params.nextSession = appModel.createSessionForApp(nextAppIndex)
            }
            else {
                params.nextAppName = null
                params.nextSession = null
            }

            var segue = component.createObject(stackView, params)
            if (!segue) {
                console.error("Failed to create QuitSegue object")
                return
            }
            stackView.push(segue)
        }

        onAccepted: quitApp()
    }

    ScrollBar.vertical: ScrollBar {}
}

