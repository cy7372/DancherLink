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
            font.pointSize: AppTheme.fontSmall
            font.bold: true
            elide: Text.ElideRight
            padding: 0
            bottomPadding: AppTheme.spacingXs
        }
    }

    property bool isWideLayout: settingsPage.width > 850
    readonly property int bottomSafeMargin: 64
    readonly property int columnSpacing: AppTheme.spacingMd

    // Properties shared with AdvancedSettings component
    property var resolutionListModel: null
    property var resolutionComboBox: null
    property var bitrateSlider: null

    Flickable {
        id: flickable
        anchors.fill: parent
        anchors.bottomMargin: bottomSafeMargin
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: settingsPage.width
        contentHeight: isWideLayout ? Math.max(settingsColumn1.height, settingsColumn2.height)
                                    : settingsColumn1.height + settingsColumn2.height + columnSpacing
        flickDecayRate: 120
        maximumFlickVelocity: 3000

        ScrollBar.vertical: ScrollBar {
            anchors.left: parent.right
            anchors.leftMargin: -10
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            policy: ScrollBar.AsNeeded
            interactive: true
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
            padding: AppTheme.spacingMd
            id: settingsColumn1
            width: isWideLayout ? (flickable.width - 20) / 2 : flickable.width - 20
            spacing: AppTheme.spacingMd

            // =========================================================================
            // SECTION: Basic Settings
            // Resolution, FPS, bitrate, and video codec configuration
            // =========================================================================

            GroupBox {
                id: basicSettingsGroupBox
                width: (parent.width - (parent.leftPadding + parent.rightPadding))
                padding: AppTheme.spacingMd
                title: qsTr("Basic Settings")
                label: groupBoxLabel.createObject(basicSettingsGroupBox)
                font.pointSize: AppTheme.fontCaption

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: AppTheme.spacingSm

                    Label {
                        id: resFPStitle
                        text: qsTr("Resolution and FPS")
                        font.pointSize: AppTheme.fontCaption
                        wrapMode: Text.Wrap
                    }

                    Label {
                        id: resFPSdesc
                        text: qsTr("Setting values too high for your PC or network connection may cause lag, stuttering, or errors.")
                        font.pointSize: AppTheme.fontSmall
                        wrapMode: Text.Wrap
                    }

                    Row {
                        spacing: AppTheme.spacingSm
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

                            function updateBitrateForSelection() {
                                var selectedWidth = parseInt(model.get(currentIndex).video_width)
                                var selectedHeight = parseInt(model.get(currentIndex).video_height)

                                if (StreamingPreferences.width !== selectedWidth || StreamingPreferences.height !== selectedHeight) {
                                    StreamingPreferences.width = selectedWidth
                                    StreamingPreferences.height = selectedHeight

                                    if (StreamingPreferences.autoAdjustBitrate && bitrateSlider) {
                                        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                                            StreamingPreferences.width, StreamingPreferences.height,
                                            StreamingPreferences.fps, StreamingPreferences.enableYUV444);
                                        bitrateSlider.value = StreamingPreferences.bitrateKbps
                                    }
                                }
                                lastIndexValue = currentIndex
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
                                if (model.get(currentIndex).is_custom) {
                                    customResolutionDialog.open()
                                } else {
                                    updateBitrateForSelection()
                                }
                            }
                        }

                        // FPS ComboBox with display refresh rate detection
                        AutoResizingComboBox {
                            id: fpsComboBox
                            property int lastIndexValue

                            function addRefreshRateOrdered(fpsListModel, refreshRate, description, custom) {
                                var indexToAdd = 0
                                for (var j = 0; j < fpsListModel.count; j++) {
                                    var existing_fps = parseInt(fpsListModel.get(j).video_fps);
                                    if (refreshRate === existing_fps || (custom && fpsListModel.get(j).is_custom)) {
                                        indexToAdd = -1
                                        break
                                    } else if (refreshRate > existing_fps) {
                                        indexToAdd = j + 1
                                    }
                                }
                                if (indexToAdd >= 0) {
                                    if (custom) {
                                        indexToAdd = fpsListModel.count
                                    }
                                    fpsListModel.insert(indexToAdd, {
                                        "text": description,
                                        "video_fps": ""+refreshRate,
                                        "is_custom": custom
                                    })
                                }
                                return indexToAdd
                            }

                            function updateBitrateForSelection() {
                                var selectedFps = parseInt(model.get(currentIndex).video_fps)
                                if (StreamingPreferences.fps !== selectedFps) {
                                    StreamingPreferences.fps = selectedFps
                                    if (StreamingPreferences.autoAdjustBitrate && bitrateSlider) {
                                        StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                                            StreamingPreferences.width, StreamingPreferences.height,
                                            StreamingPreferences.fps, StreamingPreferences.enableYUV444);
                                        bitrateSlider.value = StreamingPreferences.bitrateKbps
                                    }
                                }
                                lastIndexValue = currentIndex
                            }

                            function reinitialize() {
                                // Add native refresh rate for all attached displays
                                var done = false
                                for (var displayIndex = 0; !done; displayIndex++) {
                                    var refreshRate = SystemProperties.getRefreshRate(displayIndex);
                                    if (refreshRate === 0) {
                                        done = true
                                        break
                                    }
                                    addRefreshRateOrdered(model, refreshRate, qsTr("%1 FPS").arg(refreshRate), false)
                                }

                                var saved_fps = StreamingPreferences.fps
                                var found = false
                                for (var i = 0; i < model.count; i++) {
                                    var el_fps = parseInt(model.get(i).video_fps);
                                    if (saved_fps === el_fps) {
                                        currentIndex = i
                                        found = true
                                        break
                                    }
                                }

                                if (!found) {
                                    currentIndex = addRefreshRateOrdered(model, saved_fps, qsTr("Custom (%1 FPS)").arg(saved_fps), true)
                                } else {
                                    addRefreshRateOrdered(model, "", qsTr("Custom"), true)
                                }
                                recalculateWidth()
                                lastIndexValue = currentIndex
                            }

                            Component.onCompleted: {
                                reinitialize()
                                settingsPage.languageChanged.connect(reinitialize)
                            }

                            maximumWidth: parent.width / 2
                            textRole: "text"
                            model: ListModel {
                                id: fpsListModel
                                ListElement { text: qsTr("30 FPS"); video_fps: "30"; is_custom: false }
                                ListElement { text: qsTr("60 FPS"); video_fps: "60"; is_custom: false }
                            }

                            onActivated: {
                                if (model.get(currentIndex).is_custom) {
                                    customFpsDialog.open()
                                } else {
                                    updateBitrateForSelection()
                                }
                            }
                        }
                    }

                    // Bitrate settings
                    Label {
                        id: bitrateTitle
                        text: qsTr("Video bitrate: %1 Mbps").arg(slider.value / 1000.0)
                        font.pointSize: 12
                        wrapMode: Text.Wrap
                    }

                    Label {
                        id: bitrateDesc
                        text: qsTr("Lower the bitrate on slower connections. Raise the bitrate to increase image quality.")
                        font.pointSize: 9
                        wrapMode: Text.Wrap
                    }

                    Row {
                        width: parent.width
                        spacing: 5

                        Slider {
                            id: slider
                            value: StreamingPreferences.bitrateKbps
                            stepSize: 500
                            from: 500
                            to: StreamingPreferences.unlockBitrate ? 500000 : 150000
                            snapMode: Slider.SnapOnRelease
                            width: Math.min(bitrateDesc.implicitWidth, parent.width - (resetBitrateButton.visible ? resetBitrateButton.width + parent.spacing : 0))

                            Component.onCompleted: {
                                settingsPage.bitrateSlider = slider
                                settingsPage.languageChanged.connect(valueChanged)
                            }

                            onValueChanged: {
                                bitrateTitle.text = qsTr("Video bitrate: %1 Mbps").arg(value / 1000.0)
                                if (StreamingPreferences.bitrateKbps !== value) {
                                    StreamingPreferences.bitrateKbps = value
                                }
                            }

                            onMoved: {
                                StreamingPreferences.autoAdjustBitrate = false
                            }
                        }

                        Button {
                            id: resetBitrateButton
                            text: qsTr("Use Default")
                            visible: StreamingPreferences.bitrateKbps !== StreamingPreferences.getDefaultBitrate(
                                StreamingPreferences.width, StreamingPreferences.height,
                                StreamingPreferences.fps, StreamingPreferences.enableYUV444)
                            onClicked: {
                                var defaultBitrate = StreamingPreferences.getDefaultBitrate(
                                    StreamingPreferences.width, StreamingPreferences.height,
                                    StreamingPreferences.fps, StreamingPreferences.enableYUV444)
                                StreamingPreferences.bitrateKbps = defaultBitrate
                                StreamingPreferences.autoAdjustBitrate = true
                                slider.value = defaultBitrate
                            }
                        }
                    }

                    CheckBox {
                        id: autoBitrateCheck
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
                        visible: autoBitrateCheck.checked
                        text: qsTr("With automatic bitrate adjustment, the video codec and YUV 4:4:4 settings will be used to determine the target bitrate.")
                        font.pointSize: 9
                        wrapMode: Text.Wrap
                        color: Material.hintTextColor
                    }

                    // Display mode settings
                    Label {
                        id: windowModeTitle
                        text: qsTr("Display mode")
                        font.pointSize: 12
                        wrapMode: Text.Wrap
                        visible: SystemProperties.hasDesktopEnvironment
                    }

                    AutoResizingComboBox {
                        id: windowModeComboBox
                        visible: SystemProperties.hasDesktopEnvironment
                        enabled: !SystemProperties.rendererAlwaysFullScreen
                        hoverEnabled: true
                        textRole: "text"

                        function createModel() {
                            var newModel = Qt.createQmlObject('import QtQuick 2.15; ListModel {}', parent, '')
                            newModel.append({ text: qsTr("Fullscreen"), val: StreamingPreferences.WM_FULLSCREEN })
                            newModel.append({ text: qsTr("Borderless windowed"), val: StreamingPreferences.WM_FULLSCREEN_DESKTOP })
                            newModel.append({ text: qsTr("Windowed"), val: StreamingPreferences.WM_WINDOWED })

                            // Set the recommended option based on the OS
                            for (var i = 0; i < newModel.count; i++) {
                                var thisWm = newModel.get(i).val;
                                if (thisWm === StreamingPreferences.recommendedFullScreenMode) {
                                    newModel.get(i).text += " " + qsTr("(Recommended)")
                                    newModel.move(i, 0, 1)
                                    break
                                }
                            }
                            return newModel
                        }

                        function reinitialize() {
                            if (!visible) return
                            model = createModel()
                            currentIndex = 0
                            var savedWm = StreamingPreferences.windowMode
                            for (var i = 0; i < model.count; i++) {
                                if (model.get(i).val === savedWm) {
                                    currentIndex = i
                                    break
                                }
                            }
                            activated(currentIndex)
                        }

                        Component.onCompleted: {
                            reinitialize()
                            settingsPage.languageChanged.connect(reinitialize)
                        }

                        onActivated: {
                            StreamingPreferences.windowMode = model.get(currentIndex).val
                        }

                        ToolTip.delay: 1000
                        ToolTip.timeout: 5000
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Fullscreen generally provides the best performance, but borderless windowed may work better with features like macOS Spaces, Alt+Tab, screenshot tools, on-screen overlays, etc.")
                    }

                    CheckBox {
                        id: vsyncCheck
                        width: parent.width
                        hoverEnabled: true
                        text: qsTr("V-Sync")
                        font.pointSize: 12
                        checked: StreamingPreferences.enableVsync
                        onCheckedChanged: {
                            StreamingPreferences.enableVsync = checked
                        }

                        ToolTip.delay: 1000
                        ToolTip.timeout: 5000
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Disabling V-Sync allows sub-frame rendering latency, but it can display visible tearing")
                    }

                    CheckBox {
                        id: framePacingCheck
                        width: parent.width
                        hoverEnabled: true
                        text: qsTr("Frame pacing")
                        font.pointSize: 12
                        enabled: StreamingPreferences.enableVsync
                        checked: StreamingPreferences.enableVsync && StreamingPreferences.framePacing
                        onCheckedChanged: {
                            StreamingPreferences.framePacing = checked
                        }

                        ToolTip.delay: 1000
                        ToolTip.timeout: 5000
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Frame pacing reduces micro-stutter by delaying frames that come in too early")
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

        // =========================================================================
        // SECTION: Right Column (settingsColumn2)
        // Update, Input, Audio, Gamepad, and Advanced settings
        // Uses external components from settings/ directory
        // =========================================================================

        Column {
            padding: AppTheme.spacingMd
            rightPadding: isWideLayout ? AppTheme.spacingMd : AppTheme.spacingMd
            anchors.left: isWideLayout ? settingsColumn1.right : parent.left
            anchors.top: isWideLayout ? parent.top : settingsColumn1.bottom
            anchors.topMargin: isWideLayout ? 0 : columnSpacing
            id: settingsColumn2
            width: isWideLayout ? (flickable.width - 20) / 2 : flickable.width - 20
            spacing: AppTheme.spacingMd

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

        function isInputValid() {
            // Check if width is valid
            var widthValid = customWidthField.acceptableInput && customWidthField.text
            var heightValid = customHeightField.acceptableInput && customHeightField.text

            if (widthValid && heightValid) {
                var width = parseInt(customWidthField.text)
                var height = parseInt(customHeightField.text)
                return width >= 16 && width <= 10000 && height >= 16 && height <= 10000
            }
            return false
        }

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

                    onTextChanged: {
                        if (customResolutionDialog.standardButton) {
                            customResolutionDialog.standardButton(Dialog.Ok).enabled = customResolutionDialog.isInputValid()
                        }
                    }

                    Keys.onReturnPressed: {
                        if (customResolutionDialog.isInputValid()) {
                            customResolutionDialog.accept()
                        }
                    }

                    Keys.onEnterPressed: {
                        if (customResolutionDialog.isInputValid()) {
                            customResolutionDialog.accept()
                        }
                    }
                }

                TextField {
                    id: customHeightField
                    width: parent.width / 2 - 5
                    placeholderText: qsTr("Height")
                    validator: IntValidator { bottom: 16; top: 10000 }
                    Component.onCompleted: text = StreamingPreferences.height

                    onTextChanged: {
                        if (customResolutionDialog.standardButton) {
                            customResolutionDialog.standardButton(Dialog.Ok).enabled = customResolutionDialog.isInputValid()
                        }
                    }

                    Keys.onReturnPressed: {
                        if (customResolutionDialog.isInputValid()) {
                            customResolutionDialog.accept()
                        }
                    }

                    Keys.onEnterPressed: {
                        if (customResolutionDialog.isInputValid()) {
                            customResolutionDialog.accept()
                        }
                    }
                }
            }
        }

        onOpened: {
            customWidthField.forceActiveFocus()
            // Update OK button state when dialog opens
            if (customResolutionDialog.standardButton) {
                customResolutionDialog.standardButton(Dialog.Ok).enabled = customResolutionDialog.isInputValid()
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

    // Custom FPS Dialog
    NavigableDialog {
        id: customFpsDialog
        title: qsTr("Custom Frame Rate")
        standardButtons: Dialog.Ok | Dialog.Cancel

        Column {
            width: parent.width
            spacing: 10

            Label {
                width: parent.width
                text: qsTr("Resolutions that are not officially supported by GeForce Experience, The host will not set your host display resolution. You will need to set it manually while in game.") + "\n\n" +
                          qsTr("Frame rates that are not supported by your client or host PC may cause streaming errors.")
                font.pointSize: 10
                wrapMode: Text.Wrap
            }

            Label {
                text: qsTr("Enter a custom frame rate:")
                font.bold: true
            }

            TextField {
                id: customFpsField
                width: parent.width
                maximumLength: 4
                inputMethodHints: Qt.ImhDigitsOnly
                placeholderText: fpsListModel.get(fpsComboBox.currentIndex).video_fps
                validator: IntValidator { bottom: 10; top: 9999 }
                focus: true

                onTextChanged: {
                    if (customFpsDialog.standardButton) {
                        customFpsDialog.standardButton(Dialog.Ok).enabled = customFpsDialog.isInputValid()
                    }
                }

                Keys.onReturnPressed: {
                    customFpsDialog.accept()
                }

                Keys.onEnterPressed: {
                    customFpsDialog.accept()
                }
            }
        }

        function isInputValid() {
            // Accept if input is valid number
            if (customFpsField.acceptableInput && customFpsField.text) {
                var fps = parseInt(customFpsField.text)
                return fps >= 10 && fps <= 9999
            }
            // Accept if we can use placeholder text
            if (!customFpsField.text && customFpsField.placeholderText) {
                var placeholderFps = parseInt(customFpsField.placeholderText)
                return !isNaN(placeholderFps) && placeholderFps >= 10 && placeholderFps <= 9999
            }
            return false
        }

        onOpened: {
            customFpsField.forceActiveFocus()
            // Update OK button state when dialog opens
            if (customFpsDialog.standardButton) {
                customFpsDialog.standardButton(Dialog.Ok).enabled = customFpsDialog.isInputValid()
            }
            customFpsDialog.standardButton(Dialog.Ok).enabled = isInputValid()
        }

        onClosed: {
            customFpsField.clear()
        }

        onRejected: {
            fpsComboBox.currentIndex = fpsComboBox.lastIndexValue
        }

        onAccepted: {
            if (!isInputValid()) {
                reject()
                return
            }

            var fps = customFpsField.text ? customFpsField.text : customFpsField.placeholderText

            // Find and update the custom entry
            for (var i = 0; i < fpsListModel.count; i++) {
                if (fpsListModel.get(i).is_custom) {
                    fpsListModel.setProperty(i, "video_fps", fps)
                    fpsListModel.setProperty(i, "text", qsTr("Custom (%1 FPS)").arg(fps))

                    fpsComboBox.currentIndex = i
                    fpsComboBox.updateBitrateForSelection()

                    fpsComboBox.recalculateWidth()
                    break
                }
            }
        }
    }
}
