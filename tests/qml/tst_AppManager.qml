import QtQuick
import QtTest

import "../../src/qml"
import "Rows.js" as Rows

// The App Manager as the host loads it: what it asks the shell, and the
// details page.
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
        property var requests: []
        // How the shell answers each request.
        property var result: ({ ok: true })
        function module(name) { return name === "app_manager_ui" ? testCase.backend : null }
        function model(name, property, prefetch) {
            return name === "app_manager_ui" && property === "apps" ? testCase.appsModel : null
        }
        function request(intent, params, callback) {
            requests = requests.concat([{ intent: intent, params: params }])
            callback(result)
        }
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
        logos.result = { ok: true }
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

    // The shell couldn't open the app: say so; a cancel was the person's own.
    function test_an_app_the_shell_couldnt_open_says_so() {
        const app = makeApp()
        const toast = find(app, "appManager.toast")
        logos.result = { ok: false, error: "cancelled" }
        mouseClick(find(app, "appManager.app.chat_ui"))
        compare(toast.visible, false, "a cancel needs no message")
        logos.result = { ok: false, error: "unavailable" }
        mouseClick(find(app, "appManager.app.chat_ui"))
        tryVerify(() => toast.visible)
        compare(toast.title, "Couldn't open chat_ui")
        compare(toast.message, "Nothing in Basecamp can do that right now.")
    }

    function test_repository_settings_the_shell_couldnt_open_say_so() {
        const app = makeApp()
        const toast = find(app, "appManager.toast")
        logos.result = { ok: false, error: "timeout" }
        mouseClick(find(app, "appManager.repositoriesButton"))
        tryVerify(() => toast.visible)
        compare(toast.title, "Couldn't open the repository settings")
    }

    // A reload that failed keeps the list and says so, each time; a first
    // load's failure is the page's to say.
    function test_a_reload_that_failed_says_so() {
        const app = makeApp()
        const toast = find(app, "appManager.toast")
        backend.loaded = false
        backend.loadFailed("the catalog")
        compare(toast.visible, false)
        backend.loaded = true
        backend.loadFailed("the catalog")
        tryVerify(() => toast.visible)
        compare(toast.title, "Couldn't reload the apps")
        compare(toast.message, "Couldn't read the catalog. The list is the one from before.")
    }
}
