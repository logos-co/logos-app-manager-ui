// The App Manager's page on fake package modules and a fake Basecamp: the
// apps by repository, the filters, and what each action asks Basecamp
// before anything is installed or removed.

#include "check.h"
#include "fakes.h"
#include "fixtures.h"

#include "AppManager.h"

#include <logos/installer/IconFetcher.h>
#include <logos/installer/Installer.h>
#include <logos/installer/Trust.h>
#include <logos/installer/Types.h>

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSignalSpy>

#include <memory>

using namespace fixtures;
using appmanager::AppManager;
using logos::installer::Consent;
using logos::installer::IconFetcher;
using logos::installer::Installer;

namespace {

const QString kDefault = QStringLiteral("https://default");
const QString kMine = QStringLiteral("https://mine");
const QStringList kHere{QStringLiteral("linux-x86_64")};

QVariantMap app(const QString& repo, const QString& name, const QString& version,
                const QString& hash, const QVariantList& deps = {})
{
    return catalogRow(repo, name, version, hash, deps, kHere);
}

// `row` offering `names` as optional packages.
QVariantMap offering(QVariantMap row, const QStringList& names)
{
    QVariantList versions = row["versions"].toList();
    QVariantMap v = versions[0].toMap();
    QVariantMap m = v["manifest"].toMap();
    m["optional_dependencies"] = QVariant(names).toList();
    v["manifest"] = m;
    versions[0] = v;
    row["versions"] = versions;
    return row;
}

struct App {
    fakes::Modules modules;
    fakes::Basecamp basecamp;
    AppManager manager;
    struct Finished { QString name; int outcome; QString error; };
    QList<Finished> finished;

    App()
    {
        modules.repositories = {
            QVariantMap{{"url", kDefault}, {"displayName", "Logos"}, {"isDefault", true}},
            QVariantMap{{"url", kMine}, {"displayName", "Mine"}},
        };
        manager.setIconFetch([](const QUrl&, IconFetcher::Done done) { done({}, "offline"); });
        manager.setDebounceInterval(0);
        manager.setClearDelay(0);
        manager.setModules(&modules, &modules, &basecamp);
        QObject::connect(&manager, &AppManager::finished, &manager,
                         [this](const QString& name, int outcome, const QString& error) {
                             finished.append({name, outcome, error});
                         });
    }

    void addLocal(const QString& name)
    {
        modules.addInstalled(name, "0.1.0", "L" + name);
        modules.installed[name].insert("type", "ui_qml");
    }

    // "§title count" for a section's row, the name for an app's.
    QStringList lines() const
    {
        const QAbstractItemModel& m = *manager.apps();
        QStringList out;
        for (int r = 0; r < m.rowCount(); ++r) {
            if (at(m, r, "kind").toString() == QLatin1String("section"))
                out << QStringLiteral("§%1 %2").arg(at(m, r, "sectionTitle").toString())
                           .arg(at(m, r, "sectionCount").toInt());
            else
                out << at(m, r, "name").toString();
        }
        return out;
    }

    QString lastIntent() const { return basecamp.asked.isEmpty() ? QString() : basecamp.asked.last().intent; }
    QVariantMap lastParams() const { return basecamp.asked.isEmpty() ? QVariantMap() : basecamp.asked.last().params; }
    QStringList changes() const { return modules.calls.filter(QRegularExpression("^(install|uninstall) ")); }
};

}  // namespace

// ── The list ─────────────────────────────────────────────────────────────

TEST(apps_are_listed_by_repository_the_default_first_and_local_last) {
    App a;
    a.modules.catalog = {app(kMine, "notes_ui", "1.0.0", "N"),
                         app(kDefault, "wallet_ui", "1.0.0", "W"),
                         app(kDefault, "chat_ui", "1.0.0", "C"),
                         // Not apps, or the shell itself: never listed.
                         catalogRow(kDefault, "waku_module", "1.0.0", "K", {}, kHere, "core"),
                         app(kDefault, "main_ui", "1.0.0", "M")};
    a.addLocal("scratch_ui");
    a.manager.load();
    CHECK_EQ(a.lines(), (QStringList{"§Logos 2", "chat_ui", "wallet_ui", "§Mine 1", "notes_ui",
                                     "§local 1", "scratch_ui"}));
    CHECK_EQ(a.manager.visibleCount(), 4);
    CHECK_EQ(a.manager.localCount(), 1);
    CHECK_EQ(a.manager.repositoryCount(), 2);
    CHECK_EQ(a.manager.hostVariant(), QStringLiteral("linux-x86_64"));
    CHECK(!a.manager.loading());
}

TEST(a_disabled_repository_is_left_out) {
    App a;
    a.modules.repositories[1] = QVariantMap{{"url", kMine}, {"displayName", "Mine"}, {"enabled", false}};
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W"), app(kMine, "notes_ui", "1.0.0", "N")};
    a.manager.load();
    CHECK_EQ(a.lines(), (QStringList{"§Logos 1", "wallet_ui"}));
    CHECK_EQ(a.manager.visibleCount(), 1);
}

TEST(the_filters_narrow_the_list) {
    App a;
    a.modules.catalog = {withCategory(app(kDefault, "wallet_ui", "1.0.0", "W"), "wallet"),
                         withCategory(app(kDefault, "chat_ui", "1.0.0", "C"), "Chat"),
                         withCategory(app(kMine, "notes_ui", "1.0.0", "N"), "chat")};
    a.modules.addInstalled("wallet_ui", "1.0.0", "W");
    a.manager.load();
    CHECK_EQ(a.manager.categories(), (QStringList{"All", "Chat", "Wallet"}));

    QSignalSpy counts(&a.manager, &AppManager::countsChanged);
    a.manager.setSearchText("NOTES");
    CHECK_EQ(a.lines(), (QStringList{"§Mine 1", "notes_ui"}));
    CHECK(counts.count() > 0);
    a.manager.setSearchText({});

    a.manager.setCategory("Chat");
    CHECK_EQ(a.lines(), (QStringList{"§Logos 1", "chat_ui", "§Mine 1", "notes_ui"}));
    CHECK_EQ(a.manager.category(), QStringLiteral("Chat"));
    a.manager.setCategory("All");
    CHECK_EQ(a.manager.visibleCount(), 3);

    a.manager.setInstallState(1);
    CHECK_EQ(a.lines(), (QStringList{"§Logos 1", "wallet_ui"}));
    a.manager.setInstallState(2);
    CHECK_EQ(a.lines(), (QStringList{"§Logos 1", "chat_ui", "§Mine 1", "notes_ui"}));
}

TEST(an_app_with_nothing_for_this_platform_shows_only_when_asked) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W"),
                         catalogRow(kDefault, "mac_ui", "1.0.0", "X", {}, {"darwin-arm64"})};
    a.manager.load();
    CHECK_EQ(a.lines(), (QStringList{"§Logos 1", "wallet_ui"}));
    a.manager.setShowUnavailable(true);
    CHECK_EQ(a.lines(), (QStringList{"§Logos 2", "mac_ui", "wallet_ui"}));
    // Not available: the tile offers nothing to install.
    CHECK(!a.manager.install("mac_ui", kDefault));
    CHECK(a.basecamp.asked.isEmpty());
}

// ── Installing: Basecamp first ───────────────────────────────────────────

TEST(install_asks_basecamp_and_installs_nothing_until_it_says_yes) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    a.modules.serve("wallet_ui", "1.0.0", "W");
    a.manager.load();

    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK_EQ(a.lastIntent(), QString(Consent::kConfirmInstall));
    CHECK_EQ(a.lastParams().value("name").toString(), QStringLiteral("wallet_ui"));
    CHECK_EQ(a.lastParams().value("version").toString(), QStringLiteral("1.0.0"));
    CHECK_EQ(a.lastParams().value("repositoryUrl").toString(), kDefault);
    // Waiting for the person: nothing downloaded, nothing installed.
    CHECK(a.changes().isEmpty());
    CHECK(!a.modules.calls.contains("download wallet_ui"));

    a.basecamp.waiting.takeFirst()(fakes::refuse("cancelled"));
    CHECK(a.changes().isEmpty());
    CHECK_EQ(a.finished.size(), 1);
    CHECK_EQ(a.finished.last().outcome, static_cast<int>(Installer::Outcome::Cancelled));

    a.basecamp.decide = [](const QString&, const QVariantMap&) {
        return fakes::approve({{"plan", QVariantList{fakes::release(kDefault, "wallet_ui", "1.0.0", "W")}}});
    };
    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK_EQ(a.changes(), QStringList{"install wallet_ui"});
    CHECK_EQ(a.finished.last().outcome, static_cast<int>(Installer::Outcome::Done));

    // package_manager says so; the tile follows what is on disk.
    a.manager.onPackagesChanged();
    SPIN(20);
    CHECK_EQ(roleOf(*a.manager.apps(), "wallet_ui", "isInstalled").toBool(), true);
}

TEST(the_tiles_action_picks_what_is_asked) {
    App a;
    a.modules.catalog = {withOlderVersion(app(kDefault, "wallet_ui", "2.0.0", "W2"), "1.0.0", "W1"),
                         app(kDefault, "chat_ui", "1.0.0", "C")};
    a.modules.addInstalled("wallet_ui", "1.5.0", "W15");
    a.modules.addInstalled("chat_ui", "1.0.0", "other");
    a.manager.load();

    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK_EQ(a.lastIntent(), QString(Consent::kConfirmUpgrade));
    CHECK_EQ(a.lastParams().value("version").toString(), QStringLiteral("2.0.0"));
    CHECK_EQ(a.lastParams().value("mode").toInt(), 0);
    a.basecamp.waiting.takeFirst()(fakes::refuse("cancelled"));

    a.manager.selectVersion("wallet_ui", kDefault, "1.0.0");
    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK_EQ(a.lastParams().value("version").toString(), QStringLiteral("1.0.0"));
    CHECK_EQ(a.lastParams().value("mode").toInt(), 1);
    a.basecamp.waiting.takeFirst()(fakes::refuse("cancelled"));

    // The same version, built differently.
    CHECK(a.manager.install("chat_ui", kDefault));
    CHECK_EQ(a.lastIntent(), QString(Consent::kConfirmUpgrade));
    CHECK_EQ(a.lastParams().value("mode").toInt(), 2);
}

TEST(a_current_app_whose_dependency_moved_on_asks_to_install_it_again) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W", {dep("signer")}),
                         catalogRow(kDefault, "signer", "1.1.0", "S11", {}, kHere, "core")};
    a.modules.addInstalled("wallet_ui", "1.0.0", "W");
    a.modules.addInstalled("signer", "1.0.0", "S10");
    a.manager.load();
    CHECK_EQ(roleOf(*a.manager.apps(), "wallet_ui", "installStatus").toInt(),
             static_cast<int>(logos::installer::InstallStatus::UpgradeAvailable));
    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK_EQ(a.lastIntent(), QString(Consent::kConfirmInstall));
    CHECK_EQ(a.lastParams().value("version").toString(), QStringLiteral("1.0.0"));
}

TEST(a_current_app_offers_nothing_to_install) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    a.modules.addInstalled("wallet_ui", "1.0.0", "W");
    a.manager.load();
    CHECK(!a.manager.install("wallet_ui", kDefault));
    CHECK(!a.manager.install("nope", kDefault));
    CHECK(!a.manager.install("main_ui", kDefault));
    CHECK(a.basecamp.asked.isEmpty());
}

// Both put to Basecamp at once, the second saying it can wait; one at a
// time after that, in the order asked: the second, approved for its turn,
// hands its ticket back once the first is through.
TEST(each_is_asked_about_at_once_and_goes_in_turn) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W"), app(kDefault, "chat_ui", "1.0.0", "C")};
    a.manager.load();
    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK(a.manager.install("chat_ui", kDefault));
    CHECK_EQ(a.basecamp.asked.size(), 2);
    CHECK_EQ(a.basecamp.asked.value(1).params.value("name").toString(), QStringLiteral("chat_ui"));
    CHECK(a.basecamp.asked.value(1).params.value("waits").toBool());
    a.basecamp.waiting.takeLast()(fakes::approve({{"ticket", "t1"}}));
    SPIN(10);
    CHECK_EQ(a.basecamp.asked.size(), 2);
    a.basecamp.waiting.takeFirst()(fakes::refuse("cancelled"));
    SPIN(10);
    CHECK_EQ(a.basecamp.asked.size(), 3);
    CHECK_EQ(a.lastParams().value("name").toString(), QStringLiteral("chat_ui"));
    CHECK_EQ(a.lastParams().value("ticket").toString(), QStringLiteral("t1"));
}

// ── apps.install, delivered by intents_module ────────────────────────────

struct Responses {
    QList<QPair<bool, QString>> got;
    AppManager::Respond respond()
    {
        return [this](bool ok, const QString& error) { got.append({ok, error}); };
    }
};

// Basecamp's own request, the person's click there: whether it was taken on
// at once.
bool shellAsks(App& a, const QString& name, const QString& repositoryUrl = {})
{
    const auto taken = std::make_shared<bool>(false);
    QVariantMap params{{"name", name}};
    if (!repositoryUrl.isEmpty()) params.insert("repositoryUrl", repositoryUrl);
    a.manager.deliver("apps.install", params, "main_ui",
                      [taken](bool ok, const QString&) { *taken = ok; });
    return *taken;
}

// Another app's request: whether it was taken on at once.
bool otherAppAsks(App& a, const QString& name)
{
    const auto taken = std::make_shared<bool>(false);
    a.manager.deliver("apps.install", {{"name", name}}, "chat_ui",
                      [taken](bool ok, const QString&) { *taken = ok; });
    return *taken;
}

TEST(basecamps_request_takes_the_default_repository_first) {
    App a;
    a.modules.catalog = {app(kMine, "notes_ui", "1.0.0", "N1"), app(kDefault, "notes_ui", "1.0.0", "N2")};
    a.manager.load();
    CHECK(shellAsks(a, "notes_ui"));
    CHECK_EQ(a.lastParams().value("repositoryUrl").toString(), kDefault);
    // And shows what was asked for.
    CHECK_EQ(a.manager.details().value("repositoryUrl").toString(), kDefault);
    for (const QString& name : {QStringLiteral("nothing_ui"), QStringLiteral("main_ui"), QString()}) {
        CHECK(!shellAsks(a, name));
        CHECK(!otherAppAsks(a, name));
    }
}

// The repository it was picked from comes first: with two that list it, the
// first one used to win whichever was clicked.
TEST(a_request_takes_the_repository_it_was_picked_from) {
    App a;
    a.modules.catalog = {app(kMine, "notes_ui", "1.0.0", "N1"), app(kDefault, "notes_ui", "1.0.0", "N2")};
    a.manager.load();
    CHECK(shellAsks(a, "notes_ui", kMine));
    CHECK_EQ(a.lastParams().value("repositoryUrl").toString(), kMine);
    CHECK_EQ(a.manager.details().value("repositoryUrl").toString(), kMine);
    a.basecamp.waiting.takeFirst()(fakes::refuse("cancelled"));
    SPIN(10);
    // One that doesn't list it, or isn't known, leaves the usual order.
    CHECK(shellAsks(a, "notes_ui", QStringLiteral("https://elsewhere")));
    CHECK_EQ(a.lastParams().value("repositoryUrl").toString(), kDefault);
}

TEST(basecamps_request_for_an_installed_app_only_shows_it) {
    App a;
    a.modules.catalog = {app(kDefault, "notes_ui", "1.0.0", "N")};
    a.modules.addInstalled("notes_ui", "1.0.0", "N");
    a.manager.load();
    CHECK(shellAsks(a, "notes_ui"));
    CHECK(a.basecamp.asked.isEmpty());
    CHECK_EQ(a.manager.details().value("name").toString(), QStringLiteral("notes_ui"));
}

TEST(a_delivery_waits_for_the_catalog_then_installs) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    Responses r;
    CHECK(a.manager.deliver("apps.install", {{"name", "wallet_ui"}}, "main_ui", r.respond()));
    CHECK(r.got.isEmpty());
    a.manager.load();
    CHECK_EQ(r.got.size(), 1);
    CHECK(r.got.first().first);
    CHECK_EQ(a.lastIntent(), QString(Consent::kConfirmInstall));
    CHECK_EQ(a.manager.details().value("name").toString(), QStringLiteral("wallet_ui"));
}

// Another app's request only shows the app: the person's own click on
// Install is what asks Basecamp, so a dialog never opens on another app's
// say-so looking like the person's own.
TEST(another_apps_delivery_shows_the_app_and_asks_basecamp_nothing) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    a.manager.load();
    for (const char* requester : {"chat_ui", "logos_link", ""}) {
        Responses r;
        CHECK(a.manager.deliver("apps.install", {{"name", "wallet_ui"}}, requester, r.respond()));
        CHECK_EQ(r.got.size(), 1);
        CHECK(r.got.first().first);
        CHECK_EQ(a.manager.details().value("name").toString(), QStringLiteral("wallet_ui"));
        CHECK(a.basecamp.asked.isEmpty());
        a.manager.closeDetails();
    }
    // Waiting for the catalog changes nothing about it.
    App b;
    b.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    Responses r;
    CHECK(b.manager.deliver("apps.install", {{"name", "wallet_ui"}}, "chat_ui", r.respond()));
    b.manager.load();
    CHECK_EQ(r.got.size(), 1);
    CHECK(b.basecamp.asked.isEmpty());
}

// The backend keeps to apps whatever asks it, not only what the page lists.
TEST(only_an_app_installs_uninstalls_or_shows_its_details) {
    App a;
    a.modules.catalog = {withOlderVersion(catalogRow(kDefault, "signer", "2.0.0", "S2", {}, kHere, "core"),
                                          "1.0.0", "S1")};
    a.modules.addInstalled("signer", "1.0.0", "S1");
    a.manager.load();
    CHECK(!a.manager.install("signer", kDefault));
    CHECK(!a.manager.uninstall("signer", kDefault));
    a.manager.showDetails("signer", kDefault);
    CHECK(a.manager.details().isEmpty());
    CHECK(a.basecamp.asked.isEmpty());
    CHECK(a.changes().isEmpty());
}

// What the page hides of a disabled repository, the backend doesn't install
// or open either, whatever asks.
TEST(nothing_installs_or_opens_from_a_disabled_repository) {
    App a;
    a.modules.repositories[1] = QVariantMap{{"url", kMine}, {"displayName", "Mine"}, {"enabled", false}};
    a.modules.catalog = {app(kMine, "notes_ui", "1.0.0", "N")};
    a.manager.load();
    CHECK(!a.manager.install("notes_ui", kMine));
    a.manager.showDetails("notes_ui", kMine);
    CHECK(a.manager.details().isEmpty());
    CHECK(!shellAsks(a, "notes_ui"));
    CHECK(a.basecamp.asked.isEmpty());
}

// By name, App Manager finds apps only, as its page lists them.
TEST(by_name_only_an_app_is_found) {
    App a;
    a.modules.catalog = {catalogRow(kDefault, "signer", "1.0.0", "S", {}, kHere, "core")};
    a.manager.load();
    CHECK(!otherAppAsks(a, "signer"));
    Responses r;
    CHECK(a.manager.deliver("apps.install", {{"name", "signer"}}, "main_ui", r.respond()));
    CHECK(!r.got.first().first);
    CHECK(a.basecamp.asked.isEmpty());
}

TEST(a_delivery_for_what_no_repository_has_fails) {
    App a;
    a.manager.load();
    Responses r;
    CHECK(a.manager.deliver("apps.install", {{"name", "nothing_ui"}}, "main_ui", r.respond()));
    CHECK_EQ(r.got.size(), 1);
    CHECK(!r.got.first().first);
    CHECK_EQ(r.got.first().second, QStringLiteral("failed"));
    CHECK(a.basecamp.asked.isEmpty());
}

TEST(a_delivery_that_waits_too_long_fails_once) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    a.manager.setDeliveryTimeout(10);
    Responses r;
    CHECK(a.manager.deliver("apps.install", {{"name", "wallet_ui"}}, "main_ui", r.respond()));
    SPIN(50);
    CHECK_EQ(r.got.size(), 1);
    CHECK(!r.got.first().first);
    a.manager.load();
    CHECK_EQ(r.got.size(), 1);
    CHECK(a.basecamp.asked.isEmpty());
}

// What intents_module delivers here: apps.install and apps.search, as
// metadata.json declares them. packages.install is Package Manager's, as it
// was before App Manager left Basecamp: Basecamp's Install for a package went
// here, which shows only apps, and nothing came up.
TEST(it_provides_apps_install_and_apps_search_as_it_declares) {
    CHECK(AppManager::provides(QStringLiteral("apps.install")));
    CHECK(AppManager::provides(QStringLiteral("apps.search")));
    CHECK(!AppManager::provides(QStringLiteral("packages.install")));
    CHECK(!AppManager::provides(QStringLiteral("packages.show")));

    QFile metadata(QStringLiteral(APP_SOURCE_DIR "/../metadata.json"));
    CHECK(metadata.open(QIODevice::ReadOnly));
    QStringList declared;
    const QJsonArray provides =
        QJsonDocument::fromJson(metadata.readAll()).object().value(QStringLiteral("provides")).toArray();
    for (const QJsonValue& v : provides) declared << v.toObject().value(QStringLiteral("intent")).toString();
    declared.sort();
    CHECK_EQ(declared, (QStringList{QStringLiteral("apps.install"), QStringLiteral("apps.search")}));
}

TEST(apps_search_closes_the_details_and_searches) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    QSignalSpy asked(&a.manager, &AppManager::searchRequested);
    Responses r;
    CHECK(AppManager::provides("apps.search"));
    CHECK(a.manager.deliver("apps.search", {{"query", "wal"}}, "main_ui", r.respond()));
    CHECK(a.manager.details().isEmpty());
    CHECK_EQ(asked.count(), 1);
    CHECK_EQ(asked.first().first().toString(), QStringLiteral("wal"));
    CHECK_EQ(r.got.size(), 1);
    CHECK(r.got.first().first);
}

TEST(an_intent_it_does_not_provide_is_not_taken) {
    App a;
    a.manager.load();
    Responses r;
    CHECK(!AppManager::provides("packages.show"));
    CHECK(!a.manager.deliver("packages.show", {{"name", "wallet_ui"}}, "main_ui", r.respond()));
    CHECK(r.got.isEmpty());
}

// ── Uninstalling ─────────────────────────────────────────────────────────

TEST(uninstall_asks_basecamp_then_removes) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    a.modules.addInstalled("wallet_ui", "1.0.0", "W");
    a.manager.load();
    CHECK(a.manager.uninstall("wallet_ui", kDefault));
    CHECK_EQ(a.lastIntent(), QString(Consent::kConfirmUninstall));
    CHECK_EQ(a.lastParams().value("names").toStringList(), QStringList{"wallet_ui"});
    CHECK(a.changes().isEmpty());
    a.basecamp.waiting.takeFirst()(fakes::approve({{"names", QStringList{"wallet_ui"}}}));
    CHECK_EQ(a.changes(), QStringList{"uninstall wallet_ui"});
    CHECK_EQ(a.finished.last().outcome, static_cast<int>(Installer::Outcome::Done));
}

TEST(only_what_the_user_installed_can_be_uninstalled) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W"), app(kDefault, "chat_ui", "1.0.0", "C")};
    a.modules.addInstalled("wallet_ui", "1.0.0", "W", "builtin");
    a.manager.load();
    CHECK(!a.manager.uninstall("wallet_ui", kDefault));
    CHECK(!a.manager.uninstall("chat_ui", kDefault));
    CHECK(!a.manager.uninstall("main_ui", kDefault));
    CHECK(a.basecamp.asked.isEmpty());
}

TEST(a_local_app_is_found_with_no_repository) {
    App a;
    a.addLocal("scratch_ui");
    a.manager.load();
    CHECK(a.manager.uninstall("scratch_ui", {}));
    CHECK_EQ(a.lastParams().value("names").toStringList(), QStringList{"scratch_ui"});
    // Nothing to install it from.
    CHECK(!a.manager.install("scratch_ui", {}));
}

// ── Details ──────────────────────────────────────────────────────────────

TEST(details_follow_the_app_and_close) {
    App a;
    a.modules.catalog = {withOlderVersion(app(kDefault, "wallet_ui", "2.0.0", "W2"), "1.0.0", "W1")};
    a.manager.load();
    QSignalSpy changed(&a.manager, &AppManager::detailsChanged);
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK_EQ(a.manager.details().value("name").toString(), QStringLiteral("wallet_ui"));
    CHECK_EQ(a.manager.details().value("version").toString(), QStringLiteral("2.0.0"));
    a.manager.selectVersion("wallet_ui", kDefault, "1.0.0");
    CHECK_EQ(a.manager.details().value("version").toString(), QStringLiteral("1.0.0"));
    CHECK(changed.count() >= 2);
    a.manager.closeDetails();
    CHECK(a.manager.details().isEmpty());
}

TEST(details_say_what_the_app_brings_and_follow_it) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W", {dep("signer")}),
                         catalogRow(kDefault, "signer", "2.0.0", "S2", {}, kHere, "core")};
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    // The app itself, then what it needs.
    const auto signerAction = [&a] {
        const QVariantList packages = a.manager.details().value("packages").toList();
        return packages.size() < 2 ? -1 : packages.at(1).toMap().value("rowAction").toInt();
    };
    const QVariantList packages = a.manager.details().value("packages").toList();
    CHECK_EQ(packages.size(), 2);
    CHECK_EQ(packages.first().toMap().value("name").toString(), QStringLiteral("wallet_ui"));
    CHECK_EQ(signerAction(), static_cast<int>(logos::installer::RowAction::Install));

    // The dependency arrives on its own: the open details say so.
    a.modules.addInstalled("signer", "2.0.0", "S2");
    a.manager.onPackagesChanged();
    SPIN(20);
    CHECK_EQ(signerAction(), static_cast<int>(logos::installer::RowAction::NoOp));
}

// The details' picks go to Basecamp with the install: a package it needs at
// another version than the newest, and the optional ones as ticked.
TEST(the_picks_in_the_details_go_to_basecamp_with_the_install) {
    App a;
    a.modules.catalog = {offering(app(kDefault, "wallet_ui", "1.0.0", "W", {dep("signer")}), {"extra"}),
                         withOlderVersion(catalogRow(kDefault, "signer", "2.0.0", "S2", {}, kHere, "core"),
                                          "1.0.0", "S1"),
                         catalogRow(kDefault, "extra", "1.0.0", "E", {}, kHere, "core")};
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);

    a.manager.selectVersion("signer", kDefault, "1.0.0");
    a.manager.setOptional("extra", false);
    const auto entry = [&a](const QString& name) {
        for (const QVariant& v : a.manager.details().value("packages").toList())
            if (v.toMap().value("name").toString() == name) return v.toMap();
        return QVariantMap{};
    };
    CHECK_EQ(entry("signer").value("version").toString(), QStringLiteral("1.0.0"));
    CHECK_EQ(entry("extra").value("selected").toBool(), false);

    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK_EQ(a.lastParams().value("versions").toMap(), (QVariantMap{{"signer", "1.0.0"}}));
    CHECK_EQ(a.lastParams().value("optional").toMap(), (QVariantMap{{"extra", false}}));
    a.basecamp.waiting.takeFirst()(fakes::refuse("cancelled"));
    SPIN(10);

    // Closed: the picks are gone, the newest is back.
    a.manager.closeDetails();
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK_EQ(entry("signer").value("version").toString(), QStringLiteral("2.0.0"));
    CHECK_EQ(entry("extra").value("selected").toBool(), true);
    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK(!a.lastParams().contains("versions"));
    CHECK_EQ(a.lastParams().value("optional").toMap(), (QVariantMap{{"extra", true}}));
}

// As Basecamp's install dialog had it: what a package the app needs offers
// is offered too, and what comes with a ticked one is no choice of its own;
// a version picked for it goes like any other.
TEST(what_comes_with_an_optional_package_goes_to_basecamp_as_a_version_not_a_choice) {
    App a;
    a.modules.catalog = {app(kDefault, "chat_ui", "1.0.0", "C", {dep("delivery")}),
                         offering(catalogRow(kDefault, "delivery", "1.0.0", "D", {}, kHere, "core"), {"rln"}),
                         catalogRow(kDefault, "rln", "1.0.0", "R", {dep("zk")}, kHere, "core"),
                         withOlderVersion(catalogRow(kDefault, "zk", "2.0.0", "Z2", {}, kHere, "core"),
                                          "1.0.0", "Z1")};
    a.manager.load();
    a.manager.showDetails("chat_ui", kDefault);
    const auto entry = [&a](const QString& name) {
        for (const QVariant& v : a.manager.details().value("packages").toList())
            if (v.toMap().value("name").toString() == name) return v.toMap();
        return QVariantMap{};
    };
    CHECK_EQ(entry("rln").value("offeredBy").toString(), QStringLiteral("delivery"));
    CHECK(entry("rln").value("selected").toBool());
    CHECK_EQ(entry("zk").value("requiredFor").toString(), QStringLiteral("rln"));

    a.manager.selectVersion("zk", kDefault, "1.0.0");
    CHECK(a.manager.install("chat_ui", kDefault));
    CHECK_EQ(a.lastParams().value("versions").toMap(), (QVariantMap{{"zk", "1.0.0"}}));
    CHECK_EQ(a.lastParams().value("optional").toMap(), (QVariantMap{{"rln", true}}));
    a.basecamp.waiting.takeFirst()(fakes::refuse("cancelled"));
    SPIN(10);

    // Unticked, nothing comes with it.
    a.manager.setOptional("rln", false);
    CHECK(entry("zk").isEmpty());
    CHECK(a.manager.install("chat_ui", kDefault));
    CHECK_EQ(a.lastParams().value("optional").toMap(), (QVariantMap{{"rln", false}}));
}

TEST(details_of_an_app_that_went_away_are_empty) {
    App a;
    a.addLocal("scratch_ui");
    a.manager.load();
    a.manager.showDetails("scratch_ui", {});
    CHECK_EQ(a.manager.details().value("name").toString(), QStringLiteral("scratch_ui"));
    a.modules.installed.remove("scratch_ui");
    a.manager.onPackagesChanged();
    SPIN(20);
    CHECK(a.manager.details().isEmpty());
    // Back again: its details stay closed; they opened on their own.
    a.addLocal("scratch_ui");
    a.manager.onPackagesChanged();
    SPIN(20);
    CHECK(a.manager.details().isEmpty());
}

// What a range chose, Basecamp's resolver chooses too: only a pick is sent.
TEST(a_version_its_range_chose_goes_unpinned) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W", {dep("signer", "~1.0.0")}),
                         withOlderVersion(catalogRow(kDefault, "signer", "2.0.0", "S2", {}, kHere, "core"),
                                          "1.0.0", "S1")};
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    QVariantMap signer;
    for (const QVariant& v : a.manager.details().value("packages").toList())
        if (v.toMap().value("name").toString() == QLatin1String("signer")) signer = v.toMap();
    CHECK_EQ(signer.value("version").toString(), QStringLiteral("1.0.0"));
    CHECK(a.manager.install("wallet_ui", kDefault));
    CHECK(!a.lastParams().contains("versions"));
}

// A version picked in the details is the details' own: an app it brings
// keeps its own on its tile.
TEST(a_version_picked_for_an_app_it_brings_leaves_that_apps_tile_as_it_was) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W", {dep("keys_ui")}),
                         withOlderVersion(app(kDefault, "keys_ui", "2.0.0", "K2"), "1.0.0", "K1")};
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    a.manager.selectVersion("keys_ui", kDefault, "1.0.0");
    QVariantMap keys;
    for (const QVariant& v : a.manager.details().value("packages").toList())
        if (v.toMap().value("name").toString() == QLatin1String("keys_ui")) keys = v.toMap();
    CHECK_EQ(keys.value("version").toString(), QStringLiteral("1.0.0"));
    const QAbstractItemModel& apps = *a.manager.apps();
    CHECK_EQ(at(apps, rowOf(apps, "keys_ui", kDefault), "version").toString(), QStringLiteral("2.0.0"));
}

// As the old dialog had it: an installed app's optional packages start
// unticked, and ticking one makes its install bring it.
TEST(an_installed_app_installs_the_optional_packages_ticked_in_its_details) {
    App a;
    a.modules.catalog = {offering(app(kDefault, "chat_ui", "1.0.0", "C"), {"rln"}),
                         catalogRow(kDefault, "rln", "1.0.0", "R", {}, kHere, "core")};
    a.modules.addInstalled("chat_ui", "1.0.0", "C");
    a.manager.load();
    a.manager.showDetails("chat_ui", kDefault);
    CHECK(!a.manager.install("chat_ui", kDefault));
    CHECK(a.basecamp.asked.isEmpty());

    a.manager.setOptional("rln", true);
    CHECK(a.manager.install("chat_ui", kDefault));
    CHECK_EQ(a.lastIntent(), QStringLiteral("basecamp.packages.confirm_install"));
    CHECK_EQ(a.lastParams().value("optional").toMap(), (QVariantMap{{"rln", true}}));
}

// A version picked in its details for a package it needs installs too: the
// pick used to change only that package's row, and nothing asked Basecamp.
TEST(an_installed_app_installs_the_version_picked_for_a_package_it_needs) {
    App a;
    a.modules.catalog = {app(kDefault, "storage_ui", "1.0.0", "U", {dep("storage")}),
                         withOlderVersion(catalogRow(kDefault, "storage", "2.0.0", "S2", {}, kHere, "core"),
                                          "1.0.0", "S1")};
    a.modules.addInstalled("storage_ui", "1.0.0", "U");
    a.modules.addInstalled("storage", "2.0.0", "S2");
    a.manager.load();
    a.manager.showDetails("storage_ui", kDefault);
    CHECK(!a.manager.install("storage_ui", kDefault));
    CHECK(a.basecamp.asked.isEmpty());

    a.manager.selectVersion("storage", kDefault, "1.0.0");
    CHECK(a.manager.install("storage_ui", kDefault));
    CHECK_EQ(a.lastIntent(), QStringLiteral("basecamp.packages.confirm_install"));
    CHECK_EQ(a.lastParams().value("versions").toMap(), (QVariantMap{{"storage", "1.0.0"}}));
}

// ── Who signed it ────────────────────────────────────────────────────────

namespace {

// A made-up Ed25519 key, spelled the way liblgx spells it.
const QString kAcmeDid = QStringLiteral(
    "did:jwk:eyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6IkFRSURCQVVHQndnSkNnc01EUTRQRUJFU0V4"
    "UVZGaGNZR1JvYkhCMGVIeUEifQ");

const QVariantMap kLogosKey{{"did", logos::trust::logosDid()}, {"displayName", "Logos"}};

// `row` with its version `index` signed by `did`, as `signer` names itself.
QVariantMap signedAt(QVariantMap row, int index, const QString& did, const QString& signer)
{
    QVariantList versions = row["versions"].toList();
    QVariantMap v = versions[index].toMap();
    v["signature"] = QVariantMap{{"did", did}, {"signer", QVariantMap{{"name", signer}}}};
    versions[index] = v;
    row["versions"] = versions;
    return row;
}

// The wallet, by Logos, needing the signer, its newest by Acme and the one
// before by Logos, and keys, on disk and signed by nobody.
void addWallet(App& a)
{
    const QVariantMap signer = withOlderVersion(
        catalogRow(kDefault, "signer", "2.0.0", "S2", {}, kHere, "core"), "1.0.0", "S1");
    a.modules.catalog = {
        signedAt(app(kDefault, "wallet_ui", "1.0.0", "W", {dep("signer"), dep("keys")}), 0,
                 logos::trust::logosDid(), "Logos"),
        signedAt(signedAt(signer, 0, kAcmeDid, "Acme"), 1, logos::trust::logosDid(), "Logos"),
        catalogRow(kDefault, "keys", "1.0.0", "K", {}, kHere, "core")};
    a.modules.addInstalled("keys", "1.0.0", "K");
}

// The open details' `trust` of what the app brings.
QVariantMap trustOf(const App& a, const QString& name)
{
    for (const QVariant& v : a.manager.details().value("packages").toList())
        if (v.toMap().value("name").toString() == name) return v.toMap().value("trust").toMap();
    return {};
}

QString statusOf(const QVariantMap& verdict)
{
    return verdict.value("status").toString();
}

}  // namespace

// As Basecamp's install dialog judges them: what installs by the release
// picked, what stays on disk by its copy.
TEST(details_say_who_signed_the_app_and_each_package_it_brings) {
    App a;
    a.modules.trustedKeys = {kLogosKey};
    addWallet(a);
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    const QVariantMap own = a.manager.details().value("trust").toMap();
    CHECK_EQ(statusOf(own), QStringLiteral("trusted"));
    CHECK_EQ(own.value("publisher").toString(), QStringLiteral("Logos"));
    CHECK_EQ(statusOf(trustOf(a, "wallet_ui")), QStringLiteral("trusted"));
    CHECK_EQ(statusOf(trustOf(a, "signer")), QStringLiteral("untrusted"));
    CHECK_EQ(trustOf(a, "signer").value("publisher").toString(), QStringLiteral("Acme"));
    CHECK_EQ(statusOf(trustOf(a, "keys")), QStringLiteral("unsigned"));
    CHECK(trustOf(a, "keys").value("installed").toBool());

    a.manager.selectVersion("signer", kDefault, "1.0.0");
    CHECK_EQ(statusOf(trustOf(a, "signer")), QStringLiteral("trusted"));
    CHECK_EQ(trustOf(a, "signer").value("publisher").toString(), QStringLiteral("Logos"));
}

// An installed app's details say who signed it, not that it is there: its
// row says that.
TEST(an_installed_apps_details_say_who_signed_its_copy) {
    App a;
    a.modules.trustedKeys = {kLogosKey};
    a.modules.catalog = {signedAt(app(kDefault, "wallet_ui", "1.0.0", "W"), 0, logos::trust::logosDid(), "Logos")};
    a.modules.addInstalled("wallet_ui", "1.0.0", "W");
    a.modules.installed["wallet_ui"].insert("signerDid", logos::trust::logosDid());
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    const QVariantMap own = a.manager.details().value("trust").toMap();
    CHECK_EQ(statusOf(own), QStringLiteral("trusted"));
    CHECK(!own.contains("installed"));
    CHECK(trustOf(a, "wallet_ui").value("installed").toBool());
}

// A keyring that can't be read trusts nobody, as in Basecamp's dialog.
TEST(without_the_keyring_the_details_trust_no_signer) {
    App a;
    a.modules.trustedKeys = {kLogosKey};
    a.modules.failing << "listTrustedKeys";
    addWallet(a);
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK_EQ(statusOf(a.manager.details().value("trust").toMap()), QStringLiteral("unknown"));
    CHECK_EQ(statusOf(trustOf(a, "signer")), QStringLiteral("unknown"));
    CHECK_EQ(statusOf(trustOf(a, "keys")), QStringLiteral("unsigned"));
}

// Until the keyring answers, nothing is said of who signed what: not
// "couldn't check", which only a keyring that can't be read means.
TEST(the_details_say_who_signed_what_once_the_keyring_answers) {
    App a;
    a.modules.trustedKeys = {kLogosKey};
    a.modules.keyringWaits = true;
    addWallet(a);
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK(!a.manager.details().contains("trust"));
    for (const QVariant& v : a.manager.details().value("packages").toList())
        CHECK(!v.toMap().contains("trust"));
    CHECK_EQ(a.modules.keyringAnswers.size(), 1);
    a.modules.keyringAnswers.takeFirst()();
    CHECK_EQ(statusOf(a.manager.details().value("trust").toMap()), QStringLiteral("trusted"));
}

// Trusting a publisher comes with an install: once what is installed
// changes, the details read the keyring again.
TEST(the_details_read_the_keyring_again_when_what_is_installed_changes) {
    App a;
    a.modules.trustedKeys = {kLogosKey};
    addWallet(a);
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK_EQ(statusOf(trustOf(a, "signer")), QStringLiteral("untrusted"));
    a.modules.trustedKeys.append(QVariantMap{{"did", kAcmeDid}, {"displayName", "Acme"}});
    a.manager.onPackagesChanged();
    SPIN(20);
    CHECK_EQ(statusOf(trustOf(a, "signer")), QStringLiteral("trusted"));
    CHECK_EQ(trustOf(a, "signer").value("publisher").toString(), QStringLiteral("Acme"));
}

// ── Reload and events ────────────────────────────────────────────────────

TEST(reload_fetches_every_repository_again) {
    App a;
    a.manager.load();
    CHECK(!a.modules.calls.contains("refreshCatalog"));
    a.manager.refresh();
    CHECK(a.modules.calls.contains("refreshCatalog"));
}

TEST(the_download_notice_reads_the_downloader) {
    App a;
    a.modules.downloadSource = "logos";
    a.modules.storage = {{"state", "starting"}};
    QSignalSpy changed(&a.manager, &AppManager::downloadStateChanged);
    a.manager.load();
    CHECK_EQ(a.manager.downloadSource(), QStringLiteral("logos"));
    CHECK_EQ(a.manager.storageState(), QStringLiteral("starting"));
    a.manager.onStorageStateChanged("running", {});
    CHECK_EQ(a.manager.storageState(), QStringLiteral("running"));
    CHECK(changed.count() > 0);
}

// ── Versions ─────────────────────────────────────────────────────────────

// The view names the version it showed: a list that moved since picks it
// still, and one no longer listed picks nothing.
TEST(a_version_is_picked_by_its_name) {
    App a;
    a.modules.catalog = {withOlderVersion(app(kDefault, "wallet_ui", "2.0.0", "W2"), "1.0.0", "W1")};
    a.manager.load();
    a.manager.showDetails("wallet_ui", kDefault);
    // A newer release came in after the view drew its picker.
    a.modules.catalog = {withOlderVersion(withOlderVersion(app(kDefault, "wallet_ui", "3.0.0", "W3"),
                                                           "2.0.0", "W2"), "1.0.0", "W1")};
    a.manager.refresh();
    a.manager.selectVersion("wallet_ui", kDefault, "2.0.0");
    CHECK_EQ(a.manager.details().value("version").toString(), QStringLiteral("2.0.0"));
    a.manager.selectVersion("wallet_ui", kDefault, "0.9.0");
    CHECK_EQ(a.manager.details().value("version").toString(), QStringLiteral("2.0.0"));
}

// The app's own version picked in its details goes with them: opened again,
// or once another app's open, they show what its tile does. The pick stayed
// on its row, and came back.
TEST(the_apps_own_version_picked_goes_with_its_details) {
    App a;
    a.modules.catalog = {withOlderVersion(app(kDefault, "wallet_ui", "2.0.0", "W2"), "1.0.0", "W1"),
                         app(kDefault, "chat_ui", "1.0.0", "C")};
    a.modules.addInstalled("wallet_ui", "1.0.0", "W1");
    a.manager.load();
    const auto shown = [&a]() { return a.manager.details().value("version").toString(); };
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK_EQ(shown(), QStringLiteral("2.0.0"));
    a.manager.selectVersion("wallet_ui", kDefault, "1.0.0");
    CHECK_EQ(shown(), QStringLiteral("1.0.0"));
    a.manager.closeDetails();
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK_EQ(shown(), QStringLiteral("2.0.0"));

    a.manager.selectVersion("wallet_ui", kDefault, "1.0.0");
    a.manager.showDetails("chat_ui", kDefault);
    a.manager.showDetails("wallet_ui", kDefault);
    CHECK_EQ(shown(), QStringLiteral("2.0.0"));
}

// ── Loading ──────────────────────────────────────────────────────────────

// A read that failed is not an empty catalog: it says so, and the next good
// one clears it.
TEST(a_failed_load_says_so_until_one_reads_everything) {
    App a;
    a.modules.catalog = {app(kDefault, "wallet_ui", "1.0.0", "W")};
    a.modules.failing << "getCatalog";
    QSignalSpy failed(&a.manager, &AppManager::loadFailed);
    a.manager.load();
    CHECK(!a.manager.loaded());
    CHECK_EQ(a.manager.loadError(), QStringLiteral("the catalog"));
    CHECK_EQ(failed.count(), 1);
    CHECK_EQ(failed.at(0).at(0).toString(), QStringLiteral("the catalog"));
    a.modules.failing.clear();
    a.manager.refresh();
    CHECK(a.manager.loaded());
    CHECK_EQ(a.manager.loadError(), QString());
    CHECK_EQ(a.lines(), (QStringList{"§Logos 1", "wallet_ui"}));
    // A reload that fails keeps the list, and says so again.
    a.modules.failing << "getCatalog";
    a.manager.refresh();
    a.manager.refresh();
    CHECK_EQ(failed.count(), 3);
    CHECK(a.manager.loaded());
    CHECK_EQ(a.lines(), (QStringList{"§Logos 1", "wallet_ui"}));
}

CHECK_MAIN()
