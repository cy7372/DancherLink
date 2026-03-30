import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ItemDelegate {
    property GridView grid
    property bool hovered: mouseArea.containsMouse

    highlighted: grid.activeFocus && grid.currentItem === this

    hoverEnabled: true

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

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton  // Don't intercept clicks
    }
}

