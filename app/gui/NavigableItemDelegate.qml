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

    // Disable built-in hover behavior - delegates define their own hover detection
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

    // Hover detection MouseArea - MUST be declared last to be on top
    MouseArea {
        id: hoverMouseArea
        parent: delegateRoot
        x: 0
        y: 0
        width: delegateRoot.width
        height: delegateRoot.height
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        // CRITICAL: Accept mouse events to prevent GridView/Flickable from intercepting
        onPressed: function(mouse) { mouse.accepted = true }
        onReleased: function(mouse) { mouse.accepted = true }
        onPositionChanged: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }
        propagateComposedEvents: false

        onContainsMouseChanged: {
            delegateRoot.isHovered = containsMouse
            // Scale effect on hover
            delegateRoot.scale = containsMouse ? 1.03 : 1.0
        }
    }

    // CRITICAL: Refresh hover state when view becomes visible
    // Toggle hoverEnabled to force MouseArea to re-detect mouse position
    onVisibleChanged: {
        if (visible) {
            // Use Qt.callLater to ensure layout is complete before toggling
            Qt.callLater(function() {
                hoverMouseArea.hoverEnabled = false
                hoverMouseArea.hoverEnabled = true
                // CRITICAL: After re-enabling, check if mouse is already over the area
                // This handles the case where mouse was already hovering before component loaded
                if (hoverMouseArea.containsMouse && !delegateRoot.isHovered) {
                    delegateRoot.isHovered = true
                    delegateRoot.scale = 1.03
                }
            })
        }
    }
}
