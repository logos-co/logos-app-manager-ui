import QtQuick
import QtTest

import "../../src/qml"
import "Rows.js" as Rows

// The App Manager as the host loads it: what it asks the shell, the details
// page, and the provider side of packages.install.
TestCase {
    id: testCase
    name: "AppManager"
    width: 1280
    height: 800
    visible: true
    when: windowShown

    // The host: `logos` hands the view its backend and model, here fakes.
    property var backend: null
    property var appsModel: null
    property var logos: QtObject {
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        property var requests: []
        property var responses: []
        function module(name) { return name === "app_manager_ui" ? testCase.backend : null }
        function model(name, property, prefetch) {
            return name === "app_manager_ui" && property === "apps" ? testCase.appsModel : null
        }
        function request(intent, params, callback) {
            requests = requests.concat([{ intent: intent, params: params }])
            callback({ ok: true })
        }
        function respond(id, ok, data, error) {
            responses = responses.concat([{ id: id, ok: ok, error: error }])
        }
        // A fake backend answers at once, with a value, not a pending call.
        function watch(value, onSuccess, onError) { onSuccess(value) }
    }

    Component { id: fakeComp; FakeBackend {} }
    Component { id: modelComp; ListModel {} }
    Component { id: appComp; AppManager {} }

    function init() {
        failOnWarning(/Binding loop/)
        backend = fakeComp.createObject(testCase)
        appsModel = modelComp.createObject(testCase)
        Rows.fill(appsModel, [Rows.section(Rows.repo, "Logos", 2),
                              Rows.app("wallet_ui"), Rows.installed("chat_ui")])
        backend.visibleCount = 2
        logos.requests = []
        logos.responses = []
    }

    function cleanup() {
        backend.destroy()
        backend = null
        appsModel.destroy()
        appsModel = null
    }

    function makeApp() {
        const app = createTemporaryObject(appComp, testCase, { width: testCase.width, height: testCase.height })
        verify(app)
        waitForRendering(app)
        return app
    }

    function find(item, name) {
        const found = findChild(item, name)
        verify(found, name)
        return found
    }

    function test_an_installed_app_is_opened_by_the_shell() {
        const app = makeApp()
        mouseClick(find(app, "appManager.app.chat_ui"))
        compare(logos.requests.length, 1)
        compare(logos.requests[0].intent, "basecamp.apps.launch")
        compare(logos.requests[0].params.app, "chat_ui")
    }

    function test_manage_repositories_asks_the_shell() {
        const app = makeApp()
        mouseClick(find(app, "appManager.repositoriesButton"))
        compare(logos.requests.length, 1)
        compare(logos.requests[0].intent, "basecamp.repositories.manage")
    }

    function test_details_open_beside_the_apps() {
        const app = makeApp()
        const view = find(app, "appManager.view")
        const panel = find(app, "appManager.detailsPanel")
        compare(panel.panelOpen, false)

        backend.details = Rows.app("wallet_ui", { displayName: "Wallet" })
        verify(panel.panelOpen)
        waitForRendering(app)
        verify(view.visible)
        compare(find(app, "appManager.details.name").text, "Wallet")

        mouseClick(find(app, "appManager.details.action"))
        compare(backend.called("install"), ["install wallet_ui " + Rows.repo])

        mouseClick(find(app, "appManager.details.close"))
        compare(backend.called("closeDetails").length, 1)
    }

    function test_a_failure_says_why() {
        const app = makeApp()
        const toast = find(app, "appManager.toast")
        backend.finished("wallet_ui", 1, "cancelled")
        compare(toast.visible, false, "a cancel needs no message")
        backend.finished("wallet_ui", 2, "the download stopped")
        tryVerify(() => toast.visible)
        compare(toast.message, "the download stopped")
    }

    // ── packages.install ─────────────────────────────────────────────────────

    // Another app's request shows the app; the person's own click on
    // Install is what asks Basecamp.
    function test_packages_install_shows_the_app_and_answers() {
        makeApp()
        logos.intentRequested("r1", "packages.install", { name: "wallet_ui" }, "chat_ui")
        compare(backend.called("showByName"), ["showByName wallet_ui"])
        compare(backend.called("install").length, 0)
        compare(logos.responses.length, 1)
        compare(logos.responses[0].id, "r1")
        compare(logos.responses[0].ok, true)
    }

    function test_packages_install_waits_for_the_catalog() {
        backend.loading = true
        makeApp()
        logos.intentRequested("r1", "packages.install", { name: "wallet_ui" }, "chat_ui")
        compare(logos.responses.length, 0)
        backend.loading = false
        compare(backend.called("showByName").length, 1)
        compare(logos.responses.length, 1)
        compare(logos.responses[0].ok, true)
    }

    function test_packages_install_of_nothing_known_fails_in_time() {
        backend.hasByName = false
        const app = makeApp()
        find(app, "appManager.installRequest").timeoutMs = 200
        logos.intentRequested("r1", "packages.install", { name: "nothing_ui" }, "chat_ui")
        compare(logos.responses.length, 0)
        tryVerify(() => logos.responses.length === 1, 2000)
        compare(logos.responses[0].ok, false)
        compare(logos.responses[0].error, "failed")
    }

    function test_a_second_request_displaces_the_first() {
        backend.loading = true
        makeApp()
        logos.intentRequested("r1", "packages.install", { name: "wallet_ui" }, "chat_ui")
        logos.intentRequested("r2", "packages.install", { name: "chat_ui" }, "chat_ui")
        compare(logos.responses.length, 1)
        compare(logos.responses[0].id, "r1")
        compare(logos.responses[0].error, "cancelled")
    }

    function test_apps_search_searches_the_page() {
        const app = makeApp()
        backend.details = Rows.app("wallet_ui")
        logos.intentRequested("r1", "apps.search", { query: "wal" }, "main_ui")
        compare(backend.called("closeDetails").length, 1)
        compare(find(app, "appManager.searchField").text, "wal")
        compare(logos.responses.length, 1)
        compare(logos.responses[0].ok, true)
    }

    function test_an_intent_it_does_not_provide_is_refused() {
        makeApp()
        logos.intentRequested("r1", "packages.show", { name: "wallet_ui" }, "chat_ui")
        compare(logos.responses.length, 1)
        compare(logos.responses[0].ok, false)
        compare(backend.called("showByName").length, 0)
    }
}
