import QtQuick
import QtTest

import Logos.Icons
import Logos.Theme

import "../../src/qml"
import "../../src/qml/Installer/Types.js" as Types
import "Rows.js" as Rows

// An app's details: what it offers to do in each state, its versions, what
// installing it brings, and what it asks for. Installing is Basecamp's to
// approve, so the panel only asks.
TestCase {
    id: testCase
    name: "AppDetailsPanel"
    width: 900
    height: 700
    visible: true
    when: windowShown

    Component { id: pageComp; AppDetailsPanel {} }
    Component { id: markComp; TrustMark {} }
    SignalSpy { id: openSpy; signalName: "openRequested" }
    SignalSpy { id: installSpy; signalName: "installRequested" }
    SignalSpy { id: uninstallSpy; signalName: "uninstallRequested" }
    SignalSpy { id: versionSpy; signalName: "versionPicked" }
    SignalSpy { id: backSpy; signalName: "closeRequested" }
    SignalSpy { id: optionalSpy; signalName: "optionalToggled" }

    function versions() {
        return [{ version: "2.0.0", rootHash: "b", releasedAt: "2026-11-01", size: 2 * 1024 * 1024 },
                { version: "1.0.0", rootHash: "a", releasedAt: "2026-10-01", size: 1024 * 1024 }]
    }

    function makePage(app, images) {
        const page = createTemporaryObject(pageComp, testCase, {
            width: testCase.width, height: testCase.height, app: app,
            sandboxImages: images || null,
        })
        verify(page)
        for (const spy of [openSpy, installSpy, uninstallSpy, versionSpy, backSpy]) {
            spy.target = page
            spy.clear()
        }
        waitForRendering(page)
        return page
    }

    function find(page, name) {
        const item = findChild(page, name)
        verify(item, name)
        return item
    }

    // An icon shows through Basecamp's SandboxImages: its sandbox loads no
    // data: URL, which is what the backend sends.
    function test_the_icon_shows_through_the_sandbox() {
        const dataUrl = "data:image/png;base64,iVBORw0KGgo="
        const images = Qt.createQmlObject(
            'import QtQml; QtObject { function sourceFor(url) {'
            + ' return url === "' + dataUrl + '" ? "image://sandbox-media/0123456789abcdef01234567" : "" } }',
            testCase)
        const page = makePage(Rows.app("wallet_ui", { iconUrl: dataUrl }), images)
        compare(String(find(page, "appManager.details.icon").source),
                "image://sandbox-media/0123456789abcdef01234567")
        images.destroy()
    }

    // An app without an icon has no colour of its own, installed or not.
    function test_an_icon_less_app_has_no_colour_of_its_own() {
        for (const installed of [false, true]) {
            const page = makePage(Rows.app("wallet_ui", { isInstalled: installed }))
            const icon = find(page, "appManager.details.icon")
            verify(Qt.colorEqual(icon.fallbackColor, Theme.palette.background),
                   "installed " + installed + ": " + icon.fallbackColor)
        }
    }

    function test_an_app_not_installed_offers_install() {
        const page = makePage(Rows.app("wallet_ui", {
            displayName: "Wallet", description: "Send and receive.",
            availableVersions: versions(), selectedVersionIndex: 0, version: "2.0.0",
        }))
        compare(find(page, "appManager.details.name").text, "Wallet")
        compare(find(page, "appManager.details.description").text, "Send and receive.")
        const action = find(page, "appManager.details.action")
        verify(action.visible)
        compare(action.text, "Install")
        compare(find(page, "appManager.details.open").visible, false)
        compare(find(page, "appManager.details.uninstall").visible, false)
        compare(find(page, "appManager.details.version").text, "Version 2.0.0")
        compare(find(page, "appManager.details.size").text, "2.0 MB")
        mouseClick(action)
        compare(installSpy.count, 1)
        compare(installSpy.signalArguments[0][0], "wallet_ui")
        compare(installSpy.signalArguments[0][1], Rows.repo)
    }

    function test_an_installed_current_app_opens_and_uninstalls() {
        const page = makePage(Rows.installed("wallet_ui", {
            installedVersion: "2.0.0", availableVersions: versions(), selectedVersionIndex: 0,
        }))
        compare(find(page, "appManager.details.action").visible, false)
        const open = find(page, "appManager.details.open")
        verify(open.visible)
        mouseClick(open)
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "wallet_ui")
        const uninstall = find(page, "appManager.details.uninstall")
        verify(uninstall.visible)
        mouseClick(uninstall)
        compare(uninstallSpy.count, 1)
    }

    // As the Add Application dialog had it.
    function test_the_version_its_date_and_size_are_one_line() {
        const page = makePage(Rows.app("wallet_ui", {
            availableVersions: versions(), selectedVersionIndex: 0, version: "2.0.0",
        }))
        const middle = (item) => item.mapToItem(page, 0, item.height / 2).y
        const version = find(page, "appManager.details.version")
        compare(version.text, "Version 2.0.0")
        for (const name of ["appManager.details.released", "appManager.details.size"]) {
            const item = find(page, name)
            verify(item.text.length > 0, name)
            verify(!item.truncated, name + " fits")
            fuzzyCompare(middle(item), middle(version), 1)
        }
    }

    function test_an_upgrade_is_offered_beside_open() {
        const page = makePage(Rows.installed("wallet_ui", {
            installedVersion: "1.0.0", installStatus: Types.InstallStatus.UpgradeAvailable,
            rowAction: Types.RowAction.Upgrade, availableVersions: versions(), selectedVersionIndex: 0,
            packages: [self({ installedVersion: "1.0.0", rowAction: Types.RowAction.Upgrade })],
        }))
        compare(find(page, "appManager.details.action").text, "Upgrade")
        verify(find(page, "appManager.details.open").visible)
        compare(find(find(page, "appManager.details.package.wallet_ui"), "packageRow.version").text,
                "v1.0.0 → v2.0.0")
    }

    // The app's version is picked on its own row, as the Add Application
    // dialog had it.
    function test_picking_the_apps_version_asks_the_backend() {
        const page = makePage(wallet([self({ installedVersion: "2.0.0", rowAction: Types.RowAction.NoOp })],
                                     { installedVersion: "2.0.0" }))
        const picker = find(find(page, "appManager.details.package.wallet_ui"), "packageRow.versionPicker")
        verify(picker.visible)
        compare(picker.currentText, "2.0.0")
        compare(picker.displayText, "v2.0.0")
        picker.activated(1)
        compare(versionSpy.count, 1)
        compare(versionSpy.signalArguments[0][0], "wallet_ui")
        compare(versionSpy.signalArguments[0][1], Rows.repo)
        compare(versionSpy.signalArguments[0][2], "1.0.0")
    }

    // A picker on every row with a version, one version or many; one on disk
    // that no repository has says what it is at.
    function test_every_package_with_a_version_has_a_picker() {
        const page = makePage(wallet([self({ versions: ["2.0.0"] }),
                                      pkg("signer", { versions: ["1.0.0"] }),
                                      pkg("bundled", { versions: [], installedVersion: "0.9.0",
                                                       version: "", rowAction: Types.RowAction.NoOp }),
                                      pkg("ghost", { found: false, rowAction: Types.RowAction.NotAvailable,
                                                     versions: [], version: "" })]))
        const row = (name) => find(page, "appManager.details.package." + name)
        for (const name of ["wallet_ui", "signer"]) {
            const picker = find(row(name), "packageRow.versionPicker")
            verify(picker.visible, name)
            compare(picker.count, 1)
        }
        compare(find(row("signer"), "packageRow.versionPicker").displayText, "v1.0.0")
        compare(find(row("bundled"), "packageRow.versionPicker").visible, false)
        compare(find(row("bundled"), "packageRow.version").text, "v0.9.0 installed")
        compare(find(row("ghost"), "packageRow.versionPicker").visible, false)
        compare(find(row("ghost"), "packageRow.version").visible, false)
    }

    function test_while_installing_nothing_else_can_be_asked() {
        const page = makePage(Rows.installed("wallet_ui", {
            installedVersion: "1.0.0", rowAction: Types.RowAction.NoOp,
            planInstallStage: Types.InstallStage.Downloading, availableVersions: versions(),
            packages: [self({ installedVersion: "1.0.0", rowAction: Types.RowAction.NoOp })],
        }))
        const action = find(page, "appManager.details.action")
        verify(action.visible)
        compare(action.enabled, false)
        compare(action.text, "Downloading…")
        compare(find(page, "appManager.details.uninstall").visible, false)
        compare(find(page, "appManager.details.open").visible, false)
        compare(find(find(page, "appManager.details.package.wallet_ui"), "packageRow.versionPicker").enabled,
                false)
    }

    // Waiting its turn behind another install, Basecamp not asked yet: the
    // details say Queued, and nothing else can be asked.
    function test_a_request_waiting_its_turn_says_queued() {
        const page = makePage(wallet([self()], { planInstallStage: Types.InstallStage.Queued }))
        const action = find(page, "appManager.details.action")
        compare(action.text, "Queued")
        compare(action.enabled, false)
        compare(find(page, "appManager.details.footer").text, "Queued")
    }

    function test_a_failed_install_says_why_and_offers_retry() {
        const page = makePage(Rows.app("wallet_ui", {
            installStatus: Types.InstallStatus.Failed, rowAction: Types.RowAction.Retry,
            planInstallStage: Types.InstallStage.Failed, errorMessage: "the download stopped",
            availableVersions: versions(),
        }))
        const error = find(page, "appManager.details.error")
        verify(error.visible)
        compare(error.text, "Install failed: the download stopped")
        compare(find(page, "appManager.details.action").text, "Retry")
    }

    function test_nothing_for_this_platform_cannot_be_installed() {
        const page = makePage(Rows.app("mac_ui", {
            rowAction: Types.RowAction.NotAvailable, hasInstallableVersion: false,
            availableVersions: versions(),
        }))
        const action = find(page, "appManager.details.action")
        compare(action.text, "Not available")
        compare(action.enabled, false)
    }

    // Built in, or the shell: nothing the person can remove.
    function test_only_what_the_user_installed_can_be_removed() {
        let page = makePage(Rows.installed("wallet_ui", { installType: "builtin", installedVersion: "2.0.0" }))
        compare(find(page, "appManager.details.uninstall").visible, false)
        page = makePage(Rows.installed("main_ui", { installedVersion: "2.0.0" }))
        compare(find(page, "appManager.details.uninstall").visible, false)
    }

    // From a file: no repository to install from, so nothing but open and remove.
    function test_a_local_app_offers_open_and_uninstall() {
        const page = makePage(Rows.installed("scratch_ui", {
            repositoryUrl: "", sectionKey: "local", installedVersion: "0.1.0",
            rowAction: Types.RowAction.Reinstall,
        }))
        compare(find(page, "appManager.details.action").visible, false)
        verify(find(page, "appManager.details.open").visible)
        verify(find(page, "appManager.details.uninstall").visible)
    }

    function test_its_close_button_closes_it() {
        const page = makePage(Rows.app("wallet_ui"))
        const close = find(page, "appManager.details.close")
        compare(close.Accessible.name, "Close")
        mouseClick(close)
        compare(backSpy.count, 1)
    }

    // ── What installing it brings, as the Add Application dialog showed it ──

    function pkg(name, extra) {
        const p = { name: name, displayName: name, description: "", version: "1.0.0",
                    installedVersion: "", size: 1024 * 1024, rowAction: Types.RowAction.Install,
                    installing: false, optional: false, found: true }
        for (const k in extra) p[k] = extra[k]
        if (!("versions" in p)) p.versions = [p.version]
        return p
    }

    function self(extra) {
        const p = pkg("wallet_ui", { subject: true, displayName: "Wallet", version: "2.0.0",
                                     size: 2 * 1024 * 1024, repositoryUrl: Rows.repo,
                                     versions: ["2.0.0", "1.0.0"], selectedVersionIndex: 0 })
        for (const k in extra) p[k] = extra[k]
        return p
    }

    function wallet(packages, extra) {
        const app = { displayName: "Wallet", availableVersions: versions(), selectedVersionIndex: 0,
                      version: "2.0.0", packages: packages }
        for (const k in extra) app[k] = extra[k]
        return Rows.app("wallet_ui", app)
    }

    function stateOf(page, name) {
        return find(find(page, "appManager.details.package." + name), "packageRow.state").text
    }

    function test_the_app_comes_first_then_what_it_needs_each_with_its_state() {
        const page = makePage(wallet([
            self(),
            pkg("signer", { displayName: "Signer", description: "Signs transactions." }),
            pkg("keys", { installedVersion: "1.0.0", rowAction: Types.RowAction.NoOp }),
            pkg("crypto", { installedVersion: "0.1.0", version: "0.2.0", rowAction: Types.RowAction.Upgrade }),
        ]))
        compare(find(page, "appManager.details.packagesCount").text, "1 / 4")
        compare(stateOf(page, "wallet_ui"), "Install")
        const signer = find(page, "appManager.details.package.signer")
        compare(find(signer, "packageRow.name").text, "Signer")
        compare(find(signer, "packageRow.versionPicker").displayText, "v1.0.0")
        compare(find(signer, "packageRow.version").visible, false)
        compare(find(signer, "packageRow.description").text, "Signs transactions.")
        compare(stateOf(page, "keys"), "Installed")
        compare(find(find(page, "appManager.details.package.keys"), "packageRow.version").text,
                "v1.0.0 installed")
        compare(find(find(page, "appManager.details.package.crypto"), "packageRow.version").text,
                "v0.1.0 → v0.2.0")
        compare(stateOf(page, "crypto"), "Upgrade")
        // Everything that downloads: the app's 2 MB and the two packages that change.
        compare(find(page, "appManager.details.size").text, "4.0 MB")
        compare(find(page, "appManager.details.footer").text,
                "2 out of 3 required package dependencies need updates, please update your "
                + "dependencies to be able to use the Wallet application.")
        compare(find(page, "appManager.details.optional").visible, false)
    }

    // Its one dependency is there already: only the app itself is new.
    function test_only_the_app_installing_says_so() {
        const page = makePage(wallet([self(), pkg("keys", { installedVersion: "1.0.0",
                                                            rowAction: Types.RowAction.NoOp })]))
        compare(find(page, "appManager.details.packagesCount").text, "1 / 2")
        compare(find(page, "appManager.details.footer").text, "Wallet will be installed.")
        compare(find(page, "appManager.details.size").text, "2.0 MB")
    }

    function test_an_upgrade_says_from_what_to_what() {
        const page = makePage(wallet([self({ installedVersion: "1.0.0", rowAction: Types.RowAction.Upgrade })],
                                     { installedVersion: "1.0.0" }))
        compare(find(page, "appManager.details.footer").text, "Wallet will be upgraded from 1.0.0 to 2.0.0.")
    }

    function test_dependencies_that_are_missing_say_so() {
        const page = makePage(wallet([self({ installedVersion: "2.0.0", rowAction: Types.RowAction.NoOp }),
                                      pkg("signer"), pkg("keys")],
                                     { installedVersion: "2.0.0" }))
        compare(find(page, "appManager.details.footer").text,
                "2 out of 2 required package dependencies are missing, please install your "
                + "dependencies to be able to use the Wallet application.")
    }

    function test_a_package_installing_counts_its_bytes() {
        const page = makePage(wallet([self(), pkg("signer", {
            installing: true, installStage: Types.InstallStage.Downloading,
            downloadReceived: 1024 * 1024, downloadTotal: 4 * 1024 * 1024, downloadTransport: "http" })]))
        compare(stateOf(page, "signer"), "1.0 / 4.0 MB")
    }

    // The versions a package it needs offers, and whether an optional one
    // comes: picked here, they go to Basecamp with the install.
    function test_a_package_it_needs_offers_its_versions() {
        const page = makePage(wallet([self({ versions: ["2.0.0", "1.0.0"] }),
                                      pkg("signer", { repositoryUrl: Rows.repo,
                                                      versions: ["1.1.0", "1.0.0"], selectedVersionIndex: 0 })]))
        const row = find(page, "appManager.details.package.signer")
        const picker = find(row, "packageRow.versionPicker")
        verify(picker.visible)
        compare(picker.model, ["1.1.0", "1.0.0"])
        picker.activated(1)
        compare(versionSpy.count, 1)
        compare(versionSpy.signalArguments[0][0], "signer")
        compare(versionSpy.signalArguments[0][1], Rows.repo)
        compare(versionSpy.signalArguments[0][2], "1.0.0")
    }

    function test_an_optional_package_can_be_left_out() {
        const page = makePage(wallet([self(), pkg("extra", { optional: true, selected: true })]))
        const box = find(find(page, "appManager.details.package.extra"), "packageRow.optional")
        verify(box.visible)
        verify(box.checked)
        optionalSpy.target = page
        optionalSpy.clear()
        mouseClick(box)
        compare(optionalSpy.count, 1)
        compare(optionalSpy.signalArguments[0][0], "extra")
        compare(optionalSpy.signalArguments[0][1], false)
    }

    // As the Add Application dialog had it: one on disk that no repository
    // has stays, ticked; there is nothing to choose.
    function test_an_optional_package_only_on_disk_is_kept() {
        const page = makePage(wallet([self(), pkg("bundled", {
            optional: true, selected: true, installedOnly: true, installedVersion: "0.9.0", version: "",
            versions: [], rowAction: Types.RowAction.NoOp })]))
        const box = find(find(page, "appManager.details.package.bundled"), "packageRow.optional")
        verify(box.visible)
        verify(box.checked)
        compare(box.enabled, false)
    }

    function test_nothing_is_picked_while_it_installs() {
        const page = makePage(wallet([self(), pkg("signer", { versions: ["1.1.0", "1.0.0"] }),
                                      pkg("extra", { optional: true, selected: true })],
                                     { planInstallStage: Types.InstallStage.Downloading }))
        compare(find(find(page, "appManager.details.package.signer"), "packageRow.versionPicker").enabled, false)
        compare(find(find(page, "appManager.details.package.extra"), "packageRow.optional").enabled, false)
    }

    function test_optional_packages_are_listed_apart() {
        const page = makePage(wallet([self(), pkg("delivery"), pkg("rln", { optional: true })]))
        verify(find(page, "appManager.details.optional").visible)
        compare(find(page, "appManager.details.packagesCount").text, "0 / 2")
        verify(find(page, "appManager.details.package.rln"))
    }

    // As the Add Application dialog had it: under the optional package it
    // comes with, without a box of its own.
    function test_what_comes_with_an_optional_package_sits_under_it() {
        const page = makePage(wallet([self(), pkg("delivery"),
                                      pkg("rln", { optional: true, selected: true, offeredBy: "delivery" }),
                                      pkg("zk", { optional: true, requiredFor: "rln" })]))
        const row = (name) => find(page, "appManager.details.package." + name)
        const nameX = (name) => { const n = find(row(name), "packageRow.name"); return n.mapToItem(page, 0, 0).x }
        verify(find(row("rln"), "packageRow.optional").visible)
        // Nothing to tick: its box only keeps the place.
        compare(find(row("zk"), "packageRow.optional").opacity, 0)
        verify(find(row("zk"), "packageRow.versionPicker").visible)
        compare(nameX("zk"), nameX("rln"))
        verify(nameX("zk") > nameX("delivery"))
        verify(row("zk").mapToItem(page, 0, 0).y > row("rln").mapToItem(page, 0, 0).y)
        compare(find(page, "appManager.details.packagesCount").text, "0 / 2")
    }

    // Basecamp would refuse the plan: as the old dialog did, nothing starts.
    function test_a_package_at_a_version_that_conflicts_blocks_the_install() {
        const page = makePage(wallet([self(), pkg("signer", { conflict: true })]))
        compare(stateOf(page, "signer"), "Conflict")
        verify(find(page, "appManager.details.resolutionBanner").visible)
        compare(find(page, "appManager.details.footer").visible, false)
        const action = find(page, "appManager.details.action")
        verify(action.visible)
        compare(action.enabled, false)
    }

    // "1 package", "2 packages": not "package(s)".
    function test_what_is_installing_is_counted_in_words() {
        const installing = { planInstallStage: Types.InstallStage.Downloading }
        let page = makePage(wallet([self({ installing: true }), pkg("signer")], installing))
        compare(find(page, "appManager.details.footer").text, "Downloading… 1 package…")
        page = makePage(wallet([self({ installing: true }), pkg("signer", { installing: true })], installing))
        compare(find(page, "appManager.details.footer").text, "Downloading… 2 packages…")

        const busy = { installedVersion: "1.0.0", rowAction: Types.RowAction.NoOp, installing: true }
        page = makePage(Rows.installed("wallet_ui", {
            displayName: "Wallet", installedVersion: "2.0.0", availableVersions: versions(), selectedVersionIndex: 0,
            packages: [self({ installedVersion: "2.0.0", rowAction: Types.RowAction.NoOp }),
                       pkg("signer", busy), pkg("keys", busy)] }))
        compare(find(page, "appManager.details.footer").text,
                "2 of Wallet's required packages are currently being installed. "
                + "Wait for the active install to finish before opening Wallet.")
    }

    // The footer says to wait; so does every button.
    function test_while_another_install_brings_a_package_it_needs_nothing_starts() {
        const busy = pkg("signer", { installedVersion: "1.0.0", rowAction: Types.RowAction.NoOp, installing: true,
                                     installStage: Types.InstallStage.Downloading })
        let page = makePage(Rows.installed("wallet_ui", {
            displayName: "Wallet", installedVersion: "2.0.0", availableVersions: versions(), selectedVersionIndex: 0,
            packages: [self({ installedVersion: "2.0.0", rowAction: Types.RowAction.NoOp }), busy] }))
        const open = find(page, "appManager.details.open")
        verify(open.visible)
        compare(open.enabled, false)
        compare(find(page, "appManager.details.footer").text,
                "1 of Wallet's required packages is currently being installed. "
                + "Wait for the active install to finish before opening Wallet.")
        page = makePage(wallet([self(), busy]))
        compare(find(page, "appManager.details.action").enabled, false)
    }

    // As the old dialog had it: ticking one turns Open into Install too.
    function test_an_installed_app_installs_the_optional_packages_ticked() {
        const installedWallet = (selected) => Rows.installed("wallet_ui", {
            installedVersion: "2.0.0", availableVersions: versions(), selectedVersionIndex: 0,
            packages: [self({ installedVersion: "2.0.0", rowAction: Types.RowAction.NoOp }),
                       pkg("extra", { optional: true, offeredBy: "wallet_ui", selected: selected })] })
        let page = makePage(installedWallet(false))
        compare(find(page, "appManager.details.action").visible, false)
        page = makePage(installedWallet(true))
        const action = find(page, "appManager.details.action")
        verify(action.visible)
        verify(action.enabled)
        compare(action.text, "Install")
        verify(find(page, "appManager.details.open").visible)
        mouseClick(action)
        compare(installSpy.count, 1)
    }

    // A version picked for a package it needs is a change too, and only a
    // pick is: it used to change that package's row, with nothing to apply it.
    function test_an_installed_app_installs_a_version_picked_for_a_package_it_needs() {
        const installedWallet = (signer) => Rows.installed("wallet_ui", {
            installedVersion: "2.0.0", availableVersions: versions(), selectedVersionIndex: 0,
            packages: [self({ installedVersion: "2.0.0", rowAction: Types.RowAction.NoOp }),
                       pkg("signer", Object.assign({ installedVersion: "2.0.0", versions: ["2.0.0", "1.0.0"] },
                                                   signer))] })
        let page = makePage(installedWallet({ version: "2.0.0", rowAction: Types.RowAction.NoOp }))
        compare(find(page, "appManager.details.action").visible, false)
        page = makePage(installedWallet({ version: "2.1.0", rowAction: Types.RowAction.Upgrade }))
        compare(find(page, "appManager.details.action").visible, false)
        page = makePage(installedWallet({ version: "1.0.0", rowAction: Types.RowAction.Downgrade, picked: true }))
        const action = find(page, "appManager.details.action")
        verify(action.visible)
        verify(action.enabled)
        compare(action.text, "Install")
        mouseClick(action)
        compare(installSpy.count, 1)
    }

    // A package that comes with an optional one lines up with the others:
    // the whole row sat further right than the rest.
    function test_a_package_that_comes_with_an_optional_lines_up() {
        const page = makePage(wallet([self(),
            pkg("rln", { optional: true, selected: true, offeredBy: "delivery", repositoryUrl: Rows.repo }),
            pkg("lez_rln", { optional: true, requiredFor: ["rln"], repositoryUrl: Rows.repo })]))
        const xOf = (row, part) =>
            find(find(page, "appManager.details.package." + row), part).mapToItem(page, 0, 0).x
        for (const part of ["packageRow.name", "packageRow.versionPicker"])
            fuzzyCompare(xOf("lez_rln", part), xOf("rln", part), 0.5)
        compare(find(find(page, "appManager.details.package.lez_rln"), "packageRow.optional").enabled, false)
    }

    // As the old dialog had it: what the download source can't serve isn't
    // offered.
    function test_only_versions_this_host_can_fetch_are_offered() {
        const page = makePage(wallet([self(), pkg("signer", {
            repositoryUrl: Rows.repo, versions: ["1.1.0", "1.0.0", "0.9.0"],
            versionsServed: [false, true, true], selectedVersionIndex: 1, version: "1.0.0" })]))
        const picker = find(find(page, "appManager.details.package.signer"), "packageRow.versionPicker")
        compare(picker.model, ["1.0.0", "0.9.0"])
        compare(picker.currentIndex, 0)
        picker.activated(1)
        compare(versionSpy.signalArguments[0][2], "0.9.0")
    }

    function test_with_nothing_this_host_can_fetch_the_version_is_said() {
        const page = makePage(wallet([self(), pkg("signer", { versionsServed: [false],
                                                              rowAction: Types.RowAction.NotAvailable })]))
        const row = find(page, "appManager.details.package.signer")
        compare(find(row, "packageRow.versionPicker").visible, false)
        compare(find(row, "packageRow.version").text, "v1.0.0")
    }

    function test_where_the_bytes_come_from_is_said() {
        const page = makePage(wallet([self(), pkg("signer", {
            installing: true, installStage: Types.InstallStage.Downloading, downloadReceived: 1,
            downloadTotal: 4, downloadTransport: "http", downloadFellBack: true })]))
        compare(find(find(page, "appManager.details.package.signer"), "packageRow.transport").text,
                "via GitHub · Logos Storage didn't have it")
    }

    function test_a_package_no_repository_has_is_said() {
        const page = makePage(wallet([self(), pkg("ghost", { found: false,
                                                             rowAction: Types.RowAction.NotAvailable })]))
        compare(stateOf(page, "ghost"), "Not available")
        verify(find(page, "appManager.details.resolutionBanner").visible)
        compare(find(page, "appManager.details.footer").visible, false)
    }

    function test_an_installed_app_with_nothing_to_change_says_nothing() {
        const page = makePage(Rows.installed("wallet_ui", {
            availableVersions: versions(), selectedVersionIndex: 0, version: "2.0.0",
            installedVersion: "2.0.0", hash: "b", installedHash: "b",
            packages: [self({ installedVersion: "2.0.0", rowAction: Types.RowAction.NoOp }),
                       pkg("keys", { installedVersion: "1.0.0", rowAction: Types.RowAction.NoOp })],
        }))
        compare(find(page, "appManager.details.footer").visible, false)
        compare(find(page, "appManager.details.packagesCount").text, "2 / 2")
    }

    // ── Who signed it, as Basecamp's install dialog says it ──

    // Under its name, centred: the dialog's mark and words.
    function test_who_signed_the_app_is_said_under_its_name() {
        let page = makePage(wallet([self()], { trust: { status: "trusted", publisher: "Logos" } }))
        let line = find(page, "appManager.details.trust")
        verify(line.visible)
        const words = find(line, "trust.lineWords")
        compare(words.text, "Signed by Logos")
        const icon = find(line, "trust.markIcon")
        compare(String(icon.source), String(LogosIcons.check))
        const name = find(page, "appManager.details.name")
        const left = icon.mapToItem(page, 0, 0).x
        const right = words.mapToItem(page, 0, 0).x + words.contentWidth
        fuzzyCompare((left + right) / 2, name.mapToItem(page, name.width / 2, 0).x, 1)
        verify(line.mapToItem(page, 0, 0).y >= name.mapToItem(page, 0, name.height).y)

        page = makePage(wallet([self()], { trust: { status: "untrusted", publisher: "Acme" } }))
        line = find(page, "appManager.details.trust")
        compare(find(line, "trust.lineWords").text, "Signed by a publisher you don't trust yet")
        compare(String(find(line, "trust.markIcon").source), String(LogosIcons.warning))

        // Until it is judged, nothing is said.
        page = makePage(wallet([self()]))
        compare(find(page, "appManager.details.trust").visible, false)
    }

    // On a phone a publisher's name as long as one is shown wraps, inside
    // the panel.
    function test_who_signed_it_wraps_inside_a_phone_wide_panel() {
        const page = makePage(wallet([self()], {
            trust: { status: "trusted", publisher: "Northern Lights Cryptography Research Cooperative of Helsinki Oy" } }))
        page.width = 360
        waitForRendering(page)
        const line = find(page, "appManager.details.trust")
        const words = find(line, "trust.lineWords")
        verify(words.lineCount > 1, "lines " + words.lineCount)
        verify(words.contentWidth <= words.width + 0.5, words.contentWidth + " in " + words.width)
        const left = line.mapToItem(page, 0, 0).x
        verify(left >= 0, "left " + left)
        verify(left + line.width <= page.width, "right " + (left + line.width))
    }

    // Each package it brings, marked as the dialog marks it, right after
    // its name.
    function test_each_package_it_brings_is_marked_with_who_signed_it() {
        const page = makePage(wallet([
            self({ trust: { status: "trusted", publisher: "Logos" } }),
            pkg("signer", { displayName: "Signer", trust: { status: "untrusted", publisher: "Acme" } }),
            pkg("keys", { installedVersion: "1.0.0", rowAction: Types.RowAction.NoOp,
                          trust: { status: "unsigned", installed: true } }),
            pkg("crypto"),
        ]))
        const row = (name) => find(page, "appManager.details.package." + name)
        const mark = (name) => find(row(name), "packageRow.trust")
        compare(mark("wallet_ui").description, "Signed by Logos")
        compare(mark("signer").description, "Signed by a publisher you don't trust yet")
        compare(mark("keys").description, "Already installed, not signed")
        verify(mark("signer").visible)
        compare(mark("crypto").visible, false)
        // Where its name's text ends, not its box.
        const name = find(row("signer"), "packageRow.name")
        fuzzyCompare(mark("signer").mapToItem(page, 0, 0).x,
                     name.mapToItem(page, name.contentWidth, 0).x + Theme.spacing.small, 1)
    }

    // Its words on hover, or a tap where nothing hovers.
    function test_a_mark_says_its_words_on_hover_or_a_tap() {
        const mark = createTemporaryObject(markComp, testCase, { x: 40, y: 40, verdict: { status: "unsigned" } })
        waitForRendering(mark)
        const tip = find(mark, "trust.markTip")
        compare(tip.text, "Not signed: nobody vouches for it")
        compare(tip.visible, false)
        mouseMove(mark, mark.width / 2, mark.height / 2)
        tryCompare(tip, "visible", true)
        mouseMove(testCase, 400, 400)
        tryCompare(tip, "visible", false)
        mouseClick(mark, mark.width / 2, mark.height / 2)
        mouseMove(testCase, 400, 400)
        // Past a closing tip's fade: it stays.
        wait(500)
        verify(tip.visible)
    }
}
