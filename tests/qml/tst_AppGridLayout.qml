import QtQuick
import QtTest

import Logos.Theme

import "../../src/qml"
import "../../src/qml/Installer/Types.js" as Types
import "Rows.js" as Rows

// The App Manager grid's geometry: cells sized from the width actually
// available, sections starting lines of their own, and an app name that uses
// the cell rather than the icon under it. Then the tiles' badges.
TestCase {
    id: testCase
    // A desktop window: below 600 px dialogs and menus are phone sheets.
    width: 900
    height: 700
    name: "AppGridLayout"
    when: windowShown

    readonly property string veryLongName:
        "Extraordinarily Long Application Display Name That Cannot Possibly Fit"

    function appData(name, displayName) {
        return Rows.installed(name, { displayName: displayName })
    }

    function findByObjectName(item, target) {
        if (!item)
            return null;
        if (item.objectName === target)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; ++i) {
            var hit = findByObjectName(kids[i], target);
            if (hit)
                return hit;
        }
        if (item.contentItem)
            return findByObjectName(item.contentItem, target);
        return null;
    }

    function gridLabel(delegate) {
        var label = findByObjectName(delegate, "appGridDelegate.label");
        verify(label, "found the grid delegate's name label");
        return label;
    }

    Component { id: gridDelegateComp; AppGridDelegate {} }
    Component { id: listDelegateComp; AppListDelegate {} }
    Component { id: tilesComp; AppTiles {} }
    Component { id: modelComp; ListModel {} }

    function tiles(width, rows, viewMode) {
        var model = createTemporaryObject(modelComp, testCase);
        Rows.fill(model, rows);
        var t = createTemporaryObject(tilesComp, testCase, {
            width: width, model: model, viewMode: viewMode || "grid",
        });
        verify(t, "tiles created");
        return t;
    }

    function sixApps() {
        var rows = [Rows.section(Rows.repo, "Logos", 6)];
        for (var i = 0; i < 6; ++i)
            rows.push(Rows.app("app_" + i, { displayName: "App " + i }));
        return rows;
    }

    // ── The cell width follows the available width ───────────────────────────
    // A tile's narrowest cell is the design system's for that width
    // (Theme.tileWidth): three across a phone, five across a desktop's grid.
    function test_columns_follow_the_available_width_data() {
        return [
            { tag: "desktop 1000", width: 1000, columns: 5 },
            { tag: "tablet 700",   width: 700,  columns: 5 },
            { tag: "tablet 600",   width: 600,  columns: 4 },
            { tag: "phone 340",    width: 340,  columns: 3 },
            { tag: "phone 200",    width: 200,  columns: 1 },
        ];
    }

    function test_columns_follow_the_available_width(data) {
        var t = tiles(data.width, sixApps());
        var first = findByObjectName(t, "appManager.app.app_0");
        verify(first, "delegate instantiated");
        compare(Math.floor(data.width / first.width), data.columns, "columns");
        var header = findByObjectName(t, "appManager.section." + Rows.repo);
        verify(header, "the section's row");
        var rows = Math.ceil(6 / data.columns);
        tryCompare(t, "implicitHeight", header.height + rows * 162, 2000, "rows of 162 under the section");
    }

    function test_cells_absorb_the_leftover_width() {
        var t = tiles(1000, [Rows.section(Rows.repo, "Logos", 1), Rows.app("app_0")]);
        var delegate = findByObjectName(t, "appManager.app.app_0");
        verify(delegate, "delegate instantiated");
        compare(delegate.width, 200, "1000px over 5 columns");

        t.width = 900;
        tryCompare(delegate, "width", 180, 2000, "900px divides exactly");
    }

    // ── Sections ─────────────────────────────────────────────────────────────
    function test_each_section_starts_a_line_of_its_own() {
        var t = tiles(1000, [Rows.section("a", "First", 1), Rows.app("one", { sectionKey: "a" }),
                             Rows.section("b", "Second", 2), Rows.app("two", { sectionKey: "b" }),
                             Rows.app("three", { sectionKey: "b" })]);
        var first = findByObjectName(t, "appManager.section.a");
        var second = findByObjectName(t, "appManager.section.b");
        var one = findByObjectName(t, "appManager.app.one");
        var two = findByObjectName(t, "appManager.app.two");
        var three = findByObjectName(t, "appManager.app.three");
        verify(first && second && one && two && three);
        tryVerify(function() { return second.parent.y > one.parent.y }, 2000,
                  "the second section is under the first's apps");
        compare(second.parent.x, 0, "and spans the width");
        compare(second.parent.width, 1000);
        compare(two.parent.y, three.parent.y, "its apps share a line");
        verify(two.parent.y > second.parent.y, "under it");
        compare(findByObjectName(second, "appSection.title").text, "Second");
        compare(findByObjectName(second, "appSection.count").text, "(2)");
    }

    function test_a_list_puts_one_app_on_each_line() {
        var t = tiles(800, sixApps(), "list");
        var a = findByObjectName(t, "appManager.app.app_0");
        var b = findByObjectName(t, "appManager.app.app_1");
        verify(a && b);
        compare(a.width, 800);
        compare(a.height, 64);
        tryVerify(function() { return b.parent.y === a.parent.y + 64 }, 2000);
    }

    // A positioner can cull an item it held at no size; one that was must
    // still draw once it has one.
    function test_a_section_row_draws() {
        var t = createTemporaryObject(tilesComp, testCase.Window.window.contentItem, {
            width: 0, model: null,
        });
        var model = createTemporaryObject(modelComp, testCase);
        Rows.fill(model, sixApps());
        t.model = model;
        t.width = 600;
        var header = findByObjectName(t, "appManager.section." + Rows.repo);
        verify(header);
        waitForRendering(t);
        var title = findByObjectName(header, "appSection.title");
        var image = grabImage(t);
        var at = title.mapToItem(t, 0, 0);
        var empty = String(image.pixel(t.width - 2, at.y + 1));
        var drawn = false;
        for (var x = at.x; x < at.x + title.contentWidth && !drawn; ++x)
            for (var y = at.y; y < at.y + title.height && !drawn; ++y)
                drawn = String(image.pixel(x, y)) !== empty;
        verify(drawn, "the section's title is drawn");
    }

    // ── Icons in Basecamp's sandbox ─────────────────────────────────────────
    // The backend sends an icon as a data: URL, which Basecamp's sandbox
    // refuses to load: only an image its SandboxImages made of one shows. The
    // tiles passed the data: URL on as it came, so no icon showed in Basecamp.
    readonly property string iconData: "data:image/png;base64,iVBORw0KGgo="
    readonly property string sandboxed: "image://sandbox-media/0123456789abcdef01234567"
    QtObject {
        id: fakeImages
        property var asked: []
        // In place: assigning `asked` would re-run the binding that asks.
        function sourceFor(url) {
            asked.push(url)
            return testCase.sandboxed
        }
    }

    function test_an_icon_shows_through_the_sandbox_data() {
        return [{ tag: "grid", comp: gridDelegateComp }, { tag: "list", comp: listDelegateComp }]
    }

    function test_an_icon_shows_through_the_sandbox(data) {
        fakeImages.asked = []
        var delegate = createTemporaryObject(data.comp, testCase, {
            width: 200, height: 162, sandboxImages: fakeImages,
            appData: Rows.app("wallet_ui", { iconUrl: testCase.iconData }),
        })
        var icon = findByObjectName(delegate, "appManager.tileIcon")
        verify(icon, "found the tile's icon")
        compare(String(icon.source), testCase.sandboxed)
        verify(fakeImages.asked.indexOf(testCase.iconData) >= 0, "asked SandboxImages for it")
    }

    // An app without an icon has no colour of its own, installed or not, as
    // Basecamp's sidebar shows it.
    function test_a_tile_without_an_icon_has_no_colour_of_its_own_data() {
        return [{ tag: "grid", comp: gridDelegateComp }, { tag: "list", comp: listDelegateComp }]
    }

    function test_a_tile_without_an_icon_has_no_colour_of_its_own(data) {
        for (const installed of [false, true]) {
            const delegate = createTemporaryObject(data.comp, testCase, {
                width: 200, height: 162,
                appData: Rows.app("wallet_ui", { isInstalled: installed }),
            })
            const icon = findByObjectName(delegate, "appManager.tileIcon")
            verify(Qt.colorEqual(icon.fallbackColor, Theme.palette.surfaceRaised),
                   "installed " + installed + ": " + icon.fallbackColor)
        }
    }

    function test_an_icon_shows_from_its_url_outside_basecamp() {
        var delegate = createTemporaryObject(gridDelegateComp, testCase, {
            width: 200, height: 162,
            appData: Rows.app("wallet_ui", { iconUrl: testCase.iconData }),
        })
        compare(delegate.sandboxImages, null)
        compare(String(findByObjectName(delegate, "appManager.tileIcon").source), testCase.iconData)
    }

    // ── The name uses the cell, not the icon ────────────────────────────────
    function test_label_is_wider_than_the_icon_it_sits_under() {
        var delegate = createTemporaryObject(gridDelegateComp, testCase, {
            width: 200, height: 162, appData: appData("app", "App"),
        });
        var label = gridLabel(delegate);
        verify(label.width > delegate.tileSize,
               "label " + label.width + "px is wider than the "
               + delegate.tileSize + "px tile");
        // Spans the cell less the delegate's side margins (spacing.small each).
        compare(label.width, 200 - 8 * 2, "label fills the cell minus margins");
    }

    function test_short_name_is_one_line_and_not_truncated() {
        var delegate = createTemporaryObject(gridDelegateComp, testCase, {
            width: 200, height: 162, appData: appData("chat", "Chat"),
        });
        var label = gridLabel(delegate);
        compare(label.lineCount, 1, "short name needs one line");
        compare(label.truncated, false, "and is not elided");
    }

    // ── The very long name ──────────────────────────────────────────────────
    function test_very_long_name_wraps_to_two_lines_then_elides() {
        var delegate = createTemporaryObject(gridDelegateComp, testCase, {
            width: 200, height: 162,
            appData: appData("long_app", testCase.veryLongName),
        });
        var label = gridLabel(delegate);

        compare(label.lineCount, 2,
                "wraps to the second line rather than eliding on the first");
        compare(label.truncated, true,
                "and elides once the second line is full");
        verify(label.width <= 200,
               "never wider than its cell (" + label.width + "px)");
        compare(label.maximumLineCount, 2, "capped at two lines");
    }

    function test_wrapped_name_stays_inside_the_cell_height() {
        var delegate = createTemporaryObject(gridDelegateComp, testCase, {
            width: 200, height: 162,
            appData: appData("long_app", testCase.veryLongName),
        });
        var label = gridLabel(delegate);
        var bottom = label.mapToItem(delegate, 0, label.height).y;
        verify(bottom <= delegate.height,
               "name ends at " + bottom + "px, inside the "
               + delegate.height + "px cell");
    }

    function test_one_long_token_still_uses_both_lines() {
        var delegate = createTemporaryObject(gridDelegateComp, testCase, {
            width: 200, height: 162,
            appData: appData("t", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        });
        var label = gridLabel(delegate);
        compare(label.wrapMode, Text.Wrap, "wraps anywhere when it must");
        compare(label.lineCount, 2, "uses the second line");
    }

    // ── Where a download comes from ──────────────────────────────────────────
    // Shown in the window: TestCase itself is invisible.
    function gridTile(extra) {
        var data = appData("wallet", "Wallet");
        for (var k in extra) data[k] = extra[k];
        return createTemporaryObject(gridDelegateComp, testCase.Window.window.contentItem, {
            width: 200, height: 162, appData: data,
        });
    }

    // While downloading, the source rides at the start of the progress badge.
    function test_a_download_carries_its_source_in_the_badge() {
        var tile = gridTile({
            isInstalled: false, installStatus: Types.InstallStatus.NotInstalled,
            planInstallStage: Types.InstallStage.Downloading,
            planDownloadReceived: 0, planDownloadTotal: 4096,
            planDownloadTransport: "logos",
        });
        var badge = findByObjectName(tile, "appGridStateBadge");
        verify(badge, "found the state badge");
        compare(badge.text, "Finding peers…");
        verify(String(badge.iconSource).indexOf("logos-storage.svg") >= 0,
               "the badge starts with the Logos Storage icon");
    }

    function test_a_github_download_shows_the_github_icon() {
        var tile = gridTile({
            isInstalled: false, installStatus: Types.InstallStatus.NotInstalled,
            planInstallStage: Types.InstallStage.Downloading,
            planDownloadReceived: 1024, planDownloadTotal: 4096,
            planDownloadTransport: "http",
        });
        var badge = findByObjectName(tile, "appGridStateBadge");
        verify(String(badge.iconSource).indexOf("github.svg") >= 0);
        compare(badge.text, "25%");
    }

    function test_a_failed_install_says_so() {
        var tile = gridTile({
            isInstalled: false, installStatus: Types.InstallStatus.Failed,
            planInstallStage: Types.InstallStage.Failed,
        });
        var badge = findByObjectName(tile, "appGridStateBadge");
        verify(badge.visible);
        compare(badge.text, "Failed");
    }

    function test_an_app_with_nothing_for_this_platform_says_so() {
        var tile = gridTile({
            isInstalled: false, installStatus: Types.InstallStatus.NotInstalled,
            hasInstallableVersion: false,
        });
        var badge = findByObjectName(tile, "appGridStateBadge");
        verify(badge.visible);
        compare(badge.text, "Not available");
    }

    // The list row, like the tile: the source rides in the badge, and the
    // description stays the description.
    function test_a_list_row_download_carries_its_source_in_the_badge() {
        var data = appData("wallet", "Wallet");
        data.description = "Send and receive";
        data.isInstalled = false;
        data.installStatus = Types.InstallStatus.NotInstalled;
        data.planInstallStage = Types.InstallStage.Downloading;
        data.planDownloadReceived = 0;
        data.planDownloadTotal = 4096;
        data.planDownloadTransport = "logos";
        var row = createTemporaryObject(listDelegateComp, testCase.Window.window.contentItem, {
            width: 600, height: 56, appData: data,
        });
        compare(findByObjectName(row, "appListDescription").text, "Send and receive");
        var badge = findByObjectName(row, "appListStateBadge");
        verify(badge, "found the list badge");
        compare(badge.text, "Finding peers…");
        verify(String(badge.iconSource).indexOf("logos-storage.svg") >= 0);
    }

    // ── A click on the state badge is a click on the app ─────────────────────
    // The badge ("Upgrade", "Install", …) sits on top of the tile. A
    // HoverHandler on it made it take the press: clicking the word did
    // nothing, only the icon around it opened the app.
    SignalSpy { id: appClickedSpy; signalName: "appClicked" }

    function updatable() {
        var data = appData("wallet", "Wallet");
        data.installStatus = Types.InstallStatus.UpgradeAvailable;
        return data;
    }

    function clickBadge(delegate, badgeName) {
        var badge = findByObjectName(delegate, badgeName);
        verify(badge && badge.visible, badgeName + " is shown");
        compare(badge.text, "Upgrade");
        appClickedSpy.target = delegate;
        appClickedSpy.clear();
        mouseClick(badge);
        compare(appClickedSpy.count, 1, "clicking the badge opens the app");
        compare(appClickedSpy.signalArguments[0][0], "wallet");

        // …and a right-click on it opens the app's menu, as on the icon.
        mouseClick(badge, badge.width / 2, badge.height / 2, Qt.RightButton);
        tryVerify(function() { return contextMenuOpen(delegate) }, 1000,
                  "right-clicking the badge opens the context menu");
    }

    function contextMenuOpen(delegate) {
        for (var i = 0; i < delegate.data.length; ++i) {
            var o = delegate.data[i];
            if (typeof o.openFor === "function")
                return o.opened;
        }
        return false;
    }

    // The badge's download tooltip, on the Control's own hover.
    function hoverShowsDownloadTip(delegate, badgeName) {
        var badge = findByObjectName(delegate, badgeName);
        verify(badge && badge.visible, badgeName + " is shown");
        mouseMove(badge, badge.width / 2, badge.height / 2);
        // A tooltip is a popup: in the badge's data, not its children.
        var tip = null;
        for (var i = 0; i < badge.data.length; ++i)
            if (badge.data[i].objectName === badgeName + ".toolTip")
                tip = badge.data[i];
        verify(tip, "found the badge tooltip");
        verify(tip.text.length > 0, "the tooltip has something to say");
        tryVerify(function() { return tip.visible }, 1000, "hovering the badge shows its tooltip");
    }

    function downloading() {
        var data = appData("wallet", "Wallet");
        data.isInstalled = false;
        data.installStatus = Types.InstallStatus.NotInstalled;
        data.planInstallStage = Types.InstallStage.Downloading;
        data.planDownloadReceived = 1024;
        data.planDownloadTotal = 4096;
        data.planDownloadTransport = "logos";   // has a caption; http only on fallback
        return data;
    }

    function test_the_tile_badge_tooltip_still_shows_on_hover() {
        var tile = createTemporaryObject(gridDelegateComp, testCase.Window.window.contentItem, {
            width: 200, height: 162, appData: downloading(),
        });
        waitForRendering(tile);
        hoverShowsDownloadTip(tile, "appGridStateBadge");
    }

    function test_the_list_badge_tooltip_still_shows_on_hover() {
        var row = createTemporaryObject(listDelegateComp, testCase.Window.window.contentItem, {
            width: 200, height: 56, appData: downloading(),
        });
        waitForRendering(row);
        hoverShowsDownloadTip(row, "appListStateBadge");
    }

    function test_clicking_the_tile_badge_opens_the_app() {
        var tile = createTemporaryObject(gridDelegateComp, testCase.Window.window.contentItem, {
            width: 200, height: 162, appData: updatable(),
        });
        waitForRendering(tile);
        clickBadge(tile, "appGridStateBadge");
    }

    function test_clicking_the_list_badge_opens_the_app() {
        // Inside the 200 px test window: a click outside it is never delivered.
        var row = createTemporaryObject(listDelegateComp, testCase.Window.window.contentItem, {
            width: 200, height: 56, appData: updatable(),
        });
        waitForRendering(row);
        clickBadge(row, "appListStateBadge");
    }
}
