import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Controls
import Logos.Icons
import Logos.Layouts
import Logos.Theme

import "Installer/Downloads.js" as Downloads
import "Installer/Stages.js" as Stages
import "Installer/Types.js" as Types
import "Icons.js" as Icons

// One app, beside the list as Package Manager shows a package: what it is,
// who signed it, its version, what installing it brings, each at the version
// picked on its row, and what can be done with it: open it, install, upgrade,
// downgrade or reinstall it at that version, or remove it. Basecamp approves
// each change; this panel only asks.
Rectangle {
    id: root
    objectName: "appManager.details"

    // The app's row, every role by name, `packages`, what it brings, and
    // `trust`, who signed it: the backend's `details`.
    property var app: ({})
    // Beside the list it has its own title and ✕; as the page (a phone) the
    // side panel's bar is the way back.
    property bool showHeader: true
    // Basecamp's SandboxImages, which a sandboxed view shows images through;
    // none outside Basecamp, where an icon shows from its URL.
    property var sandboxImages: typeof SandboxImages !== "undefined" ? SandboxImages : null

    signal closeRequested()
    signal openRequested(string name)
    signal installRequested(string name, string repositoryUrl)
    signal uninstallRequested(string name, string repositoryUrl)
    // Of the app or of a package it brings.
    signal versionPicked(string name, string repositoryUrl, string version)
    signal optionalToggled(string name, bool selected)

    color: Theme.palette.surfaceRaised
    radius: Theme.spacing.radiusXlarge
    clip: true

    QtObject {
        id: d

        readonly property var app: root.app || ({})
        readonly property string name: app.name || ""
        readonly property string displayName: app.displayName || name
        readonly property string repositoryUrl: app.repositoryUrl || ""
        readonly property bool installed: app.isInstalled === true
        readonly property string installedVersion: app.installedVersion || ""

        readonly property int stage: app.planInstallStage !== undefined
                                     ? app.planInstallStage : Types.InstallStage.None
        readonly property bool installing: stage === Types.InstallStage.Downloading
                                            || stage === Types.InstallStage.Downloaded
                                            || stage === Types.InstallStage.Queued
                                            || stage === Types.InstallStage.Installing
        readonly property bool failed: stage === Types.InstallStage.Failed
        readonly property int action: app.rowAction !== undefined ? app.rowAction : Types.RowAction.NoOp
        readonly property bool available: action !== Types.RowAction.NotAvailable

        readonly property var versions: app.availableVersions || []
        readonly property int versionIndex: app.selectedVersionIndex || 0
        readonly property var version: versions[versionIndex] || ({})
        readonly property string versionText: version.version || app.version || ""

        // On disk and put there by the person; the shell itself never.
        readonly property bool canUninstall: installedVersion.length > 0 && !installing
                                             && app.installType === "user" && name !== "main_ui"

        // ─── What installing it brings: the app itself first ───
        readonly property var packages: app.packages || []
        readonly property var required: packages.filter(p => !p.optional)
        readonly property var optional: packages.filter(p => p.optional)
        readonly property var self: required.length > 0 && required[0].subject ? required[0] : ({})
        function changes(a) {
            return a === Types.RowAction.Install || a === Types.RowAction.Upgrade
                || a === Types.RowAction.Downgrade || a === Types.RowAction.Reinstall
                || a === Types.RowAction.Retry
        }
        readonly property var changing: required.filter(p => p.found && !p.installing && changes(p.rowAction))
        readonly property var changingDeps: changing.filter(p => !p.subject)
        readonly property int installingCount: required.filter(p => p.installing).length
        readonly property int installedCount:
            required.filter(p => p.found && !p.installing && p.rowAction === Types.RowAction.NoOp).length
        // A package it needs no repository has, or at a version that doesn't
        // satisfy what asks for it: Basecamp would refuse the plan.
        readonly property bool unresolved: required.some(p => !p.found || p.conflict === true)
        // Another install is bringing one of them: wait for it.
        readonly property bool waiting: !installing && installingCount > 0
        // An optional package ticked, or what comes with one, would change, or
        // one it needs at the version picked.
        readonly property bool pendingChanges:
            optional.some(p => (p.offeredBy === undefined || p.selected === true) && changes(p.rowAction))
            || required.some(p => p.picked === true && !p.subject && changes(p.rowAction))
        readonly property real downloadBytes: changing.reduce((sum, p) => sum + (Number(p.size) || 0), 0)

        // What installing it does, in the Add Application dialog's words.
        readonly property string footer: {
            if (installing)
                return installingCount > 0
                    ? Stages.fill(qsTr("%1 %2 package(s)…"), Stages.stageWord(stage), installingCount)
                    : Stages.stageWord(stage)
            if (installingCount > 0 && changing.length === 0)
                return Stages.fill(qsTr("%1 of %2's required package(s) are currently being installed. "
                                        + "Wait for the active install to finish before opening %2."),
                                   installingCount, displayName)
            if (changing.length === 0) return ""
            if (changingDeps.length === 0) {
                const from = self.installedVersion || ""
                const to = self.version || ""
                switch (self.rowAction) {
                case Types.RowAction.Install:
                case Types.RowAction.Retry:
                    return Stages.fill(qsTr("%1 will be installed."), displayName)
                case Types.RowAction.Upgrade:
                    return from && to
                        ? Stages.fill(qsTr("%1 will be upgraded from %2 to %3."), displayName, from, to)
                        : Stages.fill(qsTr("%1 will be upgraded."), displayName)
                case Types.RowAction.Downgrade:
                    return from && to
                        ? Stages.fill(qsTr("%1 will be downgraded from %2 to %3."), displayName, from, to)
                        : Stages.fill(qsTr("%1 will be downgraded."), displayName)
                case Types.RowAction.Reinstall:
                    return Stages.fill(qsTr("%1 will be reinstalled."), displayName)
                }
                return ""
            }
            const count = a => changingDeps.filter(p => a.indexOf(p.rowAction) >= 0).length
            const missing = count([Types.RowAction.Install, Types.RowAction.Retry])
            const outdated = count([Types.RowAction.Upgrade, Types.RowAction.Downgrade])
            const broken = count([Types.RowAction.Reinstall])
            let stateText, actionText
            if (outdated > 0 && missing === 0 && broken === 0) {
                stateText = qsTr("have become outdated")
                actionText = qsTr("please update your dependencies")
            } else if (missing > 0 && outdated === 0 && broken === 0) {
                stateText = qsTr("are missing")
                actionText = qsTr("please install your dependencies")
            } else if (broken > 0 && outdated === 0 && missing === 0) {
                stateText = qsTr("need to be reinstalled")
                actionText = qsTr("please reinstall your dependencies")
            } else {
                stateText = qsTr("need updates")
                actionText = qsTr("please update your dependencies")
            }
            return Stages.fill(qsTr("%1 out of %2 required package dependencies %3, "
                                    + "%4 to be able to use the %5 application."),
                               changingDeps.length, required.length - 1, stateText, actionText, displayName)
        }

        function released(iso) {
            if (!iso) return ""
            const dt = new Date(iso)
            if (isNaN(dt.getTime())) return ""
            return dt.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.medium
        spacing: Theme.spacing.small

        // ─── Header: title and ✕ ───
        RowLayout {
            visible: root.showHeader
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                Layout.fillWidth: true
                text: qsTr("Details")
                font.pixelSize: Theme.typography.panelTitleText
                font.weight: Theme.typography.weightMedium
                color: Theme.palette.text
            }

            LogosIconButton {
                objectName: "appManager.details.close"
                iconSource: LogosIcons.close
                size: 28
                iconSize: 14
                iconColor: Theme.palette.textTertiary
                onClicked: root.closeRequested()
            }
        }

        LogosScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Theme.spacing.large

                // ─── Showcase ───
                ColumnLayout {
                    objectName: "appManager.details.showcase"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.small
                    spacing: Theme.spacing.small

                    LogosTile {
                        objectName: "appManager.details.icon"
                        Layout.alignment: Qt.AlignHCenter
                        label: d.displayName
                        source: Icons.shown(root.sandboxImages, d.app.iconUrl || "")
                        // No colour of its own; the panel is surfaceRaised.
                        fallbackColor: Theme.palette.background
                        tileSize: 64
                        insetArtwork: d.app.supportsFullBleedIcon !== true
                        interactive: false
                    }

                    LogosText {
                        objectName: "appManager.details.name"
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: d.displayName
                        font.pixelSize: Theme.typography.primaryText
                        font.weight: Theme.typography.weightMedium
                        color: Theme.palette.text
                    }

                    // Who signed it, as Basecamp's install dialog says it:
                    // centred at its own width, wrapped where that's too wide.
                    TrustLine {
                        objectName: "appManager.details.trust"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        Layout.maximumWidth: Math.ceil(implicitWidth)
                        verdict: d.app.trust
                    }
                }

                // ─── Description ───
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.tiny
                    visible: (d.app.description || "").length > 0

                    LogosText {
                        Layout.fillWidth: true
                        text: qsTr("Description")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textTertiary
                    }
                    LogosText {
                        objectName: "appManager.details.description"
                        Layout.fillWidth: true
                        text: d.app.description || ""
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.typography.primaryText
                        color: Theme.palette.text
                    }
                }

                // ─── The version: released, its size ───
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: versionRow.implicitHeight + 2 * Theme.spacing.medium
                    color: Theme.palette.background
                    radius: Theme.spacing.radiusMedium
                    visible: d.versionText.length > 0

                    RowLayout {
                        id: versionRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacing.medium
                        anchors.rightMargin: Theme.spacing.medium
                        spacing: Theme.spacing.large

                        LogosText {
                            objectName: "appManager.details.version"
                            text: qsTr("Version %1").arg(d.versionText)
                            color: Theme.palette.text
                            font.pixelSize: Theme.typography.secondaryText
                            font.weight: Theme.typography.weightMedium
                        }
                        // When short of room these give up theirs first.
                        LogosText {
                            objectName: "appManager.details.released"
                            Layout.minimumWidth: 0
                            text: d.released(d.version.releasedAt)
                            color: Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText
                            elide: Text.ElideRight
                        }
                        LogosText {
                            objectName: "appManager.details.size"
                            Layout.minimumWidth: 0
                            // What installing it downloads, everything it
                            // brings; else the app's own.
                            text: d.downloadBytes > 0 ? Downloads.bytes(d.downloadBytes)
                                : d.version.size > 0 ? Downloads.bytes(d.version.size) : ""
                            color: Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText
                            elide: Text.ElideRight
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ─── Required packages: each with its state ───
                ColumnLayout {
                    objectName: "appManager.details.packages"
                    Layout.fillWidth: true
                    spacing: 0
                    visible: d.required.length > 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Theme.spacing.tiny
                        LogosText {
                            Layout.fillWidth: true
                            text: qsTr("Required Packages")
                            font.pixelSize: Theme.typography.primaryText
                            font.weight: Theme.typography.weightMedium
                            color: Theme.palette.text
                        }
                        LogosText {
                            objectName: "appManager.details.packagesCount"
                            text: d.installedCount + " / " + d.required.length
                            font.pixelSize: Theme.typography.primaryText
                            color: Theme.palette.textSecondary
                        }
                    }

                    Repeater {
                        model: d.required
                        delegate: PackageRow {
                            required property var modelData
                            objectName: "appManager.details.package." + modelData.name
                            Layout.fillWidth: true
                            row: modelData
                            installing: d.installing
                            onVersionPicked: (name, repositoryUrl, version) =>
                                root.versionPicked(name, repositoryUrl, version)
                            onOptionalToggled: (name, selected) => root.optionalToggled(name, selected)
                        }
                    }
                }

                // ─── Optional packages: ticked to come, each with what it brings ───
                ColumnLayout {
                    objectName: "appManager.details.optional"
                    Layout.fillWidth: true
                    spacing: 0
                    visible: d.optional.length > 0

                    LogosText {
                        Layout.fillWidth: true
                        text: qsTr("Optional Packages")
                        font.pixelSize: Theme.typography.primaryText
                        font.weight: Theme.typography.weightMedium
                        color: Theme.palette.text
                    }
                    LogosText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Theme.spacing.tiny
                        text: qsTr("Selected packages and the packages they need come with it.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                    Repeater {
                        model: d.optional
                        delegate: PackageRow {
                            required property var modelData
                            objectName: "appManager.details.package." + modelData.name
                            Layout.fillWidth: true
                            row: modelData
                            installing: d.installing
                            onVersionPicked: (name, repositoryUrl, version) =>
                                root.versionPicked(name, repositoryUrl, version)
                            onOptionalToggled: (name, selected) => root.optionalToggled(name, selected)
                        }
                    }
                }

                // ─── What installing it does ───
                LogosText {
                    objectName: "appManager.details.resolutionBanner"
                    Layout.fillWidth: true
                    visible: !d.failed && d.unresolved
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.warning
                    text: qsTr("Some required packages could not be resolved. "
                               + "Adjust versions or check your repositories.")
                }

                LogosText {
                    objectName: "appManager.details.footer"
                    Layout.fillWidth: true
                    visible: !d.failed && !d.unresolved && text.length > 0
                    text: d.footer
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textTertiary
                }

                LogosText {
                    objectName: "appManager.details.error"
                    Layout.fillWidth: true
                    visible: d.failed
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.error
                    text: (d.app.errorMessage || "").length > 0
                          ? qsTr("Install failed: %1").arg(d.app.errorMessage)
                          : qsTr("Install failed. Please try again.")
                }
            }
        }

        // ─── What can be done ───
        LogosButtonRow {
            objectName: "appManager.details.actions"
            Layout.fillWidth: true

            leftActions: [
                LogosButton {
                    id: uninstallButton
                    objectName: "appManager.details.uninstall"
                    visible: d.canUninstall
                    text: qsTr("Uninstall")
                    onClicked: root.uninstallRequested(d.name, d.repositoryUrl)
                    contentItem: LogosText {
                        text: uninstallButton.text
                        color: Theme.palette.error
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Item {}
                }
            ]

            rightActions: [
                LogosButton {
                    objectName: "appManager.details.open"
                    visible: d.installed && !d.installing
                    enabled: !d.waiting
                    text: qsTr("Open")
                    variant: actionButton.visible ? LogosButton.Variant.Secondary
                                                  : LogosButton.Variant.Primary
                    onClicked: root.openRequested(d.name)
                },
                LogosButton {
                    id: actionButton
                    objectName: "appManager.details.action"
                    // Nothing to change: Open is the only thing to do. An
                    // installed app installs what its details changed.
                    visible: d.installing || (d.repositoryUrl.length > 0
                                              && (d.action !== Types.RowAction.NoOp || d.pendingChanges))
                    enabled: !d.installing && d.available && !d.unresolved && !d.waiting
                    text: d.installing ? Stages.stageWord(d.stage)
                        : Stages.actionWord(d.action !== Types.RowAction.NoOp ? d.action : Types.RowAction.Install)
                    variant: LogosButton.Variant.Primary
                    onClicked: root.installRequested(d.name, d.repositoryUrl)
                }
            ]
        }
    }
}
