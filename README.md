# logos-app-manager-ui

App Manager, the Logos app for finding, installing, upgrading and removing
apps. It ships with Basecamp, which shows it in its Applications section.

It lists the apps (`ui_qml` packages) of every repository Basecamp knows, a
section each, with the apps installed from a file last; filters them by
category, install state and search. An installed app's tile opens it; any
other shows its details beside the list, as Package Manager shows a package:
what it is, the download, what can be done with it, and, as Basecamp's Add
Application dialog had them, the packages installing it brings, the app
first, each with its state and a picker for its version, then the optional
packages any of them offers, ticked to come, each with what it brings under
it.

## How it installs

The view never installs anything, and never sees an approval.

1. The view asks the backend: "install wallet_ui", "uninstall notes_ui".
2. The backend asks Basecamp itself, through `intents_module`:
   `basecamp.packages.confirm_install`, `_upgrade` or `_uninstall`, with the
   versions and optional packages picked in the details.
3. Basecamp shows its dialog. If the person agrees, the answer, with the
   approved plan, goes back to the backend that asked, and to nothing else.
4. The backend does what the plan says and nothing more: it downloads each
   approved release, checks every file is the release approved, signed as
   approved, installs them in order, and checks each on disk.

The view gets back only how it ended (`finished`), and the tiles show each
download and install as it happens.

All of this is [basecamp-installer-common](https://github.com/logos-co/basecamp-installer-common)'s,
the library App Manager shares with Package Manager and Basecamp: the package
rows and their rules, the filters, the catalog client and the install
pipeline, and the JavaScript for their words.

## Layout

| | |
|---|---|
| `src/qml/` | The view. `AppManager.qml` is the entry: the apps page (`AppManagerView`), an app's details beside it (`AppDetailsPanel`), and what the shell couldn't do, in a toast |
| `src/qml/Installer/` | The library's JavaScript, a copy: `scripts/sync-installer-common.sh` refreshes it, and the `shared-installer-words` check keeps it the pinned revision |
| `src/app_manager_ui.rep` | What the view reads and asks of the backend |
| `src/AppManagerBackend.*` | The backend, run as the core module `app_manager_ui_backend`: hands `AppManager` the package modules and Basecamp's consent, forwards the modules' events, mirrors its state into the `.rep` |
| `src/AppManager.*` | Everything the page shows and does, on the library; no module calls of its own |
| `src/AppSections.*` | The `apps` model: a row per section, then its apps |
| `src/ModuleCalls.*` | `package_manager` and `package_downloader`, through the generated wrappers |

A sandboxed view can't make filters of its own, and gets the backend's models
once, at start. So the sections are rows of one model, and the view lays them
out in a `Flow`: a section's row spans the width, so its apps start a line of
their own under it.

## Intents

| | |
|---|---|
| Asks Basecamp | `basecamp.packages.confirm_install`, `_upgrade`, `_uninstall` (from the backend); `basecamp.apps.launch` to open an app, `basecamp.repositories.manage` (from the view) |
| Provides | Delivered to the backend through `intents_module`. `apps.install`: an app is asked for by name, and optionally `repositoryUrl`, the repository it was picked from. App Manager shows it from that repository when it lists it as an app, else from the first enabled repository that does. For Basecamp's own request (the person's click there, e.g. the Welcome page) it also installs it, Basecamp's approval first; for another app's, the person's own click on Install is what asks Basecamp. It answers once the app is shown, not when an install is done. `apps.search`: the page searches for the query. `packages.install` is Package Manager's |

## Build and test

```bash
nix build                                           # the module
nix build .#checks.aarch64-linux.unit-tests         # the backend's logic, on fakes
nix build .#checks.aarch64-linux.shared-installer-words
nix run .#qml-tests                                 # the views, on Basecamp's design system
```

To try a basecamp-installer-common change, add
`--override-input basecamp-installer-common path:../basecamp-installer-common --no-write-lock-file`.

- **unit-tests** (`tests/cpp`): `AppManager` and `AppSections` with fake
  package modules and a fake Basecamp. Basecamp's consent through
  `intents_module` is the library's `IntentConsent`, tested there.
- **qml-tests** (`tests/qml`): the views on a stand-in backend
  (`FakeBackend.qml`) and a stand-in `logos`, offscreen, on the design system
  Basecamp's master pins. `LOGOS_DESIGN_SYSTEM=<checkout>` runs them on
  another.
- **shared-installer-words**: `src/qml/Installer` is the pinned library's,
  and no screen writes out a phrase the library says. A word that only looks
  shared goes in `tests/shared-words-allow.txt`, with why.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE-v2) or
[MIT license](LICENSE-MIT) at your option.
