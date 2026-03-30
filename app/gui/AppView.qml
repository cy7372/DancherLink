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

    id: appGrid
    focus: true
    activeFocusOnTab: true
    topMargin: AppTheme.spacingLg
    bottomMargin: AppTheme.spacingSm
    cellWidth: AppTheme.appCardWidth; cellHeight: AppTheme.appCardHeight;

    // Performance optimizations
    cacheBuffer: 400  // Cache extra items off-screen for smoother scrolling
    reuseItems: true  // Reuse delegate items instead of creating/destroying

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

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }

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
        width: AppTheme.appCardWidth - 8; height: AppTheme.appCardHeight - 8;
        grid: appGrid

        property alias appContextMenu: appContextMenuLoader.item
        property alias appNameText: appNameTextLoader.item

        // Dim the app if it's hidden
        opacity: model.hidden ? 0.4 : 1.0

        background: Rectangle {
            id: delegateBackground
            color: AppTheme.backgroundPrimary
            border.color: "transparent"
            border.width: 0
            radius: AppTheme.borderRadius

            states: [
                State {
                    name: "highlighted"
                    when: delegateRoot.highlighted
                    PropertyChanges { target: delegateBackground; color: AppTheme.backgroundHighlighted }
                },
                State {
                    name: "hovered"
                    when: delegateRoot.hovered && !delegateRoot.highlighted
                    PropertyChanges { target: delegateBackground; color: AppTheme.backgroundHover }
                }
            ]

            transitions: [
                Transition {
                    ColorAnimation { duration: AppTheme.animationDurationFast }
                }
            ]
        }

        Image {
            property bool isPlaceholder: false

            id: appIcon
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: AppTheme.spacingSm
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

                width = AppTheme.appIconWidth
                height = AppTheme.appIconHeight
            }

            // Display a tooltip with the full name if it's truncated
            ToolTip.text: model.name
            ToolTip.delay: 1000
            ToolTip.timeout: 5000
            ToolTip.visible: (parent.hovered || parent.highlighted) && (!appNameText || appNameText.truncated)
        }

        Loader {
            active: model.running
            asynchronous: true
            anchors.fill: appIcon

            sourceComponent: Item {
                RoundButton {
                    id: resumeButton
                    // Using explicit x/y positioning instead of anchors to allow dynamic offset
                    x: (parent.width - width) / 2 + (appIcon.isPlaceholder ? -40 : 0)
                    y: (parent.height - height) / 2 + (appIcon.isPlaceholder ? -64 : -48)
                    implicitWidth: 72
                    implicitHeight: 72

                    icon.source: "qrc:/res/play_arrow_FILL1_wght700_GRAD200_opsz48.svg"
                    icon.width: 56
                    icon.height: 56

                    onClicked: {
                        launchOrResumeSelectedApp(true)
                    }

                    ToolTip.text: qsTr("Resume Game")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered

                    Material.background: "#D0808080"

                    Behavior on x { PropertyAnimation { duration: 150 } }
                    Behavior on y { PropertyAnimation { duration: 150 } }
                }

                RoundButton {
                    id: stopButton
                    // Using explicit x/y positioning instead of anchors to allow dynamic offset
                    x: (parent.width - width) / 2 + (appIcon.isPlaceholder ? 40 : 0)
                    y: (parent.height - height) / 2 + (appIcon.isPlaceholder ? 48 : 48)
                    implicitWidth: 72
                    implicitHeight: 72

                    icon.source: "qrc:/res/stop_FILL1_wght700_GRAD200_opsz48.svg"
                    icon.width: 56
                    icon.height: 56

                    onClicked: {
                        doQuitGame()
                    }

                    ToolTip.text: qsTr("Quit Game")
                    ToolTip.delay: 1000
                    ToolTip.timeout: 3000
                    ToolTip.visible: hovered

                    Material.background: "#D0808080"

                    Behavior on x { PropertyAnimation { duration: 150 } }
                    Behavior on y { PropertyAnimation { duration: 150 } }
                }
            }
        }

        Loader {
            id: appNameTextLoader
            active: appIcon.isPlaceholder

            // This loader is not asynchronous to avoid noticeable differences
            // in the time in which the text loads for each game.

            width: appIcon.width - AppTheme.spacingMd
            height: model.running ? 144 : appIcon.height

            anchors.left: appIcon.left
            anchors.right: appIcon.right
            anchors.bottom: appIcon.bottom

            sourceComponent: Label {
                id: appNameText
                text: model.name
                font.pointSize: AppTheme.fontBody
                leftPadding: AppTheme.spacingSm
                rightPadding: AppTheme.spacingSm
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
            }
        }

        function launchOrResumeSelectedApp(quitExistingApp)
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

            var component = Qt.createComponent("StreamSegue.qml")
            if (component.status !== Component.Ready) {
                console.error("Failed to create StreamSegue component:", component.errorString())
                return
            }

            var segue = component.createObject(stackView, {
                                                   "appName": model.name,
                                                   "session": appModel.createSessionForApp(model.index),
                                                   "isResume": runningId === model.appid,
                                                   "previousVisibility": stackView.Window.visibility
                                               })

            if (!segue) {
                console.error("component.createObject returned null")
                return
            }

            // Stop latency measurement during streaming to save resources
            appModel.stopLatencyMeasurement()

            // When a restart is requested (e.g. resolution change), we destroy the old session
            // and create a brand new one. This avoids complex state reset logic in C++ and
            // ensures we start with a clean slate.
            segue.restartRequested.connect(function() {
                // Pop the old segue immediately. This will trigger the destruction of the old Session.
                stackView.pop(StackView.Immediate)

                // Start a new session for the same app.
                // launchOrResumeSelectedApp will create a new Session object.
                launchOrResumeSelectedApp(false)
            })

            stackView.push(segue)
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

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton;
            onClicked: {
                parent.pressAndHold()
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
        spacing: AppTheme.spacingSm
        visible: appGrid.count === 0

        Label {
            text: qsTr("This computer doesn't seem to have any applications or some applications are hidden")
            font.pointSize: AppTheme.fontSubtitle
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
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

    // Network latency indicator footer - similar to PC list page
    footer: Item {
        visible: networkLatencyBadge.visible
        height: 40

        Rectangle {
            id: networkLatencyBadge
            visible: appModel.networkLatencyMs >= 0 && activated
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: latencyRow.implicitWidth + AppTheme.spacingMd
            height: 32
            radius: AppTheme.borderRadius
            opacity: 0.9

            // Cache latency value to reduce binding updates
            property int cachedLatency: appModel.networkLatencyMs

            color: {
                var ms = cachedLatency
                if (ms < 0)   return "#555555"      // Unknown (gray)
                if (ms < 20)  return "#2E7D32"      // Good (green)
                if (ms < 50)  return "#F9A825"      // Fair (yellow)
                return "#C62828"                    // Poor (red)
            }

            Row {
                id: latencyRow
                anchors.centerIn: parent
                spacing: AppTheme.spacingSm

                Label {
                    text: qsTr("Network:")
                    color: "white"
                    font.pointSize: AppTheme.fontCaption
                    font.bold: true
                }

                Label {
                    text: cachedLatency + " ms"
                    color: "white"
                    font.pointSize: AppTheme.fontCaption
                }

                Label {
                    text: "|"
                    color: "white"
                    font.pointSize: AppTheme.fontCaption
                }

                Label {
                    text: appModel.networkQualityString
                    color: "white"
                    font.pointSize: AppTheme.fontCaption
                }
            }

            ToolTip.visible: latencyMouseArea.containsMouse
            ToolTip.text: qsTr("Network latency to the host PC")
            ToolTip.delay: 500

            MouseArea {
                id: latencyMouseArea
                anchors.fill: parent
                hoverEnabled: true
            }
        }
    }

    ScrollBar.vertical: ScrollBar {}
}

