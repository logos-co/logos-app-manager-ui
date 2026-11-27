import QtQuick

import Logos.Controls
import Logos.Theme

// The App Manager: the apps page, an app's details beside it. The backend
// reads the catalog and makes every change, each approved by Basecamp first;
// this view asks it, and asks the shell to open an app or Settings →
// Repositories.
Rectangle {
    id: root
    objectName: "appManager"

    readonly property string moduleName: "app_manager_ui"
    property var backend: logos.module(moduleName)
    // prefetch: the replica caches the roles before it reports rows, so a
    // tile never renders empty.
    property var apps: logos.model(moduleName, "apps", true)

    // The welcome page's search, handed over with the result that led here.
    function applySearch(query) { view.applySearch(query) }

    color: Theme.palette.background

    QtObject {
        id: d

        function request(intent, params) {
            if (typeof logos === "undefined" || typeof logos.request !== "function") {
                console.warn("App Manager: no logos.request on this host:", intent)
                return
            }
            logos.request(intent, params, function (result) {
                if (!result || !result.ok)
                    console.warn("App Manager:", intent, "failed:", result ? result.error : "no result")
            })
        }

        function open(name) { request("basecamp.apps.launch", { app: name }) }
    }

    AppManagerView {
        id: view
        anchors.fill: parent
        backend: root.backend
        apps: root.apps
        onOpenRequested: (name) => d.open(name)
        onRepositoriesRequested: d.request("basecamp.repositories.manage", {})
    }

    // Why a change failed; the tile says that it did.
    LogosToast {
        id: toast
        objectName: "appManager.toast"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.large
        width: Math.min(parent.width - 2 * Theme.spacing.large, 480)
        severity: LogosNotice.Error
        duration: 8000
    }

    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        // outcome: 0 done, 1 cancelled, 2 failed.
        function onFinished(name, outcome, error) {
            if (outcome === 2)
                toast.show(qsTr("Something went wrong with %1").arg(name), error)
        }
        // A reload that failed keeps the list it had; the first load's
        // failure is the page's to say.
        function onLoadFailed(error) {
            if (root.backend.loaded)
                toast.show(qsTr("Couldn't reload the apps"),
                           qsTr("Couldn't read %1. The list is the one from before.").arg(error))
        }
    }
}
