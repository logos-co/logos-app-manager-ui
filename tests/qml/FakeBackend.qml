import QtQuick

// Stands in for app_manager_ui's backend in the view tests: its properties
// and slots, the calls the views make, recorded, and the filters echoed back
// as the backend does.
QtObject {
    id: fake

    signal finished(string name, int outcome, string error)
    signal searchRequested(string query)

    property bool loading: false
    property bool online: true
    property string downloadSource: "any"
    property string storageState: "running"
    property string hostVariant: "linux-x86_64"
    property int repositoryCount: 1
    property var categories: ["All", "Chat", "Wallet"]
    property int visibleCount: 0
    property int localCount: 0
    property string searchText: ""
    property string category: "All"
    property int installState: 0
    property bool showUnavailable: false
    property var details: ({})

    property var calls: []
    // What showByName answers.
    property bool hasByName: true

    function record(call) { calls = calls.concat([call]) }
    function called(prefix) { return calls.filter(c => c.indexOf(prefix) === 0) }

    function pushSearchText(text) { record("search " + text); searchText = text }
    function pushCategory(c) { record("category " + c); category = c }
    function pushInstallState(state) { record("installState " + state); installState = state }
    function pushShowUnavailable(show) { record("showUnavailable " + show); showUnavailable = show }
    function refresh() { record("refresh") }
    function install(name, repositoryUrl) { record("install " + name + " " + repositoryUrl); return true }
    function uninstall(name, repositoryUrl) { record("uninstall " + name + " " + repositoryUrl); return true }
    function showByName(name) { record("showByName " + name); return hasByName }
    function showDetails(name, repositoryUrl) { record("details " + name + " " + repositoryUrl) }
    function closeDetails() { record("closeDetails"); details = ({}) }
    function selectVersion(name, repositoryUrl, index) { record("selectVersion " + name + " " + index) }
    function setOptional(name, selected) { record("optional " + name + " " + selected) }
}
