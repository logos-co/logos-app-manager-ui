#include "AppManager.h"

#include "AppSections.h"

#include <logos/installer/CatalogClient.h>
#include <logos/installer/InstallProgress.h>
#include <logos/installer/OnlineWatch.h>
#include <logos/installer/PackageFilter.h>
#include <logos/installer/PackageModel.h>
#include <logos/installer/PackageRows.h>
#include <logos/installer/RowState.h>

#include <QTimer>

#include <utility>

namespace appmanager {

using namespace logos::installer;

namespace {

const QString kAll = QStringLiteral("All");
const QString kPackagesInstall = QStringLiteral("packages.install");
const QString kAppsSearch = QStringLiteral("apps.search");
const QString kLocal = QStringLiteral("local");
const QString kShell = QStringLiteral("main_ui");

QString str(const QVariantMap& row, const char* key)
{
    return row.value(QLatin1String(key)).toString();
}

bool installableHere(const QVariantMap& row)
{
    return row.value(QStringLiteral("isVariantAvailable")).toBool()
        && row.value(QStringLiteral("isSourceAvailable"), true).toBool();
}

}  // namespace

AppManager::AppManager(QObject* parent)
    : QObject(parent)
    , m_model(new PackageModel(this))
    , m_progress(new InstallProgress(this))
    , m_filter(new PackageFilter(this))
    , m_sections(new AppSections(this))
    , m_online(new OnlineWatch(this))
    , m_icons(new IconFetcher(m_model, this))
{
    // An app stands for the modules it brings, as Basecamp's tiles always had it.
    m_model->setStatusIncludesDependencies(true);
    m_model->setProgress(m_progress);

    m_filter->setSourceModel(m_model);
    m_filter->setTypeScope({QStringLiteral("ui_qml")});
    m_filter->setExcludedNames({kShell});
    m_filter->setSortRoleByName(QStringLiteral("displayName"));
    m_sections->setSourceModel(m_filter);

    connect(m_filter, &PackageFilter::categoriesChanged, this, [this] {
        QStringList categories{kAll};
        categories << m_filter->categories();
        if (categories == m_categories) return;
        m_categories = categories;
        emit categoriesChanged();
    });
    connect(m_sections, &AppSections::countsChanged, this, &AppManager::countsChanged);
    connect(m_online, &OnlineWatch::onlineChanged, this, &AppManager::onlineChanged);
    connect(m_model, &PackageModel::hostVariantChanged, this, &AppManager::hostVariantChanged);

    // The open app's details follow its row and the rows of what it brings.
    connect(m_model, &QAbstractItemModel::dataChanged, this, [this] {
        if (!m_detailsName.isEmpty()) refreshDetails();
    });
    auto follow = [this] {
        if (!m_detailsName.isEmpty()) refreshDetails();
    };
    connect(m_model, &QAbstractItemModel::rowsInserted, this, follow);
    connect(m_model, &QAbstractItemModel::rowsRemoved, this, follow);
    connect(m_model, &QAbstractItemModel::modelReset, this, follow);
}

AppManager::~AppManager() = default;

void AppManager::setModules(PackageModules* packages, InstallModules* installs, Consent* consent)
{
    if (m_catalog) return;
    m_catalog = new CatalogClient(packages, m_model, this);
    if (m_debounceMs >= 0) m_catalog->setDebounceInterval(m_debounceMs);
    m_installer = new Installer(installs, consent, m_progress, this);
    m_installer->setPackages(m_model);
    if (m_clearDelayMs >= 0) m_installer->setClearDelay(m_clearDelayMs);

    connect(m_catalog, &CatalogClient::loadingChanged, this, &AppManager::loadingChanged);
    connect(m_catalog, &CatalogClient::loaded, this, &AppManager::takeDeliveries);
    connect(m_catalog, &CatalogClient::repositoriesChanged, this, [this] {
        applyRepositories();
        emit repositoriesChanged();
    });
    connect(m_catalog, &CatalogClient::downloadSourceChanged, this, &AppManager::downloadStateChanged);
    connect(m_catalog, &CatalogClient::storageStateChanged, this, &AppManager::downloadStateChanged);
    connect(m_installer, &Installer::finished, this,
            [this](const QString& name, Installer::Outcome outcome, const QString& error) {
                emit finished(name, static_cast<int>(outcome), error);
            });
}

void AppManager::setIconFetch(IconFetcher::Fetch fetch)
{
    m_icons->setFetch(std::move(fetch));
}

void AppManager::setIconCacheDirectory(const QString& directory)
{
    m_icons->setCacheDirectory(directory);
}

void AppManager::setDebounceInterval(int ms)
{
    m_debounceMs = ms;
    if (m_catalog) m_catalog->setDebounceInterval(ms);
}

void AppManager::setClearDelay(int ms)
{
    m_clearDelayMs = ms;
    if (m_installer) m_installer->setClearDelay(ms);
}

void AppManager::load()
{
    if (m_catalog) m_catalog->load();
}

void AppManager::refresh()
{
    if (!m_catalog) return;
    m_catalog->refresh();
    m_icons->retry();
}

void AppManager::onPackagesChanged()
{
    if (m_catalog) m_catalog->onPackagesChanged();
}

void AppManager::onCatalogChanged()
{
    if (m_catalog) m_catalog->onCatalogChanged();
}

void AppManager::onStorageStateChanged(const QString& state, const QString& error)
{
    if (m_catalog) m_catalog->onStorageStateChanged(state, error);
}

void AppManager::onSubscriptionArmed()
{
    if (m_catalog) m_catalog->onSubscriptionArmed();
}

void AppManager::onDownloadProgress(const QString& name, quint64 received, quint64 total,
                                    const QString& transport)
{
    m_progress->setDownloadProgress(name, received, total, transport);
}

QAbstractItemModel* AppManager::apps() const
{
    return m_sections;
}

QVariantMap AppManager::appRoleIds() const
{
    QVariantMap ids;
    const QHash<int, QByteArray> names = m_sections->roleNames();
    for (auto it = names.cbegin(); it != names.cend(); ++it)
        ids.insert(QString::fromLatin1(it.value()), it.key());
    return ids;
}

void AppManager::setSearchText(const QString& text)
{
    if (text == m_filter->searchText()) return;
    m_filter->setSearchText(text);
    emit filtersChanged();
}

QString AppManager::searchText() const
{
    return m_filter->searchText();
}

void AppManager::setCategory(const QString& category)
{
    const QString c = category == kAll ? QString() : category;
    if (c == m_category) return;
    m_category = c;
    m_filter->setCategoryFilter(c);
    emit filtersChanged();
}

QString AppManager::category() const
{
    return m_category.isEmpty() ? kAll : m_category;
}

void AppManager::setInstallState(int state)
{
    if (state == m_filter->installStateFilter()) return;
    m_filter->setInstallStateFilter(state);
    emit filtersChanged();
}

int AppManager::installState() const
{
    return m_filter->installStateFilter();
}

void AppManager::setShowUnavailable(bool show)
{
    if (show == m_filter->showUnavailable()) return;
    m_filter->setShowUnavailable(show);
    emit filtersChanged();
}

bool AppManager::showUnavailable() const
{
    return m_filter->showUnavailable();
}

QStringList AppManager::categories() const
{
    return m_categories;
}

int AppManager::visibleCount() const
{
    return m_sections->appCount();
}

int AppManager::localCount() const
{
    return m_sections->countOf(kLocal);
}

bool AppManager::loading() const
{
    return m_catalog && m_catalog->isLoading();
}

bool AppManager::online() const
{
    return m_online->isOnline();
}

QString AppManager::downloadSource() const
{
    return m_catalog ? m_catalog->downloadSource() : QString();
}

QString AppManager::storageState() const
{
    return m_catalog ? m_catalog->storageState() : QString();
}

QString AppManager::hostVariant() const
{
    return m_model->hostVariant();
}

int AppManager::repositoryCount() const
{
    return m_catalog ? m_catalog->repositoryCount() : 0;
}

bool AppManager::install(const QString& name, const QString& repositoryUrl)
{
    if (!m_installer || name == kShell) return false;
    const int row = rowOf(name, repositoryUrl);
    if (row < 0) return false;
    const QVariantMap r = m_model->rowAt(row);
    const QString repo = str(r, "repositoryUrl");
    // Installed from a file: no repository to install from.
    if (repo.isEmpty()) return false;
    const auto status = static_cast<InstallStatus>(r.value(QStringLiteral("installStatus")).toInt());
    if (status == InstallStatus::Installing) return false;

    // The app's own action, without what its dependencies add to its badge.
    const QString version = str(r, "version");
    const QString hash = str(r, "hash");
    const QString installedVersion = str(r, "installedVersion");
    const QString installedHash = str(r, "installedHash");
    const bool onDisk = isInstalledRow(r);
    const bool canInstall = installableHere(r);
    const InstallStatus own = installStatusOf(onDisk, installedVersion, installedHash, version, hash);
    const QVariantMap choices = choicesFor(name, repo);
    switch (resolveRowAction(onDisk, canInstall, own, installedVersion, installedHash, version, hash)) {
    case RowAction::Install:
        m_installer->install(name, version, repo, choices);
        return true;
    case RowAction::Upgrade:
        m_installer->upgrade(name, version, 0, repo, choices);
        return true;
    case RowAction::Downgrade:
        m_installer->upgrade(name, version, 1, repo, choices);
        return true;
    case RowAction::Reinstall:
        m_installer->upgrade(name, version, 2, repo, choices);
        return true;
    case RowAction::NoOp:
        // Current itself: an install brings what it is missing, what its
        // dependencies need, and the optional packages ticked in its details.
        if (!canInstall || (status == InstallStatus::Installed && !optionalChangesPending(name, repo)))
            return false;
        m_installer->install(name, version, repo, choices);
        return true;
    default:
        return false;
    }
}

bool AppManager::showByName(const QString& name)
{
    return openByName(name, false);
}

bool AppManager::openByName(const QString& name, bool andInstall)
{
    if (name.isEmpty() || name == kShell || !m_catalog) return false;
    for (const QString& key : m_catalog->sourceOrder()) {
        const int row = key == kLocal ? -1 : m_model->rowOf(name, key);
        // Apps only, as the page lists them.
        if (row < 0 || str(m_model->rowAt(row), "type") != QLatin1String("ui_qml")) continue;
        // The person sees what was asked for, installed already or not.
        showDetails(name, key);
        if (andInstall) install(name, key);
        return true;
    }
    return false;
}

bool AppManager::uninstall(const QString& name, const QString& repositoryUrl)
{
    if (!m_installer || name == kShell) return false;
    const int row = rowOf(name, repositoryUrl);
    if (row < 0) return false;
    const QVariantMap r = m_model->rowAt(row);
    const auto status = static_cast<InstallStatus>(r.value(QStringLiteral("installStatus")).toInt());
    if (str(r, "installType") != QLatin1String("user") || !isInstalledRow(r)
        || status == InstallStatus::Installing)
        return false;
    m_installer->uninstall({name});
    return true;
}

bool AppManager::provides(const QString& intent)
{
    return intent == kPackagesInstall || intent == kAppsSearch;
}

bool AppManager::deliver(const QString& intent, const QVariantMap& params, const QString& requester,
                         Respond respond)
{
    if (!provides(intent) || !respond) return false;
    if (intent == kAppsSearch) {
        closeDetails();
        emit searchRequested(params.value(QStringLiteral("query")).toString());
        respond(true, {});
        return true;
    }
    const QString name = params.value(QStringLiteral("name")).toString();
    // Basecamp's own request is the person's click there. Another app's only
    // shows the app: its install is the person's to ask for, here.
    const bool andInstall = requester == kShell;
    if (m_catalog && m_catalog->hasLoaded() && !m_catalog->isLoading()) {
        const bool taken = openByName(name, andInstall);
        respond(taken, taken ? QString() : QStringLiteral("failed"));
        return true;
    }
    const int id = ++m_nextDelivery;
    m_deliveries.append({id, name, andInstall, std::move(respond)});
    QTimer::singleShot(m_deliveryTimeoutMs, this, [this, id] {
        for (int i = 0; i < m_deliveries.size(); ++i) {
            if (m_deliveries.at(i).id != id) continue;
            const Respond respond = m_deliveries.takeAt(i).respond;
            respond(false, QStringLiteral("failed"));
            return;
        }
    });
    return true;
}

void AppManager::takeDeliveries()
{
    const QList<Delivery> waiting = std::exchange(m_deliveries, {});
    for (const Delivery& d : waiting) {
        const bool taken = openByName(d.name, d.install);
        d.respond(taken, taken ? QString() : QStringLiteral("failed"));
    }
}

void AppManager::showDetails(const QString& name, const QString& repositoryUrl)
{
    if (name != m_detailsName || repositoryUrl != m_detailsRepositoryUrl) forgetPicks();
    m_detailsName = name;
    m_detailsRepositoryUrl = repositoryUrl;
    refreshDetails();
}

void AppManager::closeDetails()
{
    forgetPicks();
    m_detailsName.clear();
    m_detailsRepositoryUrl.clear();
    refreshDetails();
}

void AppManager::selectVersion(const QString& name, const QString& repositoryUrl, int versionIndex)
{
    const int row = rowOf(name, repositoryUrl);
    if (row < 0) return;
    // The app's own version is its row's, as its tile shows it; another
    // package's is only the details'.
    if (name == m_detailsName || m_detailsName.isEmpty()) {
        m_model->selectVersion(row, versionIndex);
        return;
    }
    const QString version = m_model->rowAt(row).value(QStringLiteral("availableVersions")).toList()
                                .value(versionIndex).toMap().value(QStringLiteral("version")).toString();
    if (version.isEmpty() || m_versions.value(name).toString() == version) return;
    m_versions.insert(name, version);
    refreshDetails();
}

void AppManager::setOptional(const QString& name, bool selected)
{
    if (m_detailsName.isEmpty() || m_optional.value(name, !selected).toBool() == selected) return;
    m_optional.insert(name, selected);
    refreshDetails();
}

QVariantMap AppManager::choicesFor(const QString& name, const QString& repositoryUrl) const
{
    if (name != m_detailsName || repositoryUrl != str(m_details, "repositoryUrl")) return {};
    QVariantMap versions, optional;
    for (const QVariant& v : m_details.value(QStringLiteral("packages")).toList()) {
        const QVariantMap p = v.toMap();
        if (p.value(QStringLiteral("subject")).toBool()) continue;
        // Ticked or not; what comes with one isn't a choice.
        if (p.contains(QStringLiteral("selected")))
            optional.insert(str(p, "name"), p.value(QStringLiteral("selected")).toBool());
        // What isn't picked, Basecamp's resolver chooses as the details did.
        if (p.value(QStringLiteral("picked")).toBool())
            versions.insert(str(p, "name"), str(p, "version"));
    }
    QVariantMap choices;
    if (!versions.isEmpty()) choices.insert(QStringLiteral("versions"), versions);
    if (!optional.isEmpty()) choices.insert(QStringLiteral("optional"), optional);
    return choices;
}

void AppManager::forgetPicks()
{
    m_optional.clear();
    m_versions.clear();
}

bool AppManager::optionalChangesPending(const QString& name, const QString& repositoryUrl) const
{
    if (name != m_detailsName || repositoryUrl != str(m_details, "repositoryUrl")) return false;
    for (const QVariant& v : m_details.value(QStringLiteral("packages")).toList()) {
        const QVariantMap p = v.toMap();
        // Ticked, or coming with one that is.
        if (!p.value(QStringLiteral("optional")).toBool()
            || (p.contains(QStringLiteral("selected")) && !p.value(QStringLiteral("selected")).toBool()))
            continue;
        switch (static_cast<RowAction>(p.value(QStringLiteral("rowAction")).toInt())) {
        case RowAction::Install:
        case RowAction::Upgrade:
        case RowAction::Downgrade:
        case RowAction::Reinstall:
        case RowAction::Retry:
            return true;
        default:
            break;
        }
    }
    return false;
}

int AppManager::rowOf(const QString& name, const QString& repositoryUrl) const
{
    if (name.isEmpty()) return -1;
    if (!repositoryUrl.isEmpty()) return m_model->rowOf(name, repositoryUrl);
    // A local app has no repository; the model's rowOf() reads none as any.
    for (int r = 0; r < m_model->rowCount(); ++r) {
        const QModelIndex at = m_model->index(r);
        if (at.data(PackageModel::NameRole).toString() == name
            && at.data(PackageModel::RepositoryUrlRole).toString().isEmpty())
            return r;
    }
    return -1;
}

void AppManager::applyRepositories()
{
    m_filter->setSourceOrder(m_catalog->sourceOrder());
    m_sections->setTitles(m_catalog->repositoryLabels());
    QStringList hidden;
    for (const QVariant& v : m_catalog->repositories()) {
        const QVariantMap r = v.toMap();
        if (!r.value(QStringLiteral("enabled"), true).toBool()) hidden << str(r, "url");
    }
    m_sections->setHidden(hidden);
}

void AppManager::refreshDetails()
{
    QVariantMap details;
    const int row = rowOf(m_detailsName, m_detailsRepositoryUrl);
    if (row >= 0) {
        details = m_model->rowAt(row);
        details.insert(QStringLiteral("packages"), m_model->packagesBroughtBy(row, m_optional, m_versions));
    } else if (!m_detailsName.isEmpty()) {
        // Gone from every list: closed for good, not reopened if it comes back.
        forgetPicks();
        m_detailsName.clear();
        m_detailsRepositoryUrl.clear();
    }
    if (details == m_details) return;
    m_details = details;
    emit detailsChanged();
}

}  // namespace appmanager
