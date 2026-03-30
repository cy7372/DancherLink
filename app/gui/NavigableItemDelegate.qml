import QtQuick 2.15
import QtQuick.Controls 2.15

ItemDelegate {
    property GridView grid
    property int cardIndex: -1  // Set by delegate

    // Disable built-in hover behavior - delegates define their own hover detection
    hoverEnabled: false

    // CRITICAL: Use keyboardSelectedIndex instead of currentItem to avoid
    // GridView's automatic currentIndex behavior when using mouse
    highlighted: false
    property bool customHighlighted: grid.keyboardSelectedIndex === cardIndex

    // CRITICAL: Update keyboardSelectedIndex only on keyboard navigation
    // This ensures highlighted state is only true when using keyboard/gamepad
    Keys.onLeftPressed: {
        grid.keyboardSelectedIndex = Math.max(0, grid.keyboardSelectedIndex - 1)
        grid.moveCurrentIndexLeft()
    }
    Keys.onRightPressed: {
        grid.keyboardSelectedIndex = Math.min(grid.count - 1, grid.keyboardSelectedIndex + 1)
        grid.moveCurrentIndexRight()
    }
    Keys.onDownPressed: {
        grid.keyboardSelectedIndex = Math.min(grid.count - 1, grid.keyboardSelectedIndex + 1)
        grid.moveCurrentIndexDown()
    }
    Keys.onUpPressed: {
        grid.keyboardSelectedIndex = Math.max(0, grid.keyboardSelectedIndex - 1)
        grid.moveCurrentIndexUp()
    }
    Keys.onReturnPressed: {
        clicked()
    }
    Keys.onEnterPressed: {
        clicked()
    }
}

