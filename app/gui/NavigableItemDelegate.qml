import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

import "."

ItemDelegate {
    id: delegateRoot
    property GridView grid
    property int cardIndex: -1  // Set by delegate

    // Hover state - manually maintained, NOT bound to containsMouse.
    // MouseArea.containsMouse only updates on enter/leave events, so it stays
    // false when the mouse was already over a card when the page became visible.
    property bool cardHovered: false

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

    // Hover detection MouseArea — only used for enter/leave EVENT detection.
    // The actual cardHovered state is maintained manually via onContainsMouseChanged
    // plus the position-check timer below.
    MouseArea {
        id: hoverMouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: false

        onPressed: function(mouse) { mouse.accepted = true }
        onReleased: function(mouse) { mouse.accepted = true }
        onPositionChanged: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }

        // Sync cardHovered from MouseArea enter/leave events
        onContainsMouseChanged: {
            delegateRoot.cardHovered = containsMouse
        }
    }

    // Refresh hover when visibility changes (e.g. navigating back to this page)
    onVisibleChanged: {
        if (visible) {
            refreshHoverTimer.start()
        }
    }

    // Refresh when the parent grid regains active focus
    // (e.g. user navigates back from AppView to PcView).
    Connections {
        target: grid
        function onActiveFocusChanged() {
            if (grid && grid.activeFocus) {
                refreshHoverTimer.start()
            }
        }
    }

    // Also trigger on Component.onCompleted — onVisibleChanged does NOT fire
    // for newly created delegates (they start with visible: true by default).
    Component.onCompleted: {
        refreshHoverTimer.start()
    }

    // Timer-based hover refresh using QCursor::pos() via C++ helper.
    // This reliably detects if the cursor is over the card even when
    // MouseArea.containsMouse is stale (e.g. card appeared under cursor).
    Timer {
        id: refreshHoverTimer
        interval: 200
        onTriggered: {
            if (!delegateRoot.visible) return

            // Get cursor position via C++ helper (QCursor::pos())
            var globalPos = cursorHelper.cursorPos()

            // Map screen coordinates to local item coordinates
            var localPos = delegateRoot.mapFromGlobal(globalPos.x, globalPos.y)

            // Check if cursor is within this delegate's bounds
            var isMouseOver = delegateRoot.contains(localPos)

            // Update hover state directly (bypasses stale MouseArea.containsMouse)
            delegateRoot.cardHovered = isMouseOver
        }
    }
}
