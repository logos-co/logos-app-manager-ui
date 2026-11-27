import QtQuick
import QtQuick.Layouts

import Logos.Controls
import Logos.Theme

// Who signed a package, as the mark and its words.
RowLayout {
    id: root

    // A package's `trust` (AppManager::details()); without one, no line.
    property var verdict

    visible: mark.description.length > 0
    spacing: Theme.spacing.tiny

    TrustMark {
        id: mark
        Layout.alignment: Qt.AlignTop
        verdict: root.verdict
        showsTooltip: false
    }

    LogosText {
        objectName: "trust.lineWords"
        Layout.fillWidth: true
        text: mark.description
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
    }
}
