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

        // Use onEntered/onExited for reliable hover detection
        onEntered: {
            delegateRoot.isHovered = true
            delegateRoot.scale = 1.03
        }
        onExited: {
            delegateRoot.isHovered = false
            delegateRoot.scale = 1.0
        }

        onContainsMouseChanged: {
            // Fallback: sync state if containsMouse changes without entered/exited signal
            // This can happen when hoverEnabled is toggled
            delegateRoot.isHovered = containsMouse
            delegateRoot.scale = containsMouse ? 1.03 : 1.0
        }
    }

    // CRITICAL: Refresh hover state when view becomes visible
    // When a page is first shown, the mouse may already be over a card
    // but MouseArea hasn't detected it yet. We need to force a check.
    onVisibleChanged: {
        if (visible) {
            // Use double Qt.callLater to ensure Qt has time to update containsMouse
            Qt.callLater(function() {
                hoverMouseArea.hoverEnabled = false
                hoverMouseArea.hoverEnabled = true
                // CRITICAL: Need another Qt.callLater to check containsMouse
                // because Qt needs a full event loop cycle to update the mouse state
                Qt.callLater(function() {
                    if (hoverMouseArea.containsMouse && !delegateRoot.isHovered) {
                        delegateRoot.isHovered = true
                        delegateRoot.scale = 1.03
                    }
                })
            })
        }
    }
}
