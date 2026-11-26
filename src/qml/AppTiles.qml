import QtQuick

import Logos.Theme

import "Installer/Types.js" as Types

// The apps, section by section: each section's row spans the width, so its
// apps start a line of their own under it, as tiles in a grid or as list
// rows. The rows are the backend's `apps` (a section's row, then its apps).
Flow {
    id: root

    // ─── Public API ───
    property var model: null
    property string viewMode: "grid"
    // `current`: installed, and nothing it brings needs a change.
    signal appClicked(string name, string repositoryUrl, bool current)
    signal openRequested(string name)
    signal detailsRequested(string name, string repositoryUrl)
    signal installRequested(string name, string repositoryUrl)
    signal uninstallRequested(string name, string repositoryUrl)

    QtObject {
        id: d

        // A cell is the design system's tile for the width; the columns share
        // what is left over.
        readonly property bool isList: root.viewMode === "list"
        readonly property int gridMinCellWidth: Theme.tileWidth(root.width)
        readonly property int gridColumns: Math.max(1, Math.floor(root.width / gridMinCellWidth))
        readonly property int gridCellWidth: root.width > 0 ? Math.floor(root.width / gridColumns)
                                                            : gridMinCellWidth
        readonly property int gridCellHeight: 162
        readonly property int listRowHeight: 64
    }

    Repeater {
        model: root.model

        delegate: Loader {
            id: cell
            readonly property var row: model
            readonly property bool isSection: row.kind === "section"
            width: cell.isSection || d.isList ? root.width : d.gridCellWidth
            height: cell.isSection ? (cell.item ? cell.item.implicitHeight : 1)
                  : d.isList ? d.listRowHeight : d.gridCellHeight
            sourceComponent: cell.isSection ? sectionRow : d.isList ? listTile : gridTile

            Component {
                id: sectionRow
                AppSectionHeader {
                    objectName: "appManager.section." + (cell.row.sectionKey || "")
                    title: cell.row.sectionTitle || ""
                    count: cell.row.sectionCount || 0
                    first: index === 0
                }
            }

            Component {
                id: gridTile
                AppGridDelegate {
                    objectName: "appManager.app." + cell.row.name
                    appData: cell.row
                    onAppClicked: (name, repositoryUrl) =>
                        root.appClicked(name, repositoryUrl,
                                       cell.row.installStatus === Types.InstallStatus.Installed)
                    onOpenRequested: (name) => root.openRequested(name)
                    onDetailsRequested: (name, repositoryUrl) => root.detailsRequested(name, repositoryUrl)
                    onInstallRequested: (name, repositoryUrl) => root.installRequested(name, repositoryUrl)
                    onUninstallRequested: (name, repositoryUrl) => root.uninstallRequested(name, repositoryUrl)
                }
            }

            Component {
                id: listTile
                AppListDelegate {
                    objectName: "appManager.app." + cell.row.name
                    appData: cell.row
                    onAppClicked: (name, repositoryUrl) =>
                        root.appClicked(name, repositoryUrl,
                                       cell.row.installStatus === Types.InstallStatus.Installed)
                    onOpenRequested: (name) => root.openRequested(name)
                    onDetailsRequested: (name, repositoryUrl) => root.detailsRequested(name, repositoryUrl)
                    onInstallRequested: (name, repositoryUrl) => root.installRequested(name, repositoryUrl)
                    onUninstallRequested: (name, repositoryUrl) => root.uninstallRequested(name, repositoryUrl)
                }
            }
        }
    }
}
