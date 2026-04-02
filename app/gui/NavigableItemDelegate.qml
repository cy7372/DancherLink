import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

import "."

ItemDelegate {
    id: delegateRoot
    property GridView grid
    property int cardIndex: -1  // Set by delegate

    // Hover state from card's own MouseArea
    property bool cardHovered: hoverMouseArea.containsMouse

    // Hover state from child buttons (set by buttons when hovered)
    property bool childHovered: false

    // Combined hover state - automatic binding, no manual sync needed
    property bool isHovered: cardHovered || childHovered

    // Disable built-in hover behavior
    hoverEnabled: false

    // CRITICAL: Use keyboardSelectedIndex instead of currentItem to avoid
    // GridView's automatic currentIndex behavior when using mouse
    highlighted: false
    property bool customHighlighted: grid && grid.keyboardSelectedIndex === cardIndex

    // Scale animation for hover effect - automatically follows isHovered
    scale: isHovered ? 1.03 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: AppTheme.animationDurationFast
            easing.type: Easing.OutCubic
        }
    }

    // CRITICAL: Update keyboardSelectedIndex only on keyboard navigation
    Keys.onLeftPressed: {
        if (grid && grid.count > 0) {
            grid.keyboardSelectedIndex = Math.max(0, grid.keyboardSelectedIndex - 1)
            grid.moveCurrentIndexLeft()
        }
    }
    Keys.onRightPressed: {
        if (grid && grid.count > 0) {
            grid.keyboardSelectedIndex = Math.min(grid.count - 1, grid.keyboardSelectedIndex + 1)
            grid.moveCurrentIndexRight()
        }
    }
    Keys.onDownPressed: {
        if (grid && grid.count > 0) {
            grid.keyboardSelectedIndex = Math.min(grid.count - 1, grid.keyboardSelectedIndex + 1)
            grid.moveCurrentIndexDown()
        }
    }
    Keys.onUpPressed: {
        if (grid && grid.count > 0) {
            grid.keyboardSelectedIndex = Math.max(0, grid.keyboardSelectedIndex - 1)
            grid.moveCurrentIndexUp()
        }
    }
    Keys.onReturnPressed: {
        clicked()
    }
    Keys.onEnterPressed: {
        clicked()
    }

    // Common background - shared by all delegates
    background: Rectangle {
        id: delegateBackground
        width: delegateRoot.width
        height: delegateRoot.height
        // Use isHovered for hover state, customHighlighted for keyboard/gamepad focus
        color: delegateRoot.isHovered ? AppTheme.backgroundHover : (delegateRoot.customHighlighted ? AppTheme.backgroundHighlighted : "transparent")
        radius: AppTheme.borderRadius

        Behavior on color {
            ColorAnimation {
                duration: AppTheme.animationDurationFast
                easing.type: Easing.OutCubic
            }
        }
    }

    // Hover detection MouseArea for the card itself
    MouseArea {
        id: hoverMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: false

        // Accept all mouse events to prevent parent from intercepting
        onPressed: function(mouse) { mouse.accepted = true }
        onReleased: function(mouse) { mouse.accepted = true }
        onPositionChanged: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }
    }

    // Force refresh hover state when visibility changes (e.g. navigating back to this page)
    // MouseArea.containsMouse only updates on mouse enter/leave events, so if the mouse
    // was already over a card when the page became visible, containsMouse stays false.
    onVisibleChanged: {
        if (visible) {
            refreshHoverTimer.start()
        }
    }

    // Additional refresh when the parent grid regains active focus
    // (e.g. user navigates back from AppView to PcView).
    Connections {
        target: grid
        function onActiveFocusChanged() {
            if (grid && grid.activeFocus) {
                refreshHoverTimer.start()
            }
        }
    }

    // Use a Timer to delay the hover refresh until the delegate is fully laid out.
    // Qt.callLater is too early — the delegate may not have its final position yet.
    Timer {
        id: refreshHoverTimer
        interval: 50
        onTriggered: {
            // Check if mouse is currently over this delegate
            var window = delegateRoot.Window.window
            if (!window) return
            var mousePos = mapFromItem(null, window.mouseX, window.mouseY)
            var isMouseOver = delegateRoot.contains(mousePos)

            // Force MouseArea to re-evaluate containsMouse by toggling hoverEnabled.
            // This is needed because containsMouse only updates on enter/leave events.
            if (isMouseOver !== hoverMouseArea.containsMouse) {
                hoverMouseArea.hoverEnabled = false
                hoverMouseArea.hoverEnabled = true
            }
        }
    }
}
