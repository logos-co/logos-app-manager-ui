.pragma library
.import "../../src/qml/Installer/Types.js" as Types

// Rows as the backend's `apps` model has them: a section's, then its apps'.

var repo = "https://example.test/logos-repo.json"

function app(name, extra) {
    var r = {
        kind: "app",
        sectionKey: repo,
        sectionTitle: "",
        sectionCount: 0,
        name: name,
        displayName: name,
        description: "",
        iconUrl: "",
        repositoryUrl: repo,
        installType: "",
        isInstalled: false,
        installStatus: Types.InstallStatus.NotInstalled,
        planInstallStage: Types.InstallStage.None,
        planDownloadReceived: 0,
        planDownloadTotal: 0,
        planDownloadTransport: "",
        planDownloadFellBack: false,
        hasInstallableVersion: true,
        supportsFullBleedIcon: false,
        rowAction: Types.RowAction.Install
    }
    for (var k in extra) r[k] = extra[k]
    return r
}

function installed(name, extra) {
    var r = app(name, {
        installType: "user",
        isInstalled: true,
        installStatus: Types.InstallStatus.Installed,
        rowAction: Types.RowAction.NoOp
    })
    for (var k in extra) r[k] = extra[k]
    return r
}

function section(key, title, count) {
    return app("", { kind: "section", sectionKey: key, sectionTitle: title, sectionCount: count })
}

// A model of `rows`, to hand a view as the backend's `apps`.
function fill(model, rows) {
    model.clear()
    for (var i = 0; i < rows.length; ++i) model.append(rows[i])
}
