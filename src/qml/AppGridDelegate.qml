import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Controls
import Logos.Icons
import Logos.Theme

import "Installer/Downloads.js" as Downloads
import "Installer/Stages.js" as Stages
import "Installer/Types.js" as Types
import "Icons.js" as Icons

ItemDelegate {
    id: root

    // ─── Public API ───
    property var appData: ({})
    // Basecamp's SandboxImages, which a sandboxed view shows images through;
    // none outside Basecamp, where an icon shows from its URL.
    property var sandboxImages: typeof SandboxImages !== "undefined" ? SandboxImages : null
    property int tileSize: 80
    property int labelSize: Theme.typography.subtitleText
    property bool contextMenuEnabled: true
    signal appClicked(string name, string repositoryUrl)
    // The menu's Open: the app as it is, whatever its tile says.
    signal openRequested(string name)
    signal detailsRequested(string name, string repositoryUrl)
    signal installRequested(string name, string repositoryUrl)
    signal uninstallRequested(string name, string repositoryUrl)

    QtObject {
        id: d

        readonly property bool isInstalled: !!root.appData && root.appData.isInstalled !== false
        readonly property int installStatus:
            root.appData && root.appData.installStatus !== undefined
                ? root.appData.installStatus
                : Types.InstallStatus.NotInstalled
        readonly property int installStage:
            root.appData && root.appData.planInstallStage !== undefined
                ? root.appData.planInstallStage
                : Types.InstallStage.None
        readonly property bool isInstalling:
            d.installStage === Types.InstallStage.Downloading
            || d.installStage === Types.InstallStage.Downloaded
            || d.installStage === Types.InstallStage.Queued
            || d.installStage === Types.InstallStage.Installing
        // What the badge offers for the app's status.
        readonly property int statusAction:
            d.installStatus === Types.InstallStatus.UpgradeAvailable   ? Types.RowAction.Upgrade
            : d.installStatus === Types.InstallStatus.DowngradeAvailable ? Types.RowAction.Downgrade
            : d.installStatus === Types.InstallStatus.DifferentHash      ? Types.RowAction.Reinstall
            : Types.RowAction.Install

        // Live download bytes — rendered as a percentage here rather than
        // two byte counts, because the tile badge is too narrow for them.
        readonly property real dlReceived:
            root.appData ? (root.appData.planDownloadReceived || 0) : 0
        readonly property real dlTotal:
            root.appData ? (root.appData.planDownloadTotal || 0) : 0
        readonly property bool downloadDone: d.dlTotal > 0 && d.dlReceived >= d.dlTotal
        readonly property string transport: root.appData ? (root.appData.planDownloadTransport || "") : ""
        readonly property string transportCaption: d.installStage === Types.InstallStage.Downloading
            ? Downloads.transportCaption(d.transport, root.appData && root.appData.planDownloadFellBack)
            : ""
        // The badge's tooltip while downloading: where the bytes come from.
        readonly property string downloadToolTip: d.findingPeers
            ? qsTr("Finding peers on Logos Storage that have this app")
            : d.transportCaption
        readonly property string badgeIconName: d.installStage === Types.InstallStage.Downloading
            ? Downloads.transportIconName(d.transport) : ""
        readonly property url badgeIcon: d.badgeIconName ? LogosIcons[d.badgeIconName] : ""
        // The badge's icon: 12px, and 4px spacing.
        readonly property int badgeIconWidth: 16
        readonly property bool findingPeers: d.installStage === Types.InstallStage.Downloading
            && !d.downloadDone && Downloads.findingPeers(d.transport, d.dlReceived)
        // A determinate bar claims a FRACTION, so it needs a real sample.
        // dlTotal is seeded from the catalog when the plan is registered —
        // before any transfer — so gating on it alone parked the bar at 0%.
        readonly property bool hasProgress:
            d.installStage === Types.InstallStage.Downloading && d.dlTotal > 0
            && d.dlReceived > 0 && !d.downloadDone
        // Nothing measurable yet: no bytes, or no size from transport or
        // catalog. Sweep rather than sit still.
        readonly property bool indeterminateProgress:
            d.installStage === Types.InstallStage.Downloading && !d.downloadDone
            && (d.dlReceived <= 0 || d.dlTotal <= 0)

        readonly property string nameText:      root.appData ? (root.appData.name || "") : ""
        readonly property string displayName:   root.appData ? (root.appData.displayName || root.appData.name || "") : ""
        readonly property string iconUrl:
            Icons.shown(root.sandboxImages, root.appData ? (root.appData.iconUrl || "") : "")
        // 0.4.0+ guarantees a validated 256x256 icon, so it can fill the
        // tile. Older packages ship a small glyph that must stay inset.
        readonly property bool fullBleedIcon:
            !!root.appData && root.appData.supportsFullBleedIcon === true
        readonly property string repositoryUrl: root.appData ? (root.appData.repositoryUrl || "") : ""
        readonly property string installType:   root.appData ? (root.appData.installType || "") : ""
        readonly property bool isAvailable:
            !root.appData
            || root.appData.hasInstallableVersion !== false
            || d.isInstalled

        readonly property real tileOpacity:
            !d.isAvailable            ? 0.35
            : (d.isInstalled || root.hovered) ? 1.0 : 0.55

        readonly property int tileSize: root.tileSize

        // Plain-object copy of the row for the context menu. `model` itself is
        // owned by the delegate and would dangle if the row recycled while the
        // menu is up, so snapshot the fields the menu reads.
        function snapshot() {
            return {
                name:          d.nameText,
                displayName:   d.displayName,
                repositoryUrl: d.repositoryUrl,
                isInstalled:   d.isInstalled,
                installStage:  d.installStage,
                installStatus: d.installStatus,
                installType:   d.installType,
            };
        }
    }

    function openDetails() {
        root.detailsRequested(d.nameText, d.repositoryUrl)
    }

    background: Item {}
    padding: 0
    hoverEnabled: true
    onClicked: if (d.isAvailable) root.appClicked(d.nameText, d.repositoryUrl)

    AppContextMenu {
        id: contextMenu
        contextFor: root.contextMenuEnabled ? root : null
        onAboutToShow: appData = d.snapshot()
        onOpenRequested:      (name, repo) => root.openRequested(name)
        onDetailsRequested:   (name, repo) => root.detailsRequested(name, repo)
        onInstallRequested:   (name, repo) => root.installRequested(name, repo)
        onUninstallRequested: (name, repo) => root.uninstallRequested(name, repo)
    }

    contentItem: Item {
        ColumnLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacing.small
            anchors.rightMargin: Theme.spacing.small
            spacing: Theme.spacing.medium

            Item {
                id: tile
                Layout.preferredWidth: d.tileSize
                Layout.preferredHeight: d.tileSize
                Layout.alignment: Qt.AlignHCenter

                LogosTile {
                    anchors.fill: parent
                    label: d.nameText
                    objectName: "appManager.tileIcon"
                    source: d.iconUrl
                    // No colour of its own, as Basecamp's sidebar shows it.
                    fallbackColor: Theme.palette.surfaceRaised
                    tileSize: d.tileSize
                    radius: Theme.spacing.radiusXlarge
                    dimOpacity: d.tileOpacity
                    insetArtwork: !d.fullBleedIcon
                    interactive: false
                }

                LogosBadge {
                    id: stateBadge
                    objectName: "appGridStateBadge"
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: Theme.spacing.tiny
                    width: (d.hasProgress || d.indeterminateProgress) && !d.findingPeers
                           ? 64 + (d.badgeIcon.toString().length > 0 ? d.badgeIconWidth : 0)
                           : implicitWidth
                    iconSource: d.badgeIcon
                    visible: !d.isAvailable
                             || d.isInstalling
                             || d.installStage === Types.InstallStage.Failed
                             || (d.installStatus !== Types.InstallStatus.Installed
                                 && (d.isInstalled || root.hovered))
                    text: !d.isAvailable    ? Stages.actionWord(Types.RowAction.NotAvailable)
                        : d.hasProgress     ? Downloads.percent(d.dlReceived, d.dlTotal)
                        : d.findingPeers    ? Stages.findingPeersWord()
                        // Waiting its turn: Basecamp asks about it once the install before it ends.
                        : d.installStage === Types.InstallStage.Queued ? Stages.stageWord(Types.InstallStage.Queued)
                        : d.isInstalling    ? Stages.stageWord(Types.InstallStage.Installing)
                        : d.installStage === Types.InstallStage.Failed ? Stages.stageWord(Types.InstallStage.Failed)
                        : Stages.actionWord(d.statusAction)
                    color: !d.isAvailable                                      ? Theme.palette.textTertiary
                         : d.isInstalling                                      ? Theme.palette.warning
                         : d.installStage === Types.InstallStage.Failed              ? Theme.palette.error
                         : d.installStatus === Types.InstallStatus.UpgradeAvailable      ? Theme.palette.info
                         : d.installStatus === Types.InstallStatus.DowngradeAvailable    ? Theme.palette.info
                         : d.installStatus === Types.InstallStatus.DifferentHash         ? Theme.palette.info
                                                                               : Theme.palette.accentOrange

                    backgroundColor: Theme.palette.surfaceRaised
                    radius: Theme.spacing.radiusXlarge

                    // Control's own hover, not a HoverHandler: one on the badge
                    // made it take the press, so clicking the label did nothing.
                    hoverEnabled: true
                    LogosToolTip {
                        objectName: "appGridStateBadge.toolTip"
                        text: d.installStage === Types.InstallStage.Downloading ? d.downloadToolTip : ""
                        placement: LogosToolTip.Top
                        visible: stateBadge.hovered && text.length > 0
                    }

                    Component.onCompleted: if (labelItem) labelItem.font.pixelSize = Theme.typography.badgeText

                    LogosProgressBar {
                        parent: stateBadge.backgroundItem
                        visible: d.hasProgress || d.indeterminateProgress
                        anchors.left: parent ? parent.left : undefined
                        anchors.right: parent ? parent.right : undefined
                        anchors.bottom: parent ? parent.bottom : undefined
                        anchors.margins: stateBadge.borderWidth + 1
                        height: 3

                        from: 0
                        to: d.dlTotal > 0 ? d.dlTotal : 1
                        value: d.dlReceived
                        indeterminate: d.indeterminateProgress

                        trackColor: "transparent"
                        fillColor: Theme.colors.getColor(Theme.palette.warning, 0.95)

                        Behavior on value {
                            NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }

            LogosText {
                id: label

                objectName: "appGridDelegate.label"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                text: d.displayName
                font.pixelSize: root.labelSize
                color: d.isInstalled ? Theme.palette.text : Theme.palette.textSubtle
                elide: Text.ElideRight
                LogosToolTip {
                    text: d.displayName
                    placement: LogosToolTip.Bottom
                    visible: root.hovered && label.truncated
                }
            }
        }
    }
}
