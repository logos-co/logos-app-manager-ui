import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Controls
import Logos.Layouts
import Logos.Theme

import "Installer/Availability.js" as Availability
import "Installer/Downloads.js" as Downloads

// The App Manager's page: the apps of every repository, a section each, the
// ones installed from a file last; categories beside them; search, the
// install-state tabs and a grid or a list; an app's details beside the apps.
Rectangle {
    id: root
    // For UI tests: `loading` says when the catalog is in.
    objectName: "appManager.view"

    // ─── Public API ───
    // The backend (its replica) and its `apps` model.
    property var backend: null
    property var apps: null

    // Navigation the shell does: open an app, show Settings → Repositories.
    signal openRequested(string name)
    signal repositoriesRequested()

    // Applies a query from outside the view, into the field, so the field
    // and the backend stay in step.
    function applySearch(query) { header.openSearch(query) }

    readonly property bool loading: !!backend && backend.loading === true
    // The open app's details (the backend's `details`), and whether one is open.
    readonly property var details: backend && backend.details ? backend.details : ({})
    readonly property bool detailsOpen: (details.name || "").length > 0
    onDetailsOpenChanged: detailsPanel.panelOpen = detailsOpen

    QtObject {
        id: d

        property string viewMode: "grid"
        property string category: "All"
        property bool showUnavailable: false
        readonly property int installState: panelHeader.installStateIndex
        readonly property string searchText: header.searchText

        readonly property var categories:
            root.backend && root.backend.categories && root.backend.categories.length > 0
                ? root.backend.categories : ["All"]
        readonly property int categoryIndex: Math.max(0, categories.indexOf(category))
        // A category the catalog no longer has is no filter.
        onCategoriesChanged: if (categories.indexOf(category) < 0) category = "All"

        readonly property int repositoryCount: root.backend ? root.backend.repositoryCount || 0 : 0
        readonly property int visibleCount: root.backend ? root.backend.visibleCount || 0 : 0
        readonly property int localCount: root.backend ? root.backend.localCount || 0 : 0
        readonly property string hostVariant: root.backend ? root.backend.hostVariant || "" : ""
        // The catalog's first read failed: nothing is known, not "none".
        readonly property bool loadFailed: !!root.backend && root.backend.loaded !== true
                                           && !!root.backend.loadError && !root.loading

        // The filters live in the backend, which narrows `apps`.
        function push() {
            const b = root.backend
            if (!b) return
            if (b.searchText !== searchText) b.pushSearchText(searchText)
            if (b.category !== category) b.pushCategory(category)
            if (b.installState !== installState) b.pushInstallState(installState)
            if (b.showUnavailable !== showUnavailable) b.pushShowUnavailable(showUnavailable)
        }
        onSearchTextChanged: push()
        onCategoryChanged: push()
        onInstallStateChanged: push()
        onShowUnavailableChanged: push()

        // A current app opens; any other shows its details, what installing,
        // upgrading or reinstalling it brings, as the Add Application dialog did.
        function activate(name, repositoryUrl, current) {
            if (current) root.openRequested(name)
            else if (root.backend) root.backend.showDetails(name, repositoryUrl)
        }

        // Left for another section or app: the details close, their picks
        // with them, and the search empties.
        function leave() {
            detailsPanel.panelOpen = false
            header.searchItem.text = ""
            header.closeSearch()
        }
    }

    // Shown, or hidden behind another section or app.
    readonly property bool shown: Window.visibility !== Window.Hidden
    onShownChanged: if (!shown) d.leave()

    onBackendChanged: d.push()
    Component.onCompleted: {
        d.push()
        detailsPanel.panelOpen = root.detailsOpen
    }

    // Another app's apps.search, in the field as if typed.
    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onSearchRequested(query) { header.openSearch(query) }
    }

    color: Theme.palette.background

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pageMargin(root.width)
        spacing: Theme.spacing.xlarge

        // ─── Title and subtitle, the search on their right; on a phone a 🔍
        // at the end of the title's line ───
        LogosPageHeader {
            id: header
            objectName: "appManager.header"
            // On a phone the details are the page, under this header: a ‹
            // before the title closes them.
            canGoBack: detailsPanel.showingPanel
            onBackRequested: detailsPanel.panelOpen = false
            Layout.fillWidth: true
            title: qsTr("Applications")
            subtitle: qsTr("Install and manage applications.")
            // On a phone it would only say the title again.
            subtitleOnPhone: false
            // Nothing to search over the details on a phone.
            searchEnabled: !detailsPanel.showingPanel
            searchPlaceholder: qsTr("Search apps…")
            searchShortcutHint: searchShortcut.nativeText
            searchWidth: 605
            searchItem.objectName: "appManager.searchField"
        }

        // ⌘K focuses + selects the search.
        Shortcut {
            id: searchShortcut
            objectName: "appManager.searchShortcut"
            sequence: "Ctrl+K"
            context: Qt.WindowShortcut
            enabled: root.visible
            onActivated: header.openSearch()
        }

        // The App Manager does not show where each download comes from, so
        // Logos Storage being down while GitHub covers for it is not news here.
        LogosNotice {
            id: downloadNotice
            objectName: "appManager.downloadNotice"
            readonly property var notice: root.backend
                ? Downloads.downloadNotice(root.backend.online !== false,
                                           root.backend.downloadSource || "",
                                           root.backend.storageState || "", false)
                : null
            Layout.fillWidth: true
            shown: notice !== null
            severity: !notice ? LogosNotice.Info
                    : notice.severity === "error" ? LogosNotice.Error
                    : notice.severity === "warning" ? LogosNotice.Warning
                    : LogosNotice.Info
            title: notice ? notice.title : ""
            message: notice ? notice.message : ""
        }

        LogosSidebarLayout {
            id: body
            objectName: "appManager.body"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacing.medium

            side: LogosListView {
                id: categoriesList

                model: d.categories
                currentIndex: d.categoryIndex

                header: LogosText {
                    width: categoriesList.width
                    topPadding: Theme.spacing.tiny
                    bottomPadding: Theme.spacing.tiny
                    text: qsTr("Categories")
                    font.pixelSize: Theme.typography.subtitleText
                    font.weight: Theme.typography.weightRegular
                    color: Theme.palette.text
                }

                delegate: LogosItemDelegate {
                    id: cell
                    objectName: "appManager.category." + modelData
                    width: ListView.view.width
                    text: modelData
                    highlighted: ListView.isCurrentItem
                    radius: Theme.spacing.radiusLarge
                    highlightColor: Theme.palette.backgroundButton
                    hoverColor: "transparent"
                    textColor: (cell.highlighted || cell.hovered)
                                   ? Theme.palette.text
                                   : Theme.palette.textTertiary
                    onClicked: d.category = modelData
                }
            }

            // An app's details, a card beside the apps as Package Manager
            // shows a package's, closed by its ✕; on a phone the page, under
            // the side panel's "‹ Applications", the one way back.
            LogosSidePanel {
                id: detailsPanel
                objectName: "appManager.detailsPanel"
                anchors.fill: parent
                // Wide enough for the version, its date and size on one line.
                panelWidth: 400
                spacing: Theme.spacing.medium
                divider: false
                // The way back is the page header's: no bar of its own.
                backInHost: true
                onPanelOpenChanged: if (!panelOpen && root.detailsOpen && root.backend)
                                        root.backend.closeDetails()

                panel: AppDetailsPanel {
                    showHeader: !detailsPanel.showingPanel
                    app: root.details
                    onCloseRequested: detailsPanel.panelOpen = false
                    onOpenRequested: (name) => root.openRequested(name)
                    onInstallRequested: (name, repositoryUrl) => root.backend.install(name, repositoryUrl)
                    onUninstallRequested: (name, repositoryUrl) => root.backend.uninstall(name, repositoryUrl)
                    onVersionPicked: (name, repositoryUrl, version) =>
                        root.backend.selectVersion(name, repositoryUrl, version)
                    onOptionalToggled: (name, selected) => root.backend.setOptional(name, selected)
                }

                // ─── Apps panel ───
                content: Rectangle {
                    color: Theme.palette.surfaceRaised
                    radius: Theme.spacing.radiusXlarge
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: Theme.spacing.medium
                        anchors.bottomMargin: Theme.spacing.medium
                        spacing: Theme.spacing.medium

                        AppManagerPanelHeader {
                            id: panelHeader
                            objectName: "appManager.panelHeader"
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.spacing.medium
                            Layout.rightMargin: Theme.spacing.medium

                            loading: root.loading
                            viewMode: d.viewMode
                            showUnavailable: d.showUnavailable
                            showCategoryPicker: !body.sideShown
                            categories: d.categories
                            categoryIndex: d.categoryIndex
                            onCategorySelected: (index) => d.category = d.categories[index] || "All"
                            onReloadClicked: if (root.backend) root.backend.refresh()
                            onRepositoriesClicked: root.repositoriesRequested()
                            onViewModeChangeRequested: (mode) => d.viewMode = mode
                            onShowUnavailableRequested: (show) => d.showUnavailable = show
                        }

                        LogosStateView {
                            objectName: "appManager.loadErrorView"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: d.loadFailed
                            title: qsTr("Couldn't load the apps")
                            message: d.loadFailed ? qsTr("Couldn't read %1.").arg(root.backend.loadError) : ""
                            rightActions: [
                                LogosButton {
                                    objectName: "appManager.loadErrorView.retry"
                                    text: qsTr("Try again")
                                    onClicked: if (root.backend) root.backend.refresh()
                                }
                            ]
                        }

                        // No repository, and nothing installed from a file to
                        // show instead.
                        LogosStateView {
                            objectName: "appManager.noReposView"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: d.repositoryCount === 0 && d.localCount === 0 && !root.loading
                                     && !d.loadFailed
                            title: qsTr("No repositories configured")
                            message: qsTr("Add a package repository to browse and install apps.")
                            rightActions: [
                                LogosButton {
                                    objectName: "appManager.noReposView.manage"
                                    text: qsTr("Manage Repositories")
                                    onClicked: root.repositoriesRequested()
                                }
                            ]
                        }

                        Flickable {
                            id: gridScroll
                            objectName: "appManager.scroll"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: d.repositoryCount > 0 || d.localCount > 0 || root.loading
                            clip: true
                            contentWidth: width
                            contentHeight: listColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            ScrollBar.vertical: LogosScrollBar {
                                policy: ScrollBar.AsNeeded
                                rightPadding: 4
                            }

                            ColumnLayout {
                                id: listColumn
                                x: Theme.spacing.medium
                                width: gridScroll.width - 2 * Theme.spacing.medium
                                spacing: 0

                                AppTiles {
                                    id: tiles
                                    objectName: "appManager.list"
                                    Layout.fillWidth: true
                                    model: root.apps
                                    viewMode: d.viewMode
                                    onAppClicked: (name, repositoryUrl, current) =>
                                        d.activate(name, repositoryUrl, current)
                                    onOpenRequested: (name) => root.openRequested(name)
                                    onDetailsRequested: (name, repositoryUrl) =>
                                        root.backend.showDetails(name, repositoryUrl)
                                    onInstallRequested: (name, repositoryUrl) =>
                                        root.backend.install(name, repositoryUrl)
                                    onUninstallRequested: (name, repositoryUrl) =>
                                        root.backend.uninstall(name, repositoryUrl)
                                }

                                // Every section hides itself when the search
                                // matches nothing: say so instead of a blank panel.
                                LogosStateView {
                                    objectName: "appManager.emptyView"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: gridScroll.height
                                    visible: d.searchText.length > 0 && d.visibleCount === 0
                                             && !!root.backend
                                    title: qsTr("No apps match your search.")
                                    message: qsTr("Try a different search term.")
                                }

                                // A category or install state that leaves nothing.
                                LogosStateView {
                                    objectName: "appManager.noMatchView"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: gridScroll.height
                                    visible: d.searchText.length === 0 && d.visibleCount === 0
                                             && (d.categoryIndex !== 0 || d.installState !== 0)
                                             && !root.loading && !!root.backend
                                    title: qsTr("No apps match these filters.")
                                    rightActions: [
                                        LogosButton {
                                            objectName: "appManager.noMatchView.clear"
                                            text: qsTr("Clear filters")
                                            onClicked: {
                                                d.category = "All"
                                                panelHeader.installStateIndex = 0
                                            }
                                        }
                                    ]
                                }

                                LogosStateView {
                                    objectName: "appManager.noneForPlatformView"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: gridScroll.height
                                    // Only with no filter that could explain it.
                                    visible: d.searchText.length === 0
                                             && d.categoryIndex === 0
                                             && d.installState === 0
                                             && !d.showUnavailable
                                             && !root.loading
                                             && d.repositoryCount > 0
                                             && d.visibleCount === 0
                                             && !!root.backend

                                    readonly property var words: Availability.nothingForThisPlatform(
                                        d.hostVariant.startsWith("unknown") ? "" : d.hostVariant)
                                    title: words.title
                                    message: words.subtitle
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // While the catalog loads.
    Control {
        objectName: "appManager.loadingOverlay"
        anchors.fill: parent
        visible: root.loading
        z: 1
        padding: 0
        background: Rectangle { color: Theme.colors.getColor(Theme.palette.background, 0.65) }
        contentItem: Item {
            LogosSpinner {
                anchors.centerIn: parent
                implicitWidth: 36
                implicitHeight: 36
                running: parent.visible
            }
        }
        MouseArea { anchors.fill: parent }
    }
}
