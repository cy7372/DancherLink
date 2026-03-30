import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import "."

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0

CenteredGridView {
    property ComputerModel computerModel : null
    property bool modelReady : false  // Set to true when model is ready

    id: pcGrid
    focus: true
    activeFocusOnTab: true
    topMargin: 20
    bottomMargin: 5
    cellWidth: 310; cellHeight: 330;
    objectName: qsTr("Computers")

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1

        // Create the computer model FIRST
        computerModel = createModel()

        // Set modelReady AFTER computerModel is created
        // This triggers delegate rebuild with valid model reference
        Qt.callLater(function() {
            modelReady = true
            pcGrid.model = computerModel
        })
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)

        // If no selection and we have computers, select the first one
        if (currentIndex === -1 && computerModel && computerModel.rowCount() > 0) {
            currentIndex = 0
        }

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }

        // Start latency measurement for selected computer
        if (currentIndex >= 0 && computerModel) {
            computerModel.startLatencyMeasurement(currentIndex)
        }

        // Force refresh the latency badge by toggling modelReady
        // This ensures the Loader recreates the component with fresh bindings
        if (modelReady && computerModel && computerModel.rowCount() > 0) {
            modelReady = false
            Qt.callLater(function() {
                modelReady = true
            })
        }
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
        // Stop latency measurement when leaving the page
        if (computerModel) {
            computerModel.stopLatencyMeasurement()
        }
    }

    onCurrentIndexChanged: {
        // Start measuring latency for the newly selected computer
        if (currentIndex >= 0 && computerModel) {
            computerModel.startLatencyMeasurement(currentIndex)
        }
    }

    function pairingComplete(error)
    {
        // Close the PIN dialog
        pairDialog.close()

        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.helpText = ""
            errorDialog.open()
        }
    }

    function addComplete(success, detectedPortBlocking)
    {
        if (!success) {
            errorDialog.text = qsTr("Unable to connect to the specified PC.")

            if (detectedPortBlocking) {
                errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking DancherLink. Streaming over the Internet may not work while connected to this network.")
            }
            else {
                errorDialog.helpText = qsTr("Click the Help button for possible solutions.")
            }

            errorDialog.open()
        }
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', parent, '')
        if (!model) {
            console.error("Failed to create ComputerModel")
            return null
        }
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    // Don't set model here - we'll set it in Component.onCompleted after computerModel is created
    // This ensures delegates see a valid computerModel from the start

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: pcGrid.count === 0

        BusyIndicator {
            id: searchSpinner
            visible: StreamingPreferences.enableMdns
            running: visible
        }

        Label {
            height: searchSpinner.height
            elide: Label.ElideRight
            text: StreamingPreferences.enableMdns ? qsTr("Searching for compatible hosts on your local network...")
                                                  : qsTr("Automatic PC discovery is disabled. Add your PC manually.")
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    // model property removed - set dynamically in Component.onCompleted
    // This ensures delegates see a valid computerModel from the start

    delegate: NavigableItemDelegate {
        id: delegateRoot
        width: 300; height: 320;
        grid: pcGrid

        property alias pcContextMenu : pcContextMenuLoader.item

        // Local hover state - only true when mouse is over the card
        property bool isHovered: false

        background: Rectangle {
            id: delegateBackground
            anchors.fill: parent
            color: delegateRoot.highlighted ? AppTheme.backgroundHighlighted : (delegateRoot.isHovered ? AppTheme.backgroundHover : "transparent")
            border.color: "transparent"
            border.width: 0
            radius: AppTheme.borderRadius

            Behavior on color { ColorAnimation { duration: AppTheme.animationDurationFast } }

            Component.onCompleted: {
                console.log("[PcView] background created - parent:", parent, "parent.width:", parent.width, "parent.height:", parent.height, "this.width:", width, "this.height:", height)
            }
            onWidthChanged: {
                console.log("[PcView] background width changed:", width, "parent.width:", parent.width)
            }
            onHeightChanged: {
                console.log("[PcView] background height changed:", height, "parent.height:", parent.height)
            }
        }

        // Image content
        Image {
            id: pcIcon
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/res/desktop_windows-48px.svg"
            sourceSize {
                width: 200
                height: 200
            }
        }

        // Network latency indicator - shows for currently selected PC
        // Created in a Loader to ensure fresh bindings when model is ready
        Loader {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            // Reload component when currentIndex changes or modelReady changes
            active: pcGrid.modelReady && model.online
            visible: index === pcGrid.currentIndex
            sourceComponent: Rectangle {
                id: latencyBadge
                width: latencyLabel.implicitWidth + 12
                height: 24
                radius: 4
                color: {
                    var modelRef = pcGrid.model
                    if (!modelRef) return "#555555"
                    var ms = modelRef.networkLatencyMs
                    if (ms < 0) return "#555555"
                    if (ms < 20) return "#2E7D32"
                    if (ms < 50) return "#F9A825"
                    return "#C62828"
                }
                opacity: 0.9

                Label {
                    id: latencyLabel
                    anchors.centerIn: parent
                    text: {
                        var modelRef = pcGrid.model
                        if (!modelRef) return "--"
                        var ms = modelRef.networkLatencyMs
                        if (ms < 0) return "--"
                        return ms + " ms"
                    }
                    color: "white"
                    font.pointSize: 10
                    font.bold: true
                }

                ToolTip.visible: latencyMouseArea.containsMouse && pcGrid.model
                ToolTip.text: pcGrid.model ? pcGrid.model.networkQualityString : ""
                ToolTip.delay: 500

                MouseArea {
                    id: latencyMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
        }

        // Invisible placeholder to maintain layout when Loader is inactive
        Item {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: latencyLabel.implicitWidth + 12
            height: 24
            visible: false
        }

        // Connect to computerModel's networkLatencyChanged signal to ensure UI updates
        // Use pcGrid.computerModel directly with proper null checking
        Connections {
            target: pcGrid.computerModel
            function onNetworkLatencyChanged() {
                // This ensures the delegate is notified when latency changes
                // Use Qt.callLater to update UI after binding re-evaluation
                Qt.callLater(function() {
                    if (latencyBadge) {
                        latencyBadge.opacity = latencyBadge.opacity
                    }
                })
            }
        }

        Image {
            id: stateIcon
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: !model.online ? -18 : -16
            visible: !model.statusUnknown && (!model.online || !model.paired)
            source: !model.online ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-lock-24px.svg"
            sourceSize {
                width: !model.online ? 75 : 70
                height: !model.online ? 75 : 70
            }

            ToolTip.visible: stateIconMouseArea.containsMouse && stateIcon.visible
            ToolTip.text: !model.online ? qsTr("PC is offline") : qsTr("PC is not paired")
            ToolTip.delay: 500

            MouseArea {
                id: stateIconMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton  // Don't intercept clicks
            }
        }

        BusyIndicator {
            id: statusUnknownSpinner
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: -15
            width: 75
            height: 75
            visible: model.statusUnknown
            running: visible
        }

        Label {
            id: pcNameText
            text: model.name

            width: parent.width
            anchors.top: pcIcon.bottom
            anchors.bottom: parent.bottom
            font.pointSize: 36
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideRight
        }

        Loader {
            id: pcContextMenuLoader
            asynchronous: true
            sourceComponent: NavigableMenu {
                id: pcContextMenu
                MenuItem {
                    text: qsTr("PC Status: %1").arg(model.online ? qsTr("Online") : qsTr("Offline"))
                    font.bold: true
                    enabled: false
                }
                NavigableMenuItem {
                    text: qsTr("View All Apps")
                    onTriggered: {
                        var component = Qt.createComponent("AppView.qml")
                        if (component.status !== Component.Ready) {
                            console.error("Failed to create AppView component:", component.errorString())
                            return
                        }
                        var appView = component.createObject(stackView, {"computerIndex": index, "objectName": model.name, "showHiddenGames": true})
                        if (!appView) {
                            console.error("Failed to create AppView object")
                            return
                        }
                        stackView.push(appView)
                    }
                    visible: model.online && model.paired
                }
                NavigableMenuItem {
                    text: qsTr("Wake PC")
                    onTriggered: {
                        if (computerModel) {
                            computerModel.wakeComputer(index)
                        }
                    }
                    visible: !model.online && model.wakeable
                }
                NavigableMenuItem {
                    text: qsTr("Test Network")
                    onTriggered: {
                        if (computerModel) {
                            computerModel.testConnectionForComputer(index)
                            testConnectionDialog.open()
                        }
                    }
                }

                NavigableMenuItem {
                    text: qsTr("Rename PC")
                    onTriggered: {
                        renamePcDialog.pcIndex = index
                        renamePcDialog.placeholderText = model.name
                        renamePcDialog.open()
                    }
                }
                NavigableMenuItem {
                    text: qsTr("Delete PC")
                    onTriggered: {
                        deletePcDialog.pcIndex = index
                        deletePcDialog.pcName = model.name
                        deletePcDialog.open()
                    }
                }
                NavigableMenuItem {
                    text: qsTr("View Details")
                    onTriggered: {
                        showPcDetailsDialog.pcDetails = model.details
                        showPcDetailsDialog.open()
                    }
                }
            }
        }

        onClicked: {
            if (model.online) {
            if (!model.serverSupported) {
                errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of DancherLink. You must update DancherLink to stream from %1.").arg(model.name)
                errorDialog.helpText = ""
                errorDialog.open()
            }
                else if (model.paired) {
                    // go to game view
                    var component = Qt.createComponent("AppView.qml")
                    if (component.status !== Component.Ready) {
                        console.error("Failed to create AppView component:", component.errorString())
                        return
                    }
                    var appView = component.createObject(stackView, {"computerIndex": index, "objectName": model.name})
                    if (!appView) {
                        console.error("Failed to create AppView object")
                        return
                    }
                    stackView.push(appView)
                }
                else {
                    if (!computerModel) {
                        console.error("[PcView] Cannot pair: computerModel is null")
                        return
                    }
                    var pin = computerModel.generatePinString()

                    // Kick off pairing in the background
                    computerModel.pairComputer(index, pin)

                    // Display the pairing dialog
                    pairDialog.pin = pin
                    pairDialog.open()
                }
            } else if (!model.online) {
                // Using open() here because it may be activated by keyboard
                pcContextMenu.open()
            }
        }

        onPressAndHold: {
            // popup() ensures the menu appears under the mouse cursor
            if (pcContextMenu.popup) {
                pcContextMenu.popup()
            }
            else {
                // Qt 5.9 doesn't have popup()
                pcContextMenu.open()
            }
        }

        // Hover detection MouseArea - MUST be after all other visual elements to receive events
        MouseArea {
            id: hoverMouseArea
            anchors.fill: delegateRoot
            hoverEnabled: true
            acceptedButtons: Qt.NoButton

            // CRITICAL: Accept all mouse events to prevent Flickable (GridView) from intercepting them
            onPressed: { mouse.accepted = true }
            onReleased: { mouse.accepted = true }
            onPositionChanged: { mouse.accepted = true }
            // Also prevent wheel events from propagating to Flickable
            onWheel: { wheel.accepted = true }

            // Debug: Track containsMouse changes
            onContainsMouseChanged: {
                console.log("[PcView] hoverMouseArea containsMouse changed to:", containsMouse)
            }

            onEntered: {
                console.log("[PcView] hover ENTERED - MouseArea size:", width, "x", height, "delegateRoot size:", delegateRoot.width, "x", delegateRoot.height)
                delegateRoot.isHovered = true
            }
            onExited: {
                console.log("[PcView] hover EXITED")
                delegateRoot.isHovered = false
            }
        }

        MouseArea {
            id: rightClickMouseArea
            anchors.fill: delegateRoot
            acceptedButtons: Qt.RightButton
            onClicked: {
                delegateRoot.pressAndHold()
            }
        }

        Keys.onMenuPressed: {
            // We must use open() here so the menu is positioned on
            // the ItemDelegate and not where the mouse cursor is
            pcContextMenu.open()
        }

        Keys.onDeletePressed: {
            deletePcDialog.pcIndex = index
            deletePcDialog.pcName = model.name
            deletePcDialog.open()
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        // Using Setup-Guide here instead of Troubleshooting because it's likely that users
        // will arrive here by forgetting to enable GameStream or not forwarding ports.
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
    }

    NavigableMessageDialog {
        id: pairDialog

        // Pairing dialog must be modal to prevent double-clicks from triggering
        // pairing twice
        modal: true
        closePolicy: Popup.CloseOnEscape

        // don't allow edits to the rest of the window while open
        property string pin : "0000"
        text:qsTr("Please enter %1 on your host PC. This dialog will close when pairing is completed.").arg(pin)+"\n\n"+
             qsTr("If your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
        standardButtons: Dialog.Cancel
        onRejected: {
            // Cancel the pending pairing operation in the model
            computerModel.cancelPairing()
        }
    }

    NavigableMessageDialog {
        id: deletePcDialog
        // don't allow edits to the rest of the window while open
        property int pcIndex : -1
        property string pcName : ""
        text: qsTr("Are you sure you want to remove '%1'?").arg(pcName)
        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            computerModel.deleteComputer(pcIndex)
        }
    }

    NavigableMessageDialog {
        id: testConnectionDialog
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok

        onAboutToShow: {
            testConnectionDialog.text = qsTr("DancherLink is testing your network connection to determine if any required ports are blocked.") + "\n\n" + qsTr("This may take a few seconds...")
            showSpinner = true
        }

        function connectionTestComplete(result, blockedPorts)
        {
            if (result === -1) {
                text = qsTr("The network test could not be performed because none of DancherLink's connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
                imageSrc = "qrc:/res/baseline-warning-24px.svg"
            }
            else if (result === 0) {
                text = qsTr("This network does not appear to be blocking DancherLink. If you still have trouble connecting, check your PC's firewall settings.") + "\n\n" + qsTr("If you are trying to stream over the Internet, install the DancherLink Internet Hosting Tool on your gaming PC and run the included Internet Streaming Tester to check your gaming PC's Internet connection.")
                imageSrc = "qrc:/res/baseline-check_circle_outline-24px.svg"
            }
            else {
                text = qsTr("Your PC's current network connection seems to be blocking DancherLink. Streaming over the Internet may not work while connected to this network.") + "\n\n" + qsTr("The following network ports were blocked:") + "\n"
                text += blockedPorts
                imageSrc = "qrc:/res/baseline-error_outline-24px.svg"
            }

            // Stop showing the spinner and show the image instead
            showSpinner = false
        }
    }

    InputDialog {
        id: renamePcDialog
        label: qsTr("Enter the new name for this PC:")
        property int pcIndex: -1

        onValueAccepted: function(value) {
            computerModel.renameComputer(pcIndex, value)
        }
    }

    NavigableMessageDialog {
        id: showPcDetailsDialog
        property string pcDetails : "";
        text: showPcDetailsDialog.pcDetails
        imageSrc: "qrc:/res/baseline-help_outline-24px.svg"
        standardButtons: Dialog.Ok
    }

    ScrollBar.vertical: ScrollBar {}
}

