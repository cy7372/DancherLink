import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls.Material 2.15

import ".."

import StreamingPreferences 1.0
import SystemProperties 1.0
import ComputerManager 1.0

// =============================================================================
// Video Tab - Video streaming settings
// =============================================================================
// Contains:
//   - Resolution and FPS selection
//   - Video bitrate configuration
//   - Display mode (fullscreen, windowed, etc.)
//   - V-Sync and frame pacing
//   - Video decoder selection
//   - Video codec selection
//   - HDR and YUV 4:4:4 options
//   - Performance overlay option
// =============================================================================

ScrollView {
    id: videoTab

    signal resolutionModelReady()

    // Reinitialize on language change
    function retranslate() {
        // Refresh FPS model
        fpsComboBox.reinitialize()

        // Refresh resolution model static entries
        resolutionListModel.setProperty(0, "text", qsTr("Auto"))
        resolutionListModel.setProperty(1, "text", qsTr("720p"))
        resolutionListModel.setProperty(2, "text", qsTr("1080p"))
        resolutionListModel.setProperty(3, "text", qsTr("1440p"))
        resolutionListModel.setProperty(4, "text", qsTr("4K"))

        // Find and update custom entry if present
        for (var i = 0; i < resolutionListModel.count; i++) {
            if (resolutionListModel.get(i).is_custom) {
                var customText = StreamingPreferences.width > 0 && StreamingPreferences.height > 0
                    ? qsTr("Custom") + " (" + StreamingPreferences.width + "x" + StreamingPreferences.height + ")"
                    : qsTr("Custom")
                resolutionListModel.setProperty(i, "text", customText)
                break
            }
        }

        // Refresh decoder model
        decoderListModel.setProperty(0, "text", qsTr("Automatic (Recommended)"))
        decoderListModel.setProperty(1, "text", qsTr("Force software decoding"))
        decoderListModel.setProperty(2, "text", qsTr("Force hardware decoding"))

        // Refresh codec model
        codecListModel.setProperty(0, "text", qsTr("Automatic (Recommended)"))
        codecListModel.setProperty(1, "text", qsTr("H.264"))
        codecListModel.setProperty(2, "text", qsTr("HEVC (H.265)"))
        codecListModel.setProperty(3, "text", qsTr("AV1 (Experimental)"))

        // Refresh window mode model
        windowModeComboBox.model = windowModeComboBox.createModel()
    }

    // Export these for cross-tab communication
    property alias resolutionListModel: resolutionListModel
    property alias resolutionComboBox: resolutionComboBox
    property alias bitrateSlider: bitrateSlider

    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Column {
        id: contentColumn
        width: videoTab.width - 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: AppTheme.spacingMd
        padding: AppTheme.spacingMd

        // Section: Basic Video Settings
        SettingsGroupBox {
            title: qsTr("Video Streaming")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                Label {
                    text: qsTr("Resolution and FPS")
                    font.pointSize: AppTheme.fontCaption
                    wrapMode: Text.Wrap
                }

                Label {
                    width: parent.width
                    text: qsTr("Setting values too high for your PC or network connection may cause lag, stuttering, or errors.")
                    font.pointSize: AppTheme.fontSmall
                    wrapMode: Text.Wrap
                    color: Material.hintTextColor
                }

                Row {
                    spacing: AppTheme.spacingSm
                    width: parent.width

                    // Resolution ComboBox
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

                            videoTab.resolutionModelReady()
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

                    // FPS ComboBox
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
                    text: qsTr("Video bitrate: %1 Mbps").arg(bitrateSlider.value / 1000.0)
                    font.pointSize: AppTheme.fontCaption
                    wrapMode: Text.Wrap
                }

                Label {
                    text: qsTr("Lower the bitrate on slower connections. Raise the bitrate to increase image quality.")
                    font.pointSize: AppTheme.fontSmall
                    wrapMode: Text.Wrap
                    color: Material.hintTextColor
                }

                Row {
                    width: parent.width
                    spacing: 5

                    Slider {
                        id: bitrateSlider
                        value: StreamingPreferences.bitrateKbps
                        stepSize: 500
                        from: 500
                        to: StreamingPreferences.unlockBitrate ? 500000 : 150000
                        snapMode: Slider.SnapOnRelease
                        width: Math.min(300, parent.width - (resetBitrateButton.visible ? resetBitrateButton.width + parent.spacing : 0))

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
                            bitrateSlider.value = defaultBitrate
                        }
                    }
                }

                CheckBox {
                    id: autoBitrateCheck
                    text: qsTr("Automatically adjust video bitrate for optimal performance")
                    font.pointSize: AppTheme.fontBody
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
                    font.pointSize: AppTheme.fontSmall
                    wrapMode: Text.Wrap
                    color: Material.hintTextColor
                }
            }
        }

        // Section: Display Mode
        SettingsGroupBox {
            title: qsTr("Display Mode")
            width: parent.width - parent.padding * 2
            visible: SystemProperties.hasDesktopEnvironment

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                AutoResizingComboBox {
                    id: windowModeComboBox
                    enabled: !SystemProperties.rendererAlwaysFullScreen
                    hoverEnabled: true
                    textRole: "text"

                    function createModel() {
                        var newModel = Qt.createQmlObject('import QtQuick 2.15; ListModel {}', parent, '')
                        newModel.append({ text: qsTr("Fullscreen"), val: StreamingPreferences.WM_FULLSCREEN })
                        newModel.append({ text: qsTr("Borderless windowed"), val: StreamingPreferences.WM_FULLSCREEN_DESKTOP })
                        newModel.append({ text: qsTr("Windowed"), val: StreamingPreferences.WM_WINDOWED })

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

                    Component.onCompleted: {
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
                    font.pointSize: AppTheme.fontBody
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
                    font.pointSize: AppTheme.fontBody
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

        // Section: Decoder Settings
        SettingsGroupBox {
            title: qsTr("Decoder Settings")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                Label {
                    text: qsTr("Video decoder")
                    font.pointSize: AppTheme.fontCaption
                    wrapMode: Text.Wrap
                }

                AutoResizingComboBox {
                    id: decoderComboBox
                    textRole: "text"

                    Component.onCompleted: {
                        var saved_vds = StreamingPreferences.videoDecoderSelection
                        currentIndex = 0
                        for (var i = 0; i < decoderListModel.count; i++) {
                            var el_vds = decoderListModel.get(i).val;
                            if (saved_vds === el_vds) {
                                currentIndex = i
                                break
                            }
                        }
                        activated(currentIndex)
                    }

                    model: ListModel {
                        id: decoderListModel
                        ListElement {
                            text: qsTr("Automatic (Recommended)")
                            val: StreamingPreferences.VDS_AUTO
                        }
                        ListElement {
                            text: qsTr("Force software decoding")
                            val: StreamingPreferences.VDS_FORCE_SOFTWARE
                        }
                        ListElement {
                            text: qsTr("Force hardware decoding")
                            val: StreamingPreferences.VDS_FORCE_HARDWARE
                        }
                    }

                    onActivated: {
                        if (enabled) {
                            StreamingPreferences.videoDecoderSelection = decoderListModel.get(currentIndex).val
                        }
                    }
                }

                Label {
                    width: parent.width
                    text: qsTr("Video codec")
                    font.pointSize: AppTheme.fontCaption
                    wrapMode: Text.Wrap
                }

                AutoResizingComboBox {
                    id: codecComboBox
                    textRole: "text"

                    Component.onCompleted: {
                        var saved_vcc = StreamingPreferences.videoCodecConfig
                        currentIndex = 0
                        for (var i = 0; i < codecListModel.count; i++) {
                            var el_vcc = codecListModel.get(i).val;
                            if (saved_vcc === el_vcc) {
                                currentIndex = i
                                break
                            }
                        }
                        activated(currentIndex)
                    }

                    model: ListModel {
                        id: codecListModel
                        ListElement {
                            text: qsTr("Automatic (Recommended)")
                            val: StreamingPreferences.VCC_AUTO
                        }
                        ListElement {
                            text: qsTr("H.264")
                            val: StreamingPreferences.VCC_FORCE_H264
                        }
                        ListElement {
                            text: qsTr("HEVC (H.265)")
                            val: StreamingPreferences.VCC_FORCE_HEVC
                        }
                        ListElement {
                            text: qsTr("AV1 (Experimental)")
                            val: StreamingPreferences.VCC_FORCE_AV1
                        }
                    }

                    onActivated: {
                        if (enabled) {
                            StreamingPreferences.videoCodecConfig = codecListModel.get(currentIndex).val
                        }
                    }
                }
            }
        }

        // Section: Video Quality
        SettingsGroupBox {
            title: qsTr("Video Quality")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: enableHdr
                    width: parent.width
                    text: qsTr("Enable HDR (Experimental)")
                    font.pointSize: AppTheme.fontBody
                    enabled: SystemProperties.supportsHdr
                    checked: enabled && StreamingPreferences.enableHdr
                    onCheckedChanged: {
                        StreamingPreferences.enableHdr = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: enabled ?
                                      qsTr("The stream will be HDR-capable, but some games may require an HDR monitor on your host PC to enable HDR mode.")
                                    :
                                      qsTr("HDR streaming is not supported on this PC.")
                }

                CheckBox {
                    id: enableYUV444
                    width: parent.width
                    text: qsTr("Enable YUV 4:4:4 (Experimental)")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.enableYUV444
                    onCheckedChanged: {
                        if (StreamingPreferences.enableYUV444 != checked) {
                            StreamingPreferences.enableYUV444 = checked
                            if (StreamingPreferences.autoAdjustBitrate && bitrateSlider) {
                                StreamingPreferences.bitrateKbps = StreamingPreferences.getDefaultBitrate(
                                    StreamingPreferences.width, StreamingPreferences.height,
                                    StreamingPreferences.fps, StreamingPreferences.enableYUV444);
                                bitrateSlider.value = StreamingPreferences.bitrateKbps
                            }
                        }
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: enabled ?
                                      qsTr("Good for streaming desktop and text-heavy games, but not recommended for fast-paced games.")
                                    :
                                      qsTr("YUV 4:4:4 is not supported on this PC.")
                }

                CheckBox {
                    id: unlockBitrate
                    width: parent.width
                    text: qsTr("Unlock bitrate limit (Experimental)")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.unlockBitrate
                    onCheckedChanged: {
                        StreamingPreferences.unlockBitrate = checked
                        StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, bitrateSlider ? bitrateSlider.to : 100000)
                        if (bitrateSlider) {
                            bitrateSlider.value = StreamingPreferences.bitrateKbps
                        }
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("This unlocks extremely high video bitrates for use with Sunshine hosts. It should only be used when streaming over an Ethernet LAN connection.")
                }
            }
        }

        // Section: Advanced Options
        SettingsGroupBox {
            title: qsTr("Advanced Options")
            width: parent.width - parent.padding * 2

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: AppTheme.spacingSm

                CheckBox {
                    id: showPerformanceOverlay
                    width: parent.width
                    text: qsTr("Show performance stats while streaming")
                    font.pointSize: AppTheme.fontBody
                    checked: StreamingPreferences.showPerformanceOverlay
                    onCheckedChanged: {
                        StreamingPreferences.showPerformanceOverlay = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Display real-time stream performance information while streaming.") + "\n\n" +
                                  qsTr("You can toggle it at any time while streaming using Ctrl+Alt+Shift+S or Select+L1+R1+X.") + "\n\n" +
                                  qsTr("The performance overlay is not supported on Steam Link or Raspberry Pi.")
                }

                CheckBox {
                    id: quitOnDisplaySleepCheck
                    width: parent.width
                    text: qsTr("Quit stream on display sleep")
                    font.pointSize: AppTheme.fontBody
                    visible: SystemProperties.hasDesktopEnvironment
                    checked: StreamingPreferences.quitOnDisplaySleep
                    onCheckedChanged: {
                        StreamingPreferences.quitOnDisplaySleep = checked
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Automatically quits the stream when the client display goes to sleep or is turned off.")
                }

                CheckBox {
                    id: detectResolutionChangeCheck
                    width: parent.width
                    text: qsTr("Automatically adapt to screen resolution changes")
                    font.pointSize: AppTheme.fontBody
                    enabled: resolutionListModel && resolutionComboBox &&
                             resolutionListModel.get(resolutionComboBox.currentIndex).video_width === "0"
                    checked: enabled && StreamingPreferences.detectResolutionChange
                    onCheckedChanged: {
                        if (enabled) {
                            StreamingPreferences.detectResolutionChange = checked
                        }
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Automatically detects when the client display resolution changes and prompts to restart the stream. Only available when using Auto resolution.")
                }

                CheckBox {
                    id: showResolutionChangeDialogCheck
                    width: parent.width
                    text: qsTr("Show confirmation dialog on resolution change")
                    font.pointSize: AppTheme.fontBody
                    enabled: detectResolutionChangeCheck.checked
                    checked: enabled && StreamingPreferences.showResolutionChangeDialog
                    onCheckedChanged: {
                        if (enabled) {
                            StreamingPreferences.showResolutionChangeDialog = checked
                        }
                    }

                    ToolTip.delay: 1000
                    ToolTip.timeout: 5000
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("When unchecked, the stream will restart automatically without prompting.")
                }
            }
        }
    }

    // Custom Resolution Dialog
    NavigableDialog {
        id: customResolutionDialog
        title: qsTr("Custom Resolution")
        standardButtons: Dialog.Ok | Dialog.Cancel

        function isInputValid() {
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
                }
            }
        }

        onOpened: {
            customWidthField.forceActiveFocus()
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
            }
        }

        function isInputValid() {
            if (customFpsField.acceptableInput && customFpsField.text) {
                var fps = parseInt(customFpsField.text)
                return fps >= 10 && fps <= 9999
            }
            if (!customFpsField.text && customFpsField.placeholderText) {
                var placeholderFps = parseInt(customFpsField.placeholderText)
                return !isNaN(placeholderFps) && placeholderFps >= 10 && placeholderFps <= 9999
            }
            return false
        }

        onOpened: {
            customFpsField.forceActiveFocus()
            if (customFpsDialog.standardButton) {
                customFpsDialog.standardButton(Dialog.Ok).enabled = customFpsDialog.isInputValid()
            }
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
