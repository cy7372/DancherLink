import QtQuick 2.15
import QtQuick.Controls 2.15

Dialog {
    // Center in the overlay (window)
    anchors.centerIn: Overlay.overlay
    modal: true

    onAboutToHide: {
        // We must force focus back to the last item for platforms without
        // support for more than one active window like Steam Link. If
        // we don't, gamepad and keyboard navigation will break after a
        // dialog appears.
        stackView.forceActiveFocus()
    }
}

