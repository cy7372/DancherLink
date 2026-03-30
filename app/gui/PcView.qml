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
    property bool modelReady : false
    id: pcGrid
    focus: true
    activeFocusOnTab: true
    topMargin: AppTheme.spacingLg
    bottomMargin: AppTheme.spacingSm
    cellWidth: AppTheme.pcCardWidth; cellHeight: AppTheme.pcCardHeight;
    objectName: qsTr("Computers")

    // Performance optimizations
    cacheBuffer: 400  // Cache extra items off-screen for smoother scrolling
    reuseItems: true  // Reuse delegate items instead of creating/destroying

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // This avoids showing a highlighted item when the app starts.
        currentIndex = -1
    }

    model: computerModel

    // model property removed - set dynamically in Component.onCompleted
    // This ensures delegates see a valid computerModel from the start

    delegate: NavigableItemDelegate {
        id: delegateRoot
        width: AppTheme.pcCardWidth - 8; height: AppTheme.pcCardHeight - 8;
        grid: pcGrid

        property alias pcContextMenu : pcContextMenuLoader.item

        // Empty contentItem - all content is in background for correct hover bounds
        contentItem: Item {}

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

            // All content as children of background so hover detection matches visual bounds
            Image {
                id: pcIcon
                anchors.horizontalCenter: delegateBackground.horizontalCenter
                anchors.top: delegateBackground.top
                anchors.topMargin: AppTheme.spacingMd
                source: "qrc:/res/desktop_windows-48px.svg"
                sourceSize {
                    width: 160
                    height: 160
                }
            }

            // Network latency indicator - shows for currently selected PC
            Loader {
                anchors.top: delegateBackground.top
                anchors.right: delegateBackground.right
                anchors.margins: AppTheme.spacingSm
                active: pcGrid.modelReady && model.online && index === pcGrid.currentIndex
                visible: active
                asynchronous: true
                sourceComponent: Rectangle {
                    id: latencyBadge
                    width: latencyLabel.implicitWidth + 12
                    height: 24
                    radius: 4
                    opacity: 0.9

                    property int cachedLatency: pcGrid.model ? pcGrid.model.networkLatencyMs : -1

                    color: {
                        var ms = cachedLatency
                        if (ms < 0) return "#555555"
                        if (ms < 20) return "#2E7D32"
                        if (ms < 50) return "#F9A825"
                        return "#C62828"
                    }

                    Label {
                        id: latencyLabel
                        anchors.centerIn: parent
                        text: {
                            var ms = cachedLatency
                            if (ms < 0) return "--"
                            return ms + " ms"
                        }
                        color: "white"
                        font.pointSize: AppTheme.fontSmall
                        font.bold: true
                    }

                    ToolTip.visible: latencyMouseArea.containsMouse
                    ToolTip.text: pcGrid.model ? pcGrid.model.networkQualityString : ""
                    ToolTip.delay: 500

                    MouseArea {
                        id: latencyMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }
            }

            Image {
                id: stateIcon
                anchors.horizontalCenter: pcIcon.horizontalCenter
                anchors.verticalCenter: pcIcon.verticalCenter
                anchors.verticalCenterOffset: !model.online ? -16 : -14
                visible: !model.statusUnknown && (!model.online || !model.paired)
                source: !model.online ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-lock-24px.svg"
                sourceSize {
                    width: 64
                    height: 64
                }

                ToolTip.visible: stateIconMouseArea.containsMouse && stateIcon.visible
                ToolTip.text: !model.online ? qsTr("PC is offline") : qsTr("PC is not paired")
                ToolTip.delay: 500

                MouseArea {
                    id: stateIconMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }

            BusyIndicator {
                id: statusUnknownSpinner
                anchors.horizontalCenter: pcIcon.horizontalCenter
                anchors.verticalCenter: pcIcon.verticalCenter
                anchors.verticalCenterOffset: -14
                width: 64
                height: 64
                visible: model.statusUnknown
                running: visible
            }

            Label {
                id: pcNameText
                text: model.name

                width: delegateBackground.width - AppTheme.spacingMd * 2
                anchors.top: pcIcon.bottom
                anchors.bottom: delegateBackground.bottom
                anchors.topMargin: AppTheme.spacingSm
                font.pointSize: AppTheme.fontTitle
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
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
                            if (computerView.computerModel) {
                                computerView.currentAddress = modelData.address
                                computerView.show()
                            }
                        }
                    }
                    MenuItem {
                        text: qsTr("Details...")
                        onTriggered: {
                            pcDetailsDialog.computer = modelData
                            pcDetailsDialog.show()
                        }
                    }
                }
            }

            MouseArea {
                id: pcDelegateMouseArea
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                propagateComposedEvents: true

                onClicked: {
                    if (!pcGrid.currentItem || pcGrid.currentItem !== delegateRoot) {
                        pcGrid.currentIndex = index
                    }
                    pcContextMenu.open()
                }
            }
        }

        MouseArea {
            id: pcDelegateMouseAreaOverlay
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            propagateComposedEvents: true

            onClicked: {
                if (!pcGrid.currentItem || pcGrid.currentItem !== delegateRoot) {
                    pcGrid.currentIndex = index
                }
                if (delegateRoot.pcContextMenu) {
                    delegateRoot.pcContextMenu.open()
                }
            }
        }
    }

    Component {
        id: pcDetailsDialog
        PcDetailsDialog {}
    }

    Keys.onReturnPressed: {
        if (currentIndex >= 0 && computerModel) {
            var computer = computerModel.get(currentIndex)
            if (computer && computer.online && computer.paired) {
                computerView.computerModel = computer
                computerView.show()
            }
        }
    }
    Keys.onEnterPressed: Keys.onReturnPressed()

    // Context menu handling
    Connections {
        target: computerModel
        function onComputersChanged() {
            // Refresh the model when computers change
            pcGrid.model = null
            pcGrid.model = computerModel
        }
    }
}
