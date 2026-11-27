.pragma library
.import "Installer/Types.js" as Types

// What can be done with an app's row, as the backend allows it
// (AppManager::install() and uninstall()): the tiles, their menu, the list
// rows and the details ask here, so none offers what it would refuse.

// An install of the app is under way, its downloads included.
function busy(stage) {
    return stage === Types.InstallStage.Queued || stage === Types.InstallStage.Downloading
        || stage === Types.InstallStage.Downloaded || stage === Types.InstallStage.Installing
}

// On disk, put there by the person, and not the shell.
function canUninstall(row) {
    return !!row && row.installType === "user" && row.name !== "main_ui"
}

// Its row offers to install it, from a repository: not with nothing for this
// platform, nor while an install of it runs.
function offersInstall(row) {
    return !!row && (row.repositoryUrl || "").length > 0
        && (row.rowAction === Types.RowAction.Install || row.rowAction === Types.RowAction.Retry)
}
