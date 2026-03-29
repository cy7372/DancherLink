import QtQuick 2.15
import QtQuick.Controls 2.15

import ".."

GroupBox {
    id: groupBox

    // Match original SettingsView GroupBox width calculation
    // When inside a Column with padding, we need to subtract left/right padding
    width: parent ? (parent.width - (parent.leftPadding + parent.rightPadding)) : implicitWidth

    // Default padding matching original SettingsView style
    padding: AppTheme.spacingMd
    font.pointSize: AppTheme.fontCaption

    // Use the theme's group title color
    property color titleColor: AppTheme.groupTitle

    label: Label {
        text: groupBox.title
        color: groupBox.titleColor
        font.pointSize: AppTheme.fontCaption
        font.bold: true
        elide: Text.ElideRight
        padding: 0
        bottomPadding: AppTheme.spacingXs
    }
}
