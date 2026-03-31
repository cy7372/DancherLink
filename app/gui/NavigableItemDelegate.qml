import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

import "."

ItemDelegate {
    id: delegateRoot
    property GridView grid
    property int cardIndex: -1  // Set by delegate

    // Local hover state - only true when mouse is over the card
    property bool isHovered: false

    // Disable built-in hover behavior
    hoverEnabled: false

    // CRITICAL: Use keyboardSelectedIndex instead of currentItem to avoid
    // GridView's automatic currentIndex behavior when using mouse
    highlighted: false
    property bool customHighlighted: grid && grid.keyboardSelectedIndex === cardIndex

    // Scale animation for hover effect
    scale: 1.0
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

    // Timer to check hover state after component is fully initialized
    // This solves the "hover not showing on page enter" issue
    Timer {
        id: hoverCheckTimer
        interval: 50  // Wait 50ms for layout to complete
        running: false
        repeat: false
        onTriggered: {
            // Force Qt to re-evaluate containsMouse by toggling hoverEnabled briefly
            hoverMouseArea.hoverEnabled = false
            hoverMouseArea.hoverEnabled = true
            // Check containsMouse after toggle
            if (hoverMouseArea.containsMouse) {
                delegateRoot.isHovered = true
                delegateRoot.scale = 1.03
            }
        }
    }

    // Hover detection MouseArea
    MouseArea {
        id: hoverMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: false

        // Accept all mouse events to prevent parent from intercepting
        onPressed: function(mouse) { mouse.accepted = true }
        onReleased: function(mouse) { mouse.accepted = true }
        onPositionChanged: function(mouse) {
            mouse.accepted = true
            // Real-time hover update based on actual position
            delegateRoot.isHovered = true
            delegateRoot.scale = 1.03
        }
        onWheel: function(wheel) { wheel.accepted = true }

        onEntered: {
            delegateRoot.isHovered = true
            delegateRoot.scale = 1.03
        }
        onExited: {
            delegateRoot.isHovered = false
            delegateRoot.scale = 1.0
        }

        onContainsMouseChanged: {
            delegateRoot.isHovered = containsMouse
            delegateRoot.scale = containsMouse ? 1.03 : 1.0
        }
    }

    // FUNDAMENTAL FIX: Check hover state when page becomes visible
    // This handles the case where mouse is already over the card when page loads
    onVisibleChanged: {
        if (visible) {
            hoverCheckTimer.start()
        }
    }
}
