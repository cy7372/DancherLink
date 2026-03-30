import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ItemDelegate {
    property GridView grid

    highlighted: grid.activeFocus && grid.currentItem === this

    hoverEnabled: true

    // Transparent MouseArea to ensure hover events are captured
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: -1  // Behind all other content
    }

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

