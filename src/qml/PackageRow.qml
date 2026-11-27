import QtQuick
import QtQuick.Layouts

import Logos.Controls
import Logos.Icons
import Logos.Theme

import "Installer/Downloads.js" as Downloads
import "Installer/Stages.js" as Stages
import "Installer/Types.js" as Types

// One package an app brings, in its details, as Basecamp's install dialog
// listed it: its name and state, the version it would install, picked here,
// against what is on disk, and its description. While it installs, the state
// counts its bytes and says where they come from. An optional package is
// ticked to come; what comes only with one sits under it. The picks go to
// Basecamp with the install.
Item {
    id: root

    // One of the details' `packages` (PackageModel::packagesBroughtBy()).
    property var row: ({})
    // Nothing is picked while an install runs.
    property bool installing: false

    // By the version's name: the backend's list may have moved since.
    signal versionPicked(string name, string repositoryUrl, string version)
    signal optionalToggled(string name, bool selected)

    implicitHeight: content.implicitHeight + 2 * Theme.spacing.small

    QtObject {
        id: d

        readonly property var r: root.row || ({})
        readonly property var versions: r.versions || []
        // The versions this host can fetch, as indices into `versions`: the
        // only ones offered, as Basecamp's install dialog had it.
        readonly property var served: {
            const ok = r.versionsServed || []
            const out = []
            for (let i = 0; i < versions.length; ++i)
                if (ok[i] !== false) out.push(i)
            return out
        }
        readonly property bool picksVersion: r.found !== false && served.length > 0
        // Comes only with the optional package above it.
        readonly property bool nested: (r.requiredFor || "").length > 0
        readonly property bool inFlight: r.installing === true
        readonly property real received: Number(r.downloadReceived) || 0
        readonly property real total: Number(r.downloadTotal) || 0
        readonly property string transport: inFlight ? (r.downloadTransport || "") : ""
        readonly property bool downloading: inFlight && r.installStage === Types.InstallStage.Downloading
        readonly property bool hasProgress: downloading && Downloads.transferring(received, total)
        readonly property bool indeterminate: downloading && !hasProgress
                                              && !(total > 0 && received >= total)
        readonly property string iconName: downloading ? Downloads.transportIconName(transport) : ""
        readonly property int action: r.found === false ? Types.RowAction.NotAvailable
                                    : r.rowAction !== undefined ? r.rowAction : Types.RowAction.NoOp
        // Its version doesn't satisfy what asks for it.
        readonly property bool conflict: !inFlight && r.conflict === true
        readonly property string stateText: inFlight
            ? Stages.progressWord({ queued: r.queued === true, transport: transport,
                                    received: received, total: total })
            : conflict ? qsTr("Conflict") : Stages.actionWord(action)
        readonly property color stateColor: {
            if (inFlight) return Theme.palette.warning
            if (conflict) return Theme.palette.error
            switch (action) {
            case Types.RowAction.Install:      return Theme.palette.primary
            case Types.RowAction.Upgrade:
            case Types.RowAction.Downgrade:
            case Types.RowAction.Reinstall:    return Theme.palette.info
            case Types.RowAction.Retry:        return Theme.palette.error
            }
            return Theme.palette.textTertiary
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosCheckbox {
                id: optionalBox
                objectName: "packageRow.optional"
                visible: d.r.optional === true
                // One that comes with the optional package above has nothing to
                // tick, and keeps the box's place, so it lines up with the rest.
                opacity: d.nested ? 0 : 1
                Accessible.ignored: d.nested
                // On disk with nothing in a catalog: kept, nothing to choose.
                enabled: !d.nested && !root.installing && d.r.found !== false && d.r.installedOnly !== true
                         && d.r.rowAction !== Types.RowAction.NotAvailable
                checked: d.r.selected === true
                onToggled: root.optionalToggled(d.r.name || "", checked)
            }

            LogosText {
                id: nameLabel
                objectName: "packageRow.name"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                // Its own width, so the mark sits right after it.
                Layout.maximumWidth: Math.ceil(implicitWidth)
                text: d.r.displayName || d.r.name || ""
                font.weight: Theme.typography.weightMedium
                font.pixelSize: Theme.typography.primaryText
                color: Theme.palette.text
                elide: Text.ElideRight

                HoverHandler { id: nameHover }
                LogosToolTip {
                    text: nameLabel.text
                    visible: nameHover.hovered && nameLabel.truncated
                }
            }

            TrustMark {
                objectName: "packageRow.trust"
                Layout.alignment: Qt.AlignVCenter
                verdict: d.r.trust
            }

            Item { Layout.fillWidth: true }

            LogosBadge {
                id: badge
                objectName: "packageRow.state"
                Layout.alignment: Qt.AlignVCenter
                // As wide as the widest count of bytes while it installs, so
                // the row doesn't jump as they move.
                Layout.preferredWidth: d.inFlight
                    ? Math.ceil(widest.width) + leftPadding + rightPadding + (d.iconName ? 16 : 0)
                    : implicitWidth
                text: d.stateText
                iconSource: d.iconName ? LogosIcons[d.iconName] : ""
                color: d.stateColor
                radius: Theme.spacing.radiusLarge

                // Where the bytes come from.
                HoverHandler { id: badgeHover }
                LogosToolTip {
                    objectName: "packageRow.transport"
                    text: d.downloading ? Downloads.transportCaption(d.transport, d.r.downloadFellBack === true) : ""
                    visible: badgeHover.hovered && text.length > 0
                }

                TextMetrics {
                    id: widest
                    font: badge.labelItem.font
                    text: Downloads.widestProgressLabel
                }

                LogosProgressBar {
                    parent: badge.backgroundItem
                    visible: d.hasProgress || d.indeterminate
                    anchors.left: parent ? parent.left : undefined
                    anchors.right: parent ? parent.right : undefined
                    anchors.bottom: parent ? parent.bottom : undefined
                    anchors.margins: badge.borderWidth + 1
                    height: 3
                    from: 0
                    to: d.total > 0 ? d.total : 1
                    value: d.received
                    indeterminate: d.indeterminate
                    trackColor: "transparent"
                    fillColor: Theme.colors.getColor(Theme.palette.warning, 0.95)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosComboBox {
                objectName: "packageRow.versionPicker"
                visible: d.picksVersion
                enabled: !root.installing
                Layout.preferredWidth: 110
                model: d.served.map(i => d.versions[i])
                currentIndex: d.served.indexOf(d.r.selectedVersionIndex || 0)
                displayText: currentText ? "v" + currentText : ""
                onActivated: (index) => root.versionPicked(d.r.name || "", d.r.repositoryUrl || "",
                                                           d.versions[d.served[index]] || "")
            }
            // What is on disk, and what it would become; with nothing this
            // host can fetch, the version it would be.
            LogosText {
                objectName: "packageRow.version"
                Layout.fillWidth: true
                visible: text.length > 0
                text: d.r.installedVersion ? Stages.transitionText(d.r.installedVersion, d.r.version)
                    : !d.picksVersion && d.r.version ? "v" + d.r.version : ""
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                elide: Text.ElideRight
            }
        }

        LogosText {
            id: descriptionLabel
            objectName: "packageRow.description"
            Layout.fillWidth: true
            visible: text.length > 0
            text: d.r.description || ""
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textTertiary
            elide: Text.ElideRight

            HoverHandler { id: descriptionHover }
            LogosToolTip {
                text: descriptionLabel.text
                visible: descriptionHover.hovered && descriptionLabel.truncated
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.palette.borderSubtle
    }
}
