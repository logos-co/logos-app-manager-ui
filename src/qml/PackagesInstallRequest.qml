import QtQuick

// Provider side of packages.install: another app asks for an app by name;
// the backend shows it, from the first repository that has it, and the
// person's own click on Install is what asks Basecamp. Answered once it is
// shown: the intent is a hand-off, so the person stays here to decide.
QtObject {
    id: root

    property var backend: null
    property int timeoutMs: 8000

    function begin(requestId, name) {
        // Every request gets an answer, a displaced one too.
        finish(false, "cancelled")
        d.requestId = requestId
        d.name = name
        deadline.restart()
        attempt()
    }

    // Again once the catalog is in: the app may have just started.
    function attempt() {
        if (d.requestId === "" || d.asking || !root.backend || root.backend.loading === true) return
        d.asking = true
        const id = d.requestId
        logos.watch(root.backend.showByName(d.name), function (taken) {
            d.asking = false
            if (taken === true && d.requestId === id) finish(true, "")
        }, function () {
            d.asking = false
        })
    }

    function finish(ok, error) {
        const id = d.requestId
        if (id === "") return
        d.requestId = ""
        d.name = ""
        deadline.stop()
        logos.respond(id, ok, ({}), error)
    }

    property QtObject d: QtObject {
        id: d
        // "" = nothing waiting.
        property string requestId: ""
        property string name: ""
        property bool asking: false
    }

    property Timer deadline: Timer {
        interval: root.timeoutMs
        onTriggered: root.finish(false, "failed")
    }

    property Connections backendSignals: Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onLoadingChanged() { root.attempt() }
        function onVisibleCountChanged() { root.attempt() }
    }
}
