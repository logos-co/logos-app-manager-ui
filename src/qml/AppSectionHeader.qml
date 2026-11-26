import QtQuick
import QtQuick.Layouts

import Logos.Controls
import Logos.Theme

// A repository's section in the list: its title and how many apps it has,
// over a rule. The first section has no gap above it.
ColumnLayout {
    id: root

    property string title: ""
    property int count: 0
    property bool first: false

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: root.first ? 0 : Theme.spacing.large
        spacing: Theme.spacing.small

        LogosText {
            id: titleLabel
            objectName: "appSection.title"
            text: root.title
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightMedium
            color: Theme.palette.textSecondary
            elide: Text.ElideRight
            Layout.fillWidth: true

            HoverHandler { id: titleHover }
            LogosToolTip {
                text: root.title
                placement: LogosToolTip.Top
                visible: titleHover.hovered && titleLabel.truncated
            }
        }

        LogosText {
            objectName: "appSection.count"
            text: "(" + root.count + ")"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textTertiary
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.topMargin: Theme.spacing.medium
        Layout.bottomMargin: Theme.spacing.medium
        color: Theme.palette.borderSubtle
        opacity: 0.5
    }
}
