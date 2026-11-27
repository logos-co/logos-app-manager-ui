#pragma once

#include <logos/installer/IconFetcher.h>
#include <logos/installer/Installer.h>

#include <QList>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantMap>

#include <functional>

class QAbstractItemModel;

namespace logos::installer {
class CatalogClient;
class Consent;
class InstallModules;
class InstallProgress;
class OnlineWatch;
class PackageFilter;
class PackageModel;
class PackageModules;
}  // namespace logos::installer

namespace appmanager {

class AppSections;

// What the App Manager's page shows and does, on basecamp-installer-common:
// every repository's apps and the ones installed from a file, filtered as
// the page asks and listed by section; an app's details; and the installs,
// upgrades and uninstalls the person asks for, each of which Basecamp
// approves before anything happens. No module calls of its own: the backend
// hands it the modules it reads and installs through, and Basecamp's consent.
class AppManager : public QObject {
    Q_OBJECT

public:
    explicit AppManager(QObject* parent = nullptr);
    ~AppManager() override;

    // Once, before load().
    void setModules(logos::installer::PackageModules* packages,
                    logos::installer::InstallModules* installs,
                    logos::installer::Consent* consent);
    // For tests: how icons are fetched, how soon a burst of events reloads,
    // and how long a finished install's tile says Installed.
    void setIconFetch(logos::installer::IconFetcher::Fetch fetch);
    void setIconCacheDirectory(const QString& directory);
    void setDebounceInterval(int ms);
    void setClearDelay(int ms);

    // The first load, and Reload: every repository fetched again.
    void load();
    void refresh();

    // The modules' events, as the backend receives them.
    void onPackagesChanged();
    void onCatalogChanged();
    void onStorageStateChanged(const QString& state, const QString& error);
    void onSubscriptionArmed();
    void onDownloadProgress(const QString& name, quint64 received, quint64 total,
                            const QString& transport);

    // The list: AppSections over the filtered apps.
    QAbstractItemModel* apps() const;
    QVariantMap appRoleIds() const;

    void setSearchText(const QString& text);
    QString searchText() const;
    // "" or "All": every category.
    void setCategory(const QString& category);
    QString category() const;
    // logos::installer::PackageFilter::InstallState.
    void setInstallState(int state);
    int installState() const;
    void setShowUnavailable(bool show);
    bool showUnavailable() const;
    // "All", then each category among the apps.
    QStringList categories() const;
    // The apps listed, and those of them no repository publishes.
    int visibleCount() const;
    int localCount() const;

    bool loading() const;
    // The catalog has been read once; what the last read couldn't read, or "".
    bool loaded() const;
    QString loadError() const;
    bool online() const;
    QString downloadSource() const;
    QString storageState() const;
    QString hostVariant() const;
    int repositoryCount() const;

    // What the person asked for. Each asks Basecamp first; how it ended
    // comes as finished(). False when there is no such app or nothing to do.
    // install() does what the app's row offers: install it, upgrade,
    // downgrade or reinstall it to the version it shows, or bring in what
    // it is missing.
    // Only an app (ui_qml, not the shell) installs, uninstalls or opens its
    // details, and installs or opens only from a repository that is enabled.
    bool install(const QString& name, const QString& repositoryUrl);
    bool uninstall(const QString& name, const QString& repositoryUrl);

    // An intent this app provides, delivered through intents_module:
    // apps.install {name, repositoryUrl}, answered through `respond` once
    // taken on (an app just started waits for its catalog): its details, from
    // `repositoryUrl` when it has it as an app (the one it was picked from),
    // else the first repository that does, and for Basecamp's own request
    // (`requester` main_ui), the person's click there, install() too;
    // apps.search {query}, the page searching for it. False for an intent it
    // doesn't provide.
    using Respond = std::function<void(bool ok, const QString& error)>;
    static bool provides(const QString& intent);
    bool deliver(const QString& intent, const QVariantMap& params, const QString& requester,
                 Respond respond);
    // How long a delivery waits for the catalog.
    void setDeliveryTimeout(int ms) { m_deliveryTimeoutMs = ms; }

    void showDetails(const QString& name, const QString& repositoryUrl);
    void closeDetails();
    // Every role of the open app's row, by name, and `packages`: what it
    // brings (PackageModel::packagesBroughtBy()), an optional one's `selected`
    // included. Empty with none open.
    QVariantMap details() const { return m_details; }
    // The version of the open app (its row's), or of a package it brings, and
    // whether an optional package comes with it: they go to Basecamp with the
    // open app's install, which plans with them. Forgotten when the details
    // close.
    void selectVersion(const QString& name, const QString& repositoryUrl, const QString& version);
    void setOptional(const QString& name, bool selected);

signals:
    void loadingChanged();
    void loadStateChanged();
    // Every read that failed, `error` as loadError() has it.
    void loadFailed(const QString& error);
    void onlineChanged();
    void downloadStateChanged();
    void hostVariantChanged();
    void repositoriesChanged();
    void categoriesChanged();
    void countsChanged();
    void filtersChanged();
    void detailsChanged();
    // `outcome`: logos::installer::Installer::Outcome as an int.
    void finished(const QString& name, int outcome, const QString& error);
    // The page is asked to search for `query`, in its own field.
    void searchRequested(const QString& query);

private:
    struct Delivery {
        int id = 0;
        QString name;
        QString repositoryUrl;
        bool install = false;
        Respond respond;
    };

    int rowOf(const QString& name, const QString& repositoryUrl) const;
    // `name`'s details, from `repositoryUrl` when it has it as an app, else
    // the first repository that does, and with `install`, install() too.
    bool openByName(const QString& name, bool install, const QString& repositoryUrl = {});
    // An app: ui_qml, and not the shell.
    static bool isApp(const QVariantMap& row);
    // From a repository that is enabled, or from a file.
    bool fromEnabledSource(const QVariantMap& row) const;
    void takeDeliveries();
    void applyRepositories();
    void refreshDetails();
    // The open details' picks, for its install ({versions, optional}), and
    // putting them back as they were.
    QVariantMap choicesFor(const QString& name, const QString& repositoryUrl) const;
    void forgetPicks();
    // Its open details change something: an optional package ticked, or a
    // version picked for one it needs.
    bool changesPending(const QString& name, const QString& repositoryUrl) const;

    logos::installer::PackageModel* m_model;
    logos::installer::InstallProgress* m_progress;
    logos::installer::PackageFilter* m_filter;
    AppSections* m_sections;
    logos::installer::OnlineWatch* m_online;
    logos::installer::IconFetcher* m_icons;
    logos::installer::CatalogClient* m_catalog = nullptr;
    logos::installer::Installer* m_installer = nullptr;
    int m_debounceMs = -1;
    int m_clearDelayMs = -1;

    QSet<QString> m_disabledRepositories;
    QString m_category;
    QStringList m_categories{QStringLiteral("All")};
    QList<Delivery> m_deliveries;
    int m_nextDelivery = 0;
    int m_deliveryTimeoutMs = 8000;

    QString m_detailsName;
    QString m_detailsRepositoryUrl;
    QVariantMap m_details;
    // The open details' picks: optional packages ticked (name -> bool), and
    // the versions of the packages it brings (name -> version).
    QVariantMap m_optional;
    QVariantMap m_versions;
};

}  // namespace appmanager
