import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls.Material 2.15

import "."
import "settings"

import StreamingPreferences 1.0
import ComputerManager 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import AutoUpdateChecker 1.0

Page {
    id: settingsPage

    Component.onDestruction: {
        StreamingPreferences.save()
    }
    objectName: qsTr("Settings")

    signal languageChanged()

    background: Rectangle {
        color: Material.background
    }

    StackView.onActivated: {
        SdlGamepadKeyNavigation.setUiNavMode(true)
        if (SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            resolutionComboBox.forceActiveFocus(Qt.TabFocus)
        }
    }

    StackView.onDeactivating: {
        SdlGamepadKeyNavigation.setUiNavMode(false)
        StreamingPreferences.save()
    }

    property color groupTitleColor: AppTheme.groupTitle

    Component {
        id: groupBoxLabel
        Label {
            text: parent.title
            color: groupTitleColor
            font.pointSize: 12
            font.bold: true
            elide: Text.ElideRight
            padding: 0
            bottomPadding: 5
        }
    }

    property bool isWideLayout: settingsPage.width > 850
    readonly property int bottomSafeMargin: 60

    // Properties shared with AdvancedSettings component
    property var resolutionListModel: null
    property var resolutionComboBox: null
    property var bitrateSlider: null

    Flickable {
        id: flickable
        anchors.fill: parent
        anchors.bottomMargin: bottomSafeMargin
        boundsBehavior: Flickable.OvershootBounds
        contentWidth: settingsPage.width
        contentHeight: isWideLayout ? Math.max(settingsColumn1.height, settingsColumn2.height) : (settingsColumn1.height + settingsColumn2.height) + bottomSafeMargin

        ScrollBar.vertical: ScrollBar {
            anchors.left: parent.right
            anchors.leftMargin: -10
        }

        function isChildOfFlickable(item) {
            while (item) {
                if (item.parent === flickable.contentItem) return true
                item = item.parent
            }
            return false
        }

        NumberAnimation on contentY {
            id: autoScrollAnimation
            duration: 100
        }

        Window.onActiveFocusItemChanged: {
            var item = Window.activeFocusItem
            if (item && isChildOfFlickable(item)) {
                var pos = item.mapToItem(flickable.contentItem, 0, 0)
                var scrollMargin = height > 100 ? 50 : 0
                var effectiveHeight = height - bottomSafeMargin

                if (pos.y - scrollMargin < contentY) {
                    autoScrollAnimation.from = contentY
                    autoScrollAnimation.to = Math.max(pos.y - scrollMargin, 0)
                    autoScrollAnimation.start()
                } else if (pos.y + item.height + scrollMargin > contentY + effectiveHeight) {
                    autoScrollAnimation.from = contentY
                    autoScrollAnimation.to = Math.min(pos.y + item.height + scrollMargin - effectiveHeight, contentHeight - height)
                    autoScrollAnimation.start()
                }
            }
        }

        Column {
            padding: 10
            id: settingsColumn1
            width: isWideLayout ? settingsPage.width / 2 : settingsPage.width
            spacing: 15

            // ========== Basic Settings (inline - complex logic) ==========
            GroupBox {
                id: basicSettingsGroupBox
                width: parent.width - (parent.leftPadding + parent.rightPadding)
                padding: 12
                title: qsTr("Basic Settings")
                label: groupBoxLabel.createObject(basicSettingsGroupBox)
                font.pointSize: 12

                Column {
                    anchors.fill: parent
                    spacing: 5

                    Label {
                        width: parent.width
                        text: qsTr("Resolution and FPS")
                        font.pointSize: 12
                        wrapMode: Text.Wrap
                    }

                    Label {
                        width: parent.width
                        text: qsTr("Setting values too high for your PC or network connection may cause lag, stuttering, or errors.")
                        font.pointSize: 9
                        wrapMode: Text.Wrap
                    }

                    Row {
                        spacing: 5
                        width: parent.width

                        AutoResizingComboBox {
                            property int lastIndexValue

                            function addDetectedResolution(friendlyNamePrefix, rect) {
                                var indexToAdd = 0
                                for (var j = 0; j < count; j++) {
                                    var existing_width = parseInt(model.get(j).video_width);
                                    var existing_height = parseInt(model.get(j).video_height);
                                    if (rect.width === existing_width && rect.height === existing_height) {
                                        indexToAdd = -1
                                        break
                                    } else if (rect.width * rect.height > existing_width * existing_height) {
                                        indexToAdd = j + 1
                                    }
                                }
                                if (indexToAdd >= 0) {
                                    model.insert(indexToAdd, {
                                        "text": friendlyNamePrefix+" ("+rect.width+"x"+rect.height+")",
                                        "video_width": ""+rect.width,
                                        "video_height": ""+rect.height,
                                        "is_custom": false
                                    })
                                }
                            }

                            Component.onCompleted: {
                                SystemProperties.refreshDisplays()
                                var done = false
                                for (var displayIndex = 0; !done; displayIndex++) {
                                    var screenRect = SystemProperties.getNativeResolution(displayIndex);
                                    var safeAreaRect = SystemProperties.getSafeAreaResolution(displayIndex);
                                    if (screenRect.width === 0) {
                                        done = true
                                        break
                                    }
                                    addDetectedResolution(qsTr("Native"), screenRect)
                                    addDetectedResolution(qsTr("Native (Excluding Notch)"), safeAreaRect)
                                }

                                var max_pixels = SystemProperties.maximumResolution.width * SystemProperties.maximumResolution.height;
                                if (max_pixels > 0) {
                                    for (var j = 0; j < count; j++) {
                                        var existing_width = parseInt(model.get(j).video_width);
                                        var existing_height = parseInt(model.get(j).video_height);
                                        if (existing_width * existing_height > max_pixels) {
                                            model.remove(j)
                                            j--
                                        }
                                    }
                                }

                                var saved_width = StreamingPreferences.width
                                var saved_height = StreamingPreferences.height
                                var index_set = false
                                for (var i = 0; i < count; i++) {
                                    var el_width = parseInt(model.get(i).video_width);
                                    var el_height = parseInt(model.get(i).video_height);
                                    if (saved_width === el_width && saved_height === el_height) {
                                        currentIndex = i
                                        index_set = true
                                        break
                                    }
                                }

                                if (!index_set) {
                                    model.append({
                                        "text": qsTr("Custom")+" ("+StreamingPreferences.width+"x"+StreamingPreferences.height+")",
                                        "video_width": ""+StreamingPreferences.width,
                                        "video_height": ""+StreamingPreferences.height,
                                        "is_custom": true
                                    })
                                    currentIndex = count - 1
                                } else {
                                    model.append({
                                        "text": qsTr("Custom"),
                                        "video_width": "",
                                        "video_height": "",
                                        "is_custom": true
                                    })
                                }
                                recalculateWidth()
                                lastIndexValue = currentIndex

                                // Store reference for AdvancedSettings
                                settingsPage.resolutionListModel = model
                                settingsPage.resolutionComboBox = this
                            }

                            id: resolutionComboBox
                            maximumWidth: parent.width / 2
                            textRole: "text"
                            model: ListModel {
                                id: resolutionListModel
                                ListElement { text: qsTr("Auto"); video_width: "0"; video_height: "0"; is_custom: false }
                                ListElement { text: qsTr("720p"); video_width: "1280"; video_height: "720"; is_custom: false }
                                ListElement { text: qsTr("1080p"); video_width: "1920"; video_height: "1080"; is_custom: false }
                                ListElement { text: qsTr("1440p"); video_width: "2560"; video_height: "1440"; is_custom: false }
                                ListElement { text: qsTr("4K"); video_width: "3840"; video_height: "2160"; is_custom: false }
                            }

                            onActivated: {
                                var modelData = model.get(currentIndex)
                                if (modelData.is_custom) {
                                    customResolutionDialog.open()
                                    lastIndexValue = currentIndex
                                } else {
                                    StreamingPreferences.width = parseInt(modelData.video_width)
                                    StreamingPreferences.height = parseInt(modelData.video_height)
                                    if (lastIndexValue >= 0 && model.get(lastIndexValue).is_custom) {
                                        model.remove(lastIndexValue)
                                    }
                                    if (StreamingPreferences.autoAdjustBitrate && bitrateSlider) {
                                        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                                            StreamingPreferences.width, StreamingPreferences.height,
                                            StreamingPreferences.fps, StreamingPreferences.enableYUV444);
                                        bitrateSlider.value = StreamingPreferences.bitrateKbps
                                    }
                                }
                            }
                        }

                        AutoResizingComboBox {
                            id: fpsComboBox
                            maximumWidth: parent.width / 2
                            textRole: "text"
                            model: ListModel {
                                ListElement { text: qsTr("30 FPS"); val: 30 }
                                ListElement { text: qsTr("60 FPS"); val: 60 }
                                ListElement { text: qsTr("90 FPS"); val: 90 }
                                ListElement { text: qsTr("120 FPS"); val: 120 }
                                ListElement { text: qsTr("144 FPS"); val: 144 }
                            }

                            Component.onCompleted: {
                                var saved_fps = StreamingPreferences.fps
                                currentIndex = 0
                                for (var i = 0; i < model.count; i++) {
                                    if (model.get(i).val === saved_fps) {
                                        currentIndex = i
                                        break
                                    }
                                }
                                activated(currentIndex)
                            }

                            onActivated: {
                                var newFps = model.get(currentIndex).val
                                if (StreamingPreferences.fps !== newFps) {
                                    StreamingPreferences.fps = newFps
                                    if (StreamingPreferences.autoAdjustBitrate && bitrateSlider) {
                                        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                                            StreamingPreferences.width, StreamingPreferences.height,
                                            StreamingPreferences.fps, StreamingPreferences.enableYUV444);
                                        bitrateSlider.value = StreamingPreferences.bitrateKbps
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        width: parent.width
                        text: qsTr("Video bitrate")
                        font.pointSize: 12
                        wrapMode: Text.Wrap
                    }

                    Row {
                        spacing: 5
                        width: parent.width

                        Slider {
                            id: slider
                            width: parent.width - stepLabel.width - 10
                            from: 1000
                            to: StreamingPreferences.unlockBitrate ? 100000 : StreamingPreferences.getMaxBitrate(resolutionComboBox.model.get(resolutionComboBox.currentIndex).video_width, resolutionComboBox.model.get(resolutionComboBox.currentIndex).video_height, StreamingPreferences.fps, StreamingPreferences.enableYUV444)
                            stepSize: 500
                            value: StreamingPreferences.bitrateKbps

                            Component.onCompleted: {
                                settingsPage.bitrateSlider = slider
                            }

                            onValueChanged: {
                                if (StreamingPreferences.bitrateKbps !== value) {
                                    StreamingPreferences.bitrateKbps = value
                                }
                            }

                            onEditingFinished: {
                                to = StreamingPreferences.unlockBitrate ? 100000 : StreamingPreferences.getMaxBitrate(resolutionComboBox.model.get(resolutionComboBox.currentIndex).video_width, resolutionComboBox.model.get(resolutionComboBox.currentIndex).video_height, StreamingPreferences.fps, StreamingPreferences.enableYUV444)
                            }
                        }

                        Label {
                            id: stepLabel
                            width: implicitWidth
                            text: (slider.value / 1000).toFixed(1) + " Mbps"
                            font.pointSize: 12
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    CheckBox {
                        id: autoBitrateCheck
                        width: parent.width
                        text: qsTr("Automatically adjust video bitrate for optimal performance")
                        font.pointSize: 12
                        checked: StreamingPreferences.autoAdjustBitrate
                        onCheckedChanged: {
                            StreamingPreferences.autoAdjustBitrate = checked
                            if (checked && bitrateSlider) {
                                StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                                    StreamingPreferences.width, StreamingPreferences.height,
                                    StreamingPreferences.fps, StreamingPreferences.enableYUV444);
                                bitrateSlider.value = StreamingPreferences.bitrateKbps
                            }
                        }
                    }

                    Label {
                        width: parent.width
                        visible: autoBitrateCheck.checked
                        text: qsTr("With automatic bitrate adjustment, the video codec and YUV 4:4:4 settings will be used to determine the target bitrate.")
                        font.pointSize: 9
                        wrapMode: Text.Wrap
                        color: Material.hintTextColor
                    }
                }
            }

            // ========== Audio Settings (external component) ==========
            AudioSettings { }

            // ========== Host Settings (external component) ==========
            HostSettings { }

            // ========== UI Settings (external component) ==========
            UISettings {
                onLanguageChanged: settingsPage.languageChanged()
            }
        }

        // ========== Right Column (settingsColumn2) ==========
        Column {
            padding: 10
            rightPadding: isWideLayout ? 20 : 10
            anchors.left: isWideLayout ? settingsColumn1.right : parent.left
            anchors.top: isWideLayout ? parent.top : settingsColumn1.bottom
            id: settingsColumn2
            width: isWideLayout ? settingsPage.width / 2 : settingsPage.width
            spacing: 15

            // ========== Update Settings (external component) ==========
            UpdateSettings { }

            // ========== Input Settings (external component) ==========
            InputSettings { }

            // ========== Gamepad Settings (external component) ==========
            GamepadSettings { }

            // ========== Advanced Settings (external component) ==========
            AdvancedSettings {
                resolutionListModel: settingsPage.resolutionListModel
                resolutionComboBox: settingsPage.resolutionComboBox
                bitrateSlider: settingsPage.bitrateSlider
            }
        }
    }

    // Custom Resolution Dialog
    NavigableDialog {
        id: customResolutionDialog
        title: qsTr("Custom Resolution")
        standardButtons: Dialog.Ok | Dialog.Cancel

        Column {
            width: parent.width
            spacing: 10

            Label {
                width: parent.width
                text: qsTr("Enter a custom resolution:")
                font.pointSize: 12
            }

            Row {
                spacing: 10
                width: parent.width

                TextField {
                    id: customWidthField
                    width: parent.width / 2 - 5
                    placeholderText: qsTr("Width")
                    validator: IntValidator { bottom: 16; top: 10000 }
                    Component.onCompleted: text = StreamingPreferences.width
                }

                TextField {
                    id: customHeightField
                    width: parent.width / 2 - 5
                    placeholderText: qsTr("Height")
                    validator: IntValidator { bottom: 16; top: 10000 }
                    Component.onCompleted: text = StreamingPreferences.height
                }
            }
        }

        onAccepted: {
            var newWidth = parseInt(customWidthField.text)
            var newHeight = parseInt(customHeightField.text)

            if (newWidth > 0 && newHeight > 0) {
                StreamingPreferences.width = newWidth
                StreamingPreferences.height = newHeight

                if (StreamingPreferences.autoAdjustBitrate && bitrateSlider) {
                    StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                        StreamingPreferences.width, StreamingPreferences.height,
                        StreamingPreferences.fps, StreamingPreferences.enableYUV444);
                    bitrateSlider.value = StreamingPreferences.bitrateKbps
                }
            }
        }
    }
}
