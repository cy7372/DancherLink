pragma Singleton
import QtQuick 2.15

QtObject {
    // ============================================
    // Animation Durations (ms) - referenced from AppTheme
    // ============================================
    // Note: These are defined in AppTheme.qml, this file is for future expansion

    // ============================================
    // Easing Types (convenience constants)
    // ============================================
    readonly property int easingOutCubic: Easing.OutCubic
    readonly property int easingInCubic: Easing.InCubic
    readonly property int easingInOutCubic: Easing.InOutCubic
}
