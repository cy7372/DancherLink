import QtQuick 2.15
import QtQuick.Controls 2.15

import ".."

GroupBox {
    id: groupBox

    // Auto-fill parent container width for responsive layout
    width: parent ? parent.width : implicitWidth

    // Default padding matching original SettingsView style
    padding: 12
    font.pointSize: 12

    // Use the theme's group title color
    property color titleColor: AppTheme.groupTitle

    label: Label {
        text: groupBox.title
        color: groupBox.titleColor
        font.pointSize: 12
        font.bold: true
        elide: Text.ElideRight
        padding: 0
        bottomPadding: 5
    }
}
