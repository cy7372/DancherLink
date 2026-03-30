import QtQuick 2.15
import QtQuick.Controls 2.15

ItemDelegate {
    property GridView grid

    // Disable built-in hover behavior - delegates define their own hover detection
    hoverEnabled: false

    // Use customHighlighted instead of built-in highlighted to avoid interference
    highlighted: false
    property bool customHighlighted: grid.activeFocus && grid.currentItem === this

    Keys.onLeftPressed: {
        grid.moveCurrentIndexLeft()
    }
    Keys.onRightPressed: {
        grid.moveCurrentIndexRight()
    }
    Keys.onDownPressed: {
        grid.moveCurrentIndexDown()
    }
    Keys.onUpPressed: {
        grid.moveCurrentIndexUp()
    }
    Keys.onReturnPressed: {
        clicked()
    }
    Keys.onEnterPressed: {
        clicked()
    }
}

