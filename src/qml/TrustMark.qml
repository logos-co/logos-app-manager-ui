import QtQuick

import Logos.Controls
import Logos.Icons
import Logos.Theme

import "Installer/Trust.js" as Trust

// Who signed a package, as Basecamp's install dialog marks it: a check or a
// warning, its words (Trust.js) on hover or a tap.
Item {
    id: root

    // A package's `trust` (AppManager::details()); without one, no mark.
    property var verdict
    property bool showsTooltip: true

    readonly property string description: Trust.description(root.verdict)

    visible: description.length > 0
    implicitWidth: 14
    implicitHeight: 14

    QtObject {
        id: d

        // Shown by a tap, for screens with no hover.
        property bool tapped: false
        readonly property color tint: {
            switch (Trust.tone(root.verdict)) {
            case "fine":
                return Theme.palette.success
            case "danger":
                return Theme.palette.error
            case "muted":
                return Theme.palette.textTertiary
            }
            return Theme.palette.warning
        }
    }

    LogosIcon {
        objectName: "trust.markIcon"
        anchors.fill: parent
        source: Trust.isCheck(root.verdict) ? LogosIcons.check : LogosIcons.warning
        brightness: 1.0
        color: d.tint
    }

    Accessible.role: Accessible.Graphic
    Accessible.name: description

    HoverHandler { id: hover }
    TapHandler {
        enabled: root.showsTooltip
        margin: Theme.spacing.small
        onTapped: d.tapped = !d.tapped
    }
    LogosToolTip {
        objectName: "trust.markTip"
        text: root.description
        placement: LogosToolTip.Top
        visible: root.showsTooltip && (hover.hovered || d.tapped)
    }
}
