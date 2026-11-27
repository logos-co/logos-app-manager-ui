import QtQuick
import QtTest

import Logos.Theme

import "../../src/qml"
import "../../src/qml/Installer/Types.js" as Types
import "Rows.js" as Rows

// The App Manager's page on a stand-in backend: the filters it pushes, what a
// tile and its menu ask for, and its empty states.
TestCase {
    id: testCase
    name: "AppManagerView"
    width: 1280
    height: 800
    // Input can't reach anything in an invisible TestCase, the default.
    visible: true
    when: windowShown

    property var backend: null

    Component { id: fakeComp; FakeBackend {} }
    Component { id: modelComp; ListModel {} }
    Component { id: viewComp; AppManagerView {} }
    SignalSpy { id: openSpy; signalName: "openRequested" }
    SignalSpy { id: reposSpy; signalName: "repositoriesRequested" }

    function init() {
        failOnWarning(/Binding loop/)
        backend = fakeComp.createObject(testCase)
    }

    function cleanup() {
        // A test that hid the window and failed before showing it again.
        if (!testCase.Window.window.visible) testCase.Window.window.show()
        backend.destroy()
        backend = null
    }

    function makeView(rows) {
        const model = createTemporaryObject(modelComp, testCase)
        Rows.fill(model, rows || [])
        let apps = 0
        for (const r of rows || []) if (r.kind === "app") ++apps
        backend.visibleCount = apps
        const view = createTemporaryObject(viewComp, testCase, {
            width: testCase.width, height: testCase.height, backend: backend, apps: model,
        })
        verify(view)
        openSpy.target = view
        openSpy.clear()
        reposSpy.target = view
        reposSpy.clear()
        waitForRendering(view)
        return view
    }

    function find(view, name) {
        const item = findChild(view, name)
        verify(item, name)
        return item
    }

    function twoSections() {
        return [Rows.section(Rows.repo, "Logos", 2),
                Rows.app("wallet_ui", { displayName: "Wallet" }),
                Rows.installed("chat_ui", { displayName: "Chat" }),
                Rows.section("local", "local", 1),
                Rows.installed("scratch_ui", { sectionKey: "local", repositoryUrl: "" })]
    }

    // ── The list ─────────────────────────────────────────────────────────────

    function test_sections_and_their_apps_are_shown() {
        const view = makeView(twoSections())
        find(view, "appManager.section." + Rows.repo)
        find(view, "appManager.section.local")
        find(view, "appManager.app.wallet_ui")
        find(view, "appManager.app.scratch_ui")
        compare(find(view, "appManager.noReposView").visible, false)
        compare(find(view, "appManager.emptyView").visible, false)
        compare(find(view, "appManager.noneForPlatformView").visible, false)
    }

    // ── The filters live in the backend ──────────────────────────────────────

    function test_the_filters_are_pushed_to_the_backend() {
        const view = makeView(twoSections())
        view.applySearch("wal")
        tryCompare(backend, "searchText", "wal")

        mouseClick(find(view, "appManager.category.Chat"))
        compare(backend.category, "Chat")

        find(view, "appManager.stateTabs").currentIndex = 1
        compare(backend.installState, 1)

        find(view, "appManager.panelHeader").showUnavailableRequested(true)
        compare(backend.showUnavailable, true)

        mouseClick(find(view, "appManager.reloadButton"))
        compare(backend.called("refresh").length, 1)
    }

    // Another app's apps.search lands in the field, and so in the backend.
    function test_a_search_asked_for_is_typed_in() {
        const view = makeView(twoSections())
        backend.searchRequested("chat")
        compare(find(view, "appManager.searchField").text, "chat")
        tryCompare(backend, "searchText", "chat")
    }

    function test_a_category_the_catalog_lost_is_no_filter() {
        const view = makeView(twoSections())
        mouseClick(find(view, "appManager.category.Wallet"))
        compare(backend.category, "Wallet")
        backend.categories = ["All", "Chat"]
        compare(backend.category, "All")
    }

    // ── What a tile asks for ─────────────────────────────────────────────────

    // As the Add Application dialog did: what installing it brings, first.
    function test_clicking_an_app_not_installed_shows_its_details() {
        const view = makeView(twoSections())
        mouseClick(find(view, "appManager.app.wallet_ui"))
        compare(backend.called("details"), ["details wallet_ui " + Rows.repo])
        compare(backend.called("install").length, 0)
        compare(openSpy.count, 0)
    }

    function test_details_open_beside_the_apps_and_close() {
        const view = makeView(twoSections())
        const panel = find(view, "appManager.detailsPanel")
        compare(panel.panelOpen, false)
        backend.details = Rows.app("wallet_ui", { displayName: "Wallet" })
        verify(panel.panelOpen)
        waitForRendering(view)
        verify(panel.beside, "beside the apps on a desktop")
        verify(find(view, "appManager.list").visible, "the apps stay")
        compare(find(view, "appManager.details.name").text, "Wallet")
        mouseClick(find(view, "appManager.details.action"))
        compare(backend.called("install"), ["install wallet_ui " + Rows.repo])
        mouseClick(find(view, "appManager.details.close"))
        compare(backend.called("closeDetails").length, 1)
        compare(panel.panelOpen, false)
    }

    // Beside the apps on a desktop, the details have room for a long version,
    // its date and size on one line, as the Add Application dialog had them,
    // and for a long package name beside its state.
    function test_the_details_beside_the_apps_fit_a_long_version_on_one_line() {
        const view = makeView(twoSections())
        backend.details = Rows.app("wallet_ui", {
            displayName: "Wallet", version: "0.3.0-features", selectedVersionIndex: 0,
            availableVersions: [{ version: "0.3.0-features", releasedAt: "2026-11-25T15:07:03Z",
                                  size: 145434415 }],
            packages: [{ name: "wallet_ui", subject: true, displayName: "Wallet", found: true,
                         version: "0.3.0-features", versions: ["0.3.0-features"],
                         rowAction: Types.RowAction.Install },
                       { name: "liblogos_lez_rln_module", displayName: "liblogos_lez_rln_module",
                         found: true, version: "0.10.0", installedVersion: "0.12.0",
                         versions: ["0.12.0", "0.10.0"], selectedVersionIndex: 1,
                         rowAction: Types.RowAction.Downgrade }],
        })
        waitForRendering(view)
        verify(find(view, "appManager.detailsPanel").beside)
        const middle = (item) => item.mapToItem(view, 0, item.height / 2).y
        const version = find(view, "appManager.details.version")
        compare(version.text, "Version 0.3.0-features")
        for (const name of ["appManager.details.released", "appManager.details.size"]) {
            const item = find(view, name)
            verify(item.text.length > 0, name)
            verify(!item.truncated, name + " fits")
            fuzzyCompare(middle(item), middle(version), 1)
        }
        const row = find(view, "appManager.details.package.liblogos_lez_rln_module")
        verify(!find(row, "packageRow.name").truncated, "the package's name fits beside its state")
        verify(!find(row, "packageRow.version").truncated, "from what to what fits beside its picker")
    }

    // Left for another section or app, it starts afresh: the details closed,
    // their picks forgotten, the search empty. Hiding stands in for leaving:
    // Basecamp hides the view of a section it leaves.
    function test_leaving_closes_the_details_and_clears_the_search() {
        const view = makeView(twoSections())
        backend.details = Rows.app("wallet_ui", { displayName: "Wallet" })
        const panel = find(view, "appManager.detailsPanel")
        verify(panel.panelOpen)
        view.applySearch("wal")
        compare(backend.searchText, "wal")
        const win = view.Window.window
        win.hide()
        tryVerify(() => !view.shown)
        compare(backend.called("closeDetails").length, 1)
        compare(panel.panelOpen, false)
        compare(backend.searchText, "")
        compare(find(view, "appManager.searchField").text, "")
        win.show()
        tryVerify(() => view.shown)
        waitForRendering(view)
        compare(panel.panelOpen, false)
    }

    // On a phone the details are the page, under the page's own header: a ‹
    // before the title, which moves right for it but never up or down; no
    // bar of the side panel's, nor its hairline, and the details where the
    // apps were.
    function test_on_a_phone_the_page_header_is_the_way_back() {
        const model = createTemporaryObject(modelComp, testCase)
        Rows.fill(model, twoSections())
        const view = createTemporaryObject(viewComp, testCase, {
            width: 390, height: testCase.height, backend: backend, apps: model,
        })
        waitForRendering(view)
        const header = find(view, "appManager.header")
        const at = (item) => { const p = item.mapToItem(view, 0, 0); return [p.x, p.y] }
        const title = at(header.titleItem)
        const height = header.height
        view.applySearch("wal")
        backend.details = Rows.app("wallet_ui", { displayName: "Wallet" })
        waitForRendering(view)
        const panel = find(view, "appManager.detailsPanel")
        verify(panel.showingPanel)
        compare(panel.headerItem.visible, false, "no bar of the side panel's own")
        compare(at(header.titleItem)[1], title[1], "not up or down")
        verify(at(header.titleItem)[0] > title[0], "after the ‹")
        compare(header.titleItem.text, "Applications")
        compare(header.height, height)
        compare(header.searchItem.visible, false)
        verify(header.backIconItem.visible)
        verify(at(header.backIconItem)[0] < at(header.titleItem)[0], "before the title")
        compare(header.searchItem.text, "wal", "the query kept for the list")
        fuzzyCompare(panel.panelPaneItem.mapToItem(view, 0, 0).y,
                     panel.contentPaneItem.mapToItem(view, 0, 0).y, 0.5, "where the apps were")
        mouseClick(header.backButtonItem)
        compare(panel.panelOpen, false)
        compare(backend.called("closeDetails").length, 1)
        verify(header.searchItem.visible)
        compare(backend.searchText, "wal", "the list searched again")
        compare(header.backIconItem.visible, false)
        waitForRendering(view)
        compare(at(header.titleItem), title)
    }

    // Its tile says Reinstall: a click shows that, as the Add Application
    // dialog did, rather than opening the app as it is.
    function test_clicking_an_installed_app_with_a_change_pending_shows_its_details() {
        const view = makeView([Rows.section(Rows.repo, "Logos", 1),
                               Rows.installed("storage_ui", {
                                   installStatus: Types.InstallStatus.DifferentHash,
                                   rowAction: Types.RowAction.Reinstall })])
        const tile = find(view, "appManager.app.storage_ui")
        mouseClick(tile)
        compare(backend.called("details"), ["details storage_ui " + Rows.repo])
        compare(openSpy.count, 0)

        // Its menu's Open still opens it as it is.
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        const menu = menuOf(tile)
        tryVerify(() => menu.opened)
        menuItem(menu, "appContextMenu.open").triggered()
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "storage_ui")
    }

    function test_clicking_an_installed_app_opens_it() {
        const view = makeView(twoSections())
        mouseClick(find(view, "appManager.app.chat_ui"))
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "chat_ui")
        compare(backend.called("install").length, 0)
    }

    function menuOf(tile) {
        for (let i = 0; i < tile.data.length; ++i)
            if (typeof tile.data[i].openFor === "function") return tile.data[i]
        return null
    }

    function menuItem(menu, name) {
        for (let i = 0; i < menu.count; ++i)
            if (menu.itemAt(i).objectName === name) return menu.itemAt(i)
        return null
    }

    function test_the_menu_shows_details_and_uninstalls() {
        const view = makeView(twoSections())
        const tile = find(view, "appManager.app.chat_ui")
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        const menu = menuOf(tile)
        tryVerify(() => menu.opened)
        menuItem(menu, "appContextMenu.details").triggered()
        compare(backend.called("details"), ["details chat_ui " + Rows.repo])

        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        tryVerify(() => menu.opened)
        menuItem(menu, "appContextMenu.uninstall").triggered()
        compare(backend.called("uninstall"), ["uninstall chat_ui " + Rows.repo])
    }

    function test_an_app_not_installed_has_details_and_install() {
        const view = makeView(twoSections())
        const tile = find(view, "appManager.app.wallet_ui")
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        const menu = menuOf(tile)
        tryVerify(() => menu.opened)
        verify(menuItem(menu, "appContextMenu.details").visible, "details before it is installed")
        compare(menuItem(menu, "appContextMenu.open").visible, false)
        menuItem(menu, "appContextMenu.install").triggered()
        compare(backend.called("install"), ["install wallet_ui " + Rows.repo])
    }

    // The menu offers what the backend does: no Install with nothing for this
    // platform, nor while an install of it runs.
    function test_the_menu_offers_no_install_the_backend_would_refuse() {
        const view = makeView([Rows.section(Rows.repo, "Logos", 2),
                               Rows.app("mac_ui", { hasInstallableVersion: false,
                                                    rowAction: Types.RowAction.NotAvailable }),
                               Rows.app("wallet_ui", { installStatus: Types.InstallStatus.Installing,
                                                       planInstallStage: Types.InstallStage.Downloading,
                                                       rowAction: Types.RowAction.NoOp })])
        for (const name of ["mac_ui", "wallet_ui"]) {
            const tile = find(view, "appManager.app." + name)
            mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
            const menu = menuOf(tile)
            tryVerify(() => menu.opened)
            compare(menuItem(menu, "appContextMenu.install").visible, false, name)
            verify(menuItem(menu, "appContextMenu.details").visible, name)
            menu.close()
            tryVerify(() => !menu.visible)
        }
    }

    // Downloaded is still the install: Uninstall waits it out, as the
    // backend does.
    function test_uninstall_waits_out_a_downloaded_install() {
        const view = makeView([Rows.section(Rows.repo, "Logos", 1),
                               Rows.installed("chat_ui", { planInstallStage: Types.InstallStage.Downloaded })])
        const tile = find(view, "appManager.app.chat_ui")
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        const menu = menuOf(tile)
        tryVerify(() => menu.opened)
        const uninstall = menuItem(menu, "appContextMenu.uninstall")
        verify(uninstall.visible)
        compare(uninstall.enabled, false)
    }

    // On disk but missing a package it needs, it isn't installed: Install
    // brings what it lacks, and it can still be removed.
    function test_an_app_missing_a_package_offers_install_and_uninstall() {
        const view = makeView([Rows.section(Rows.repo, "Logos", 1),
                               Rows.app("wallet_ui", { installType: "user", installedVersion: "1.0.0" })])
        const tile = find(view, "appManager.app.wallet_ui")
        mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
        const menu = menuOf(tile)
        tryVerify(() => menu.opened)
        compare(menuItem(menu, "appContextMenu.open").visible, false)
        verify(menuItem(menu, "appContextMenu.install").visible)
        const uninstall = menuItem(menu, "appContextMenu.uninstall")
        verify(uninstall.visible)
        verify(uninstall.enabled)
        uninstall.triggered()
        compare(backend.called("uninstall"), ["uninstall wallet_ui " + Rows.repo])
    }

    // A list row's trash follows the menu's rule, and says what it removes.
    function test_a_list_rows_uninstall_follows_the_menu() {
        const view = makeView([Rows.section(Rows.repo, "Logos", 2),
                               Rows.installed("chat_ui", { displayName: "Chat" }),
                               Rows.app("wallet_ui", { displayName: "Wallet", installType: "user",
                                                       installedVersion: "1.0.0" })])
        find(view, "appManager.panelHeader").viewModeChangeRequested("list")
        waitForRendering(view)
        const chat = findChild(find(view, "appManager.app.chat_ui"), "appListDelegate.uninstall")
        verify(chat.visible)
        compare(chat.Accessible.name, "Uninstall Chat")
        verify(findChild(find(view, "appManager.app.wallet_ui"), "appListDelegate.uninstall").visible)
    }

    // ── Empty states ─────────────────────────────────────────────────────────

    function test_no_repositories_offers_to_add_one() {
        backend.repositoryCount = 0
        backend.appCount = 0
        const view = makeView([])
        const empty = find(view, "appManager.noReposView")
        verify(empty.visible)
        mouseClick(find(view, "appManager.noReposView.manage"))
        compare(reposSpy.count, 1)
    }

    function test_apps_installed_from_a_file_show_with_no_repository() {
        backend.repositoryCount = 0
        const view = makeView([Rows.section("local", "local", 1),
                               Rows.installed("scratch_ui", { sectionKey: "local", repositoryUrl: "" })])
        compare(find(view, "appManager.noReposView").visible, false)
        find(view, "appManager.app.scratch_ui")
    }

    function test_a_search_that_matches_nothing_says_so() {
        const view = makeView([])
        view.applySearch("zzz")
        tryVerify(() => find(view, "appManager.emptyView").visible)
        compare(find(view, "appManager.noneForPlatformView").visible, false)
    }

    function test_nothing_for_this_platform_names_it() {
        backend.availableCount = 0
        const view = makeView([])
        const none = find(view, "appManager.noneForPlatformView")
        verify(none.visible)
        verify(none.message.indexOf("linux-x86_64") >= 0, none.message)
    }

    // Not "nothing for this platform" when it is the Installed tab that is
    // empty: the filters are, and they can be cleared.
    function test_an_empty_install_state_tab_is_not_the_platform() {
        const view = makeView([])
        find(view, "appManager.stateTabs").currentIndex = 1
        compare(find(view, "appManager.noneForPlatformView").visible, false)
        verify(find(view, "appManager.noMatchView").visible)
        mouseClick(find(view, "appManager.noMatchView.clear"))
        compare(find(view, "appManager.stateTabs").currentIndex, 0)
        compare(backend.installState, 0)
    }

    function test_a_category_with_nothing_offers_to_clear_it() {
        const view = makeView([])
        mouseClick(find(view, "appManager.category.Wallet"))
        compare(backend.category, "Wallet")
        verify(find(view, "appManager.noMatchView").visible)
        compare(find(view, "appManager.noneForPlatformView").visible, false)
        mouseClick(find(view, "appManager.noMatchView.clear"))
        compare(backend.category, "All")
    }

    // A first load that failed knows nothing: not "no repositories".
    function test_a_first_load_that_failed_says_so_and_retries() {
        backend.repositoryCount = 0
        backend.appCount = 0
        backend.loaded = false
        backend.loadError = "the catalog"
        const view = makeView([])
        const failed = find(view, "appManager.loadErrorView")
        verify(failed.visible)
        compare(failed.message, "Couldn't read the catalog.")
        compare(find(view, "appManager.noReposView").visible, false)
        mouseClick(find(view, "appManager.loadErrorView.retry"))
        compare(backend.called("refresh").length, 1)
        backend.loaded = true
        backend.loadError = ""
        compare(failed.visible, false)
        verify(find(view, "appManager.noReposView").visible)
    }

    // "Nothing available for this platform" was all the page said with every
    // repository turned off, or none answering.
    function test_every_repository_turned_off_says_so() {
        backend.repositoryCount = 2
        backend.enabledRepositoryCount = 0
        backend.appCount = 0
        const view = makeView([])
        verify(find(view, "appManager.repositoriesOffView").visible)
        compare(find(view, "appManager.noneForPlatformView").visible, false)
        mouseClick(find(view, "appManager.repositoriesOffView.manage"))
        compare(reposSpy.count, 1)
    }

    function test_a_repository_out_of_reach_says_so_and_retries() {
        backend.unreachableRepositories = ["Logos"]
        backend.appCount = 0
        const view = makeView([])
        const unreachable = find(view, "appManager.unreachableView")
        verify(unreachable.visible)
        compare(unreachable.message, "Couldn't read Logos. Check your connection, then try again.")
        compare(find(view, "appManager.noneForPlatformView").visible, false)
        mouseClick(find(view, "appManager.unreachableView.retry"))
        compare(backend.called("refresh").length, 1)
    }

    function test_repositories_with_no_apps_say_so() {
        backend.appCount = 0
        const view = makeView([])
        verify(find(view, "appManager.noAppsView").visible)
        compare(find(view, "appManager.noneForPlatformView").visible, false)
    }

    // Showing the apps this platform can't run, with no app at all, left the
    // panel blank.
    function test_showing_unavailable_apps_with_none_says_so() {
        backend.appCount = 0
        const view = makeView([])
        find(view, "appManager.panelHeader").showUnavailableRequested(true)
        compare(backend.showUnavailable, true)
        verify(find(view, "appManager.noAppsView").visible)
    }

    // With no repository, the apps from a file are searched: a search that
    // misses says so, not "no repositories".
    function test_a_search_over_apps_from_a_file_that_misses_says_so() {
        backend.repositoryCount = 0
        const view = makeView([])
        view.applySearch("zzz")
        tryVerify(() => find(view, "appManager.emptyView").visible)
        compare(find(view, "appManager.noReposView").visible, false)
    }

    // Until the catalog is read, nothing is said of what it lacks.
    function test_nothing_is_said_before_the_catalog_is_read() {
        backend.loaded = false
        backend.repositoryCount = 0
        backend.appCount = 0
        const view = makeView([])
        for (const name of ["appManager.noReposView", "appManager.repositoriesOffView",
                            "appManager.unreachableView", "appManager.noAppsView",
                            "appManager.loadErrorView"])
            compare(find(view, name).visible, false, name)
        backend.loaded = true
        verify(find(view, "appManager.noReposView").visible)
    }

    // ── Notices ──────────────────────────────────────────────────────────────

    function test_downloads_that_cannot_work_say_so() {
        const view = makeView(twoSections())
        const notice = find(view, "appManager.downloadNotice")
        compare(notice.shown, false)
        backend.downloadSource = "logos"
        backend.storageState = "failed"
        compare(notice.shown, true)
        compare(notice.title, "Logos Storage isn't running")
        // Offline is not the storage's fault.
        backend.online = false
        compare(notice.shown, false)
    }

    function test_loading_covers_the_page() {
        const view = makeView(twoSections())
        const overlay = find(view, "appManager.loadingOverlay")
        compare(overlay.visible, false)
        backend.loading = true
        compare(overlay.visible, true)
    }
}
