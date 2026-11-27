#include "AppManager.h"

#include "AppSections.h"

#include <logos/installer/CatalogClient.h>
#include <logos/installer/InstallProgress.h>
#include <logos/installer/OnlineWatch.h>
#include <logos/installer/PackageFilter.h>
#include <logos/installer/PackageModel.h>
#include <logos/installer/PackageModules.h>
#include <logos/installer/PackageRows.h>
#include <logos/installer/PackageTrust.h>
#include <logos/installer/RowState.h>

#include <QPointer>
#include <QTimer>

#include <memory>
#include <utility>

namespace appmanager {

using namespace logos::installer;

namespace {

const QString kAll = QStringLiteral("All");
const QString kAppsInstall = QStringLiteral("apps.install");
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

// What a resolveFlatDependencies() answer says isn't installed. Not what only
// an optional dependency asks for: Basecamp opens the app without it.
QStringList missingOf(const QVariantList& dependencies)
{
    QStringList missing;
    for (const QVariant& v : dependencies) {
        const QVariantMap d = v.toMap();
        if (str(d, "status") == QLatin1String("not_installed")
            && !d.value(QStringLiteral("optional")).toBool())
            missing << str(d, "name");
    }
    return missing;
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

    // The open app's details follow its row and the rows of what it brings;
    // the counts, whether a row is an app the list could show.
    connect(m_model, &QAbstractItemModel::dataChanged, this,
            [this](const QModelIndex&, const QModelIndex&, const QList<int>& roles) {
                if (roles.isEmpty() || roles.contains(PackageModel::IsInstalledRole)
                    || roles.contains(PackageModel::HasInstallableVersionRole))
                    recount();
                if (!m_detailsName.isEmpty()) refreshDetails();
            });
    auto follow = [this] {
        recount();
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
    m_packages = packages;
    m_catalog = new CatalogClient(packages, m_model, this);
    if (m_debounceMs >= 0) m_catalog->setDebounceInterval(m_debounceMs);
    m_installer = new Installer(installs, consent, m_progress, this);
    m_installer->setPackages(m_model);
    if (m_clearDelayMs >= 0) m_installer->setClearDelay(m_clearDelayMs);

    // A load that read everything ends once what its installed apps miss is
    // read too; one that failed ends at once.
    connect(m_catalog, &CatalogClient::loadingChanged, this, [this] {
        if (m_catalog->isLoading()) emit loadingChanged();
    });
    connect(m_catalog, &CatalogClient::loaded, this, &AppManager::loadStateChanged);
    connect(m_catalog, &CatalogClient::loaded, this, &AppManager::readMissingDependencies);
    connect(m_catalog, &CatalogClient::loadFailed, this, [this] {
        emit loadingChanged();
        emit loadStateChanged();
        emit loadFailed(m_catalog->loadError());
    });
    connect(m_catalog, &CatalogClient::repositoriesChanged, this, [this] {
        applyRepositories();
        emit repositoriesChanged();
    });
    connect(m_catalog, &CatalogClient::downloadSourceChanged, this, &AppManager::downloadStateChanged);
    connect(m_catalog, &CatalogClient::storageStateChanged, this, &AppManager::downloadStateChanged);
    connect(m_installer, &Installer::finished, this,
            [this](const QString& name, Installer::Outcome outcome, const QString& error) {
                // Trusting a publisher comes with an install, which may then
                // fail with nothing installed.
                if (!m_detailsName.isEmpty()) readTrustedKeys();
                emit finished(name, static_cast<int>(outcome), error);
            });
    connect(m_installer, &Installer::changeEnded, this, &AppManager::changeEnded);
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
    if (!m_detailsName.isEmpty()) readTrustedKeys();
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

bool AppManager::loading() const
{
    return m_catalog && (m_catalog->isLoading() || m_readingDependencies);
}

bool AppManager::loaded() const
{
    return m_catalog && m_catalog->hasLoaded();
}

QString AppManager::loadError() const
{
    return m_catalog ? m_catalog->loadError() : QString();
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
    if (!isApp(r) || !fromEnabledSource(r)) return false;
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
        // dependencies need, and what its details changed (changesPending()).
        if (!canInstall || (status == InstallStatus::Installed && !changesPending(name, repo)))
            return false;
        m_installer->install(name, version, repo, choices);
        return true;
    default:
        return false;
    }
}

bool AppManager::openByName(const QString& name, bool andInstall, const QString& repositoryUrl)
{
    if (name.isEmpty() || name == kShell || !m_catalog) return false;
    // The repository it was picked from, before the rest.
    QStringList order = m_catalog->sourceOrder();
    if (order.removeAll(repositoryUrl) > 0) order.prepend(repositoryUrl);
    for (const QString& key : order) {
        const int row = key == kLocal ? -1 : m_model->rowOf(name, key);
        // Apps only, as the page lists them.
        if (row < 0 || !isApp(m_model->rowAt(row)) || !fromEnabledSource(m_model->rowAt(row))) continue;
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
    if (!isApp(r) || str(r, "installType") != QLatin1String("user") || !isInstalledRow(r)
        || status == InstallStatus::Installing)
        return false;
    m_installer->uninstall({name});
    return true;
}

bool AppManager::provides(const QString& intent)
{
    return intent == kAppsInstall || intent == kAppsSearch;
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
    // Where it was picked, when the request says: two repositories can list it.
    const QString repositoryUrl = params.value(QStringLiteral("repositoryUrl")).toString();
    // Basecamp's own request is the person's click there. Another app's only
    // shows the app: its install is the person's to ask for, here.
    const bool andInstall = requester == kShell;
    if (m_catalog && m_catalog->hasLoaded() && !loading()) {
        const bool taken = openByName(name, andInstall, repositoryUrl);
        respond(taken, taken ? QString() : QStringLiteral("failed"));
        return true;
    }
    const int id = ++m_nextDelivery;
    m_deliveries.append({id, name, repositoryUrl, andInstall, std::move(respond)});
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
        const bool taken = openByName(d.name, d.install, d.repositoryUrl);
        d.respond(taken, taken ? QString() : QStringLiteral("failed"));
    }
}

void AppManager::showDetails(const QString& name, const QString& repositoryUrl)
{
    const int row = rowOf(name, repositoryUrl);
    if (row < 0 || !isApp(m_model->rowAt(row)) || !fromEnabledSource(m_model->rowAt(row))) return;
    if (name != m_detailsName || repositoryUrl != m_detailsRepositoryUrl) forgetPicks();
    m_detailsName = name;
    m_detailsRepositoryUrl = repositoryUrl;
    refreshDetails();
    readTrustedKeys();
}

void AppManager::closeDetails()
{
    forgetPicks();
    m_detailsName.clear();
    m_detailsRepositoryUrl.clear();
    refreshDetails();
}

void AppManager::selectVersion(const QString& name, const QString& repositoryUrl, const QString& version)
{
    // Of what the open details show: two repositories can list the same name.
    const bool own = !m_detailsName.isEmpty() && name == m_detailsName
        && repositoryUrl == m_detailsRepositoryUrl;
    if (!own && !showsPackage(name, repositoryUrl)) return;
    const int row = rowOf(name, repositoryUrl);
    if (row < 0 || version.isEmpty()) return;
    // By its name, not its place: a list that changed since the view showed
    // it moves the place. One it no longer lists is no pick.
    const QVariantList versions = m_model->rowAt(row).value(QStringLiteral("availableVersions")).toList();
    int index = -1;
    for (int i = 0; i < versions.size() && index < 0; ++i)
        if (versions.at(i).toMap().value(QStringLiteral("version")).toString() == version) index = i;
    if (index < 0) return;
    // The app's own version is its row's, as its tile shows it; another
    // package's is only the details'.
    if (own) {
        m_model->selectVersion(row, index);
        return;
    }
    if (m_versions.value(name).toString() == version) return;
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
    // The app's own version is picked on its row: back to the newest, as its
    // tile shows it.
    const int row = rowOf(m_detailsName, m_detailsRepositoryUrl);
    if (row >= 0) m_model->selectVersion(row, 0);
}

bool AppManager::changesPending(const QString& name, const QString& repositoryUrl) const
{
    if (name != m_detailsName || repositoryUrl != str(m_details, "repositoryUrl")) return false;
    for (const QVariant& v : m_details.value(QStringLiteral("packages")).toList()) {
        const QVariantMap p = v.toMap();
        // An optional one ticked, or coming with one that is; one it needs, at
        // the version picked.
        const bool asked = p.value(QStringLiteral("optional")).toBool()
            ? !(p.contains(QStringLiteral("selected")) && !p.value(QStringLiteral("selected")).toBool())
            : p.value(QStringLiteral("picked")).toBool() && !p.value(QStringLiteral("subject")).toBool();
        if (!asked) continue;
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
    const QVariantMap labels = m_catalog->repositoryLabels();
    m_filter->setSourceOrder(m_catalog->sourceOrder());
    m_sections->setTitles(labels);
    QStringList hidden;
    QStringList unreachable;
    int enabled = 0;
    for (const QVariant& v : m_catalog->repositories()) {
        const QVariantMap r = v.toMap();
        const QString url = str(r, "url");
        if (!r.value(QStringLiteral("enabled"), true).toBool()) {
            hidden << url;
            continue;
        }
        ++enabled;
        if (!str(r, "resolveError").isEmpty()) unreachable << labels.value(url, url).toString();
    }
    m_enabledRepositoryCount = enabled;
    m_unreachableRepositories = unreachable;
    m_disabledRepositories = QSet<QString>(hidden.cbegin(), hidden.cend());
    m_sections->setHidden(hidden);
    recount();
    // Turned off with its details open: they close, as its apps leave the list.
    refreshDetails();
}

void AppManager::readMissingDependencies()
{
    QStringList apps;
    if (m_readDependencies) {
        for (int r = 0; r < m_model->rowCount(); ++r) {
            const QVariantMap row = m_model->rowAt(r);
            const QString name = str(row, "name");
            if (isApp(row) && isInstalledRow(row) && !apps.contains(name)) apps << name;
        }
    }
    const int reading = ++m_dependencyReads;
    m_readingDependencies = true;
    const auto missing = std::make_shared<QHash<QString, QStringList>>();
    // One for each app and one for this loop, so an answer that comes at once
    // can't end it early.
    const auto left = std::make_shared<int>(int(apps.size()) + 1);
    QPointer<AppManager> self(this);
    const auto answered = [self, reading, apps, missing, left] {
        if (--*left > 0 || !self || reading != self->m_dependencyReads) return;
        self->applyMissingDependencies(apps, *missing);
    };
    for (const QString& name : apps) {
        m_readDependencies(name, [name, missing, answered](const QVariantList& dependencies, bool read) {
            // Unread, an app keeps what the last read said.
            if (read) missing->insert(name, missingOf(dependencies));
            answered();
        });
    }
    answered();
}

void AppManager::applyMissingDependencies(const QStringList& apps,
                                          const QHash<QString, QStringList>& missing)
{
    const QSet<QString> marked = m_missingDependencies;
    for (const QString& name : marked) {
        if (apps.contains(name)) continue;
        m_model->setMissingDependencies(name, {});
        m_missingDependencies.remove(name);
    }
    for (auto it = missing.cbegin(); it != missing.cend(); ++it) {
        m_model->setMissingDependencies(it.key(), it.value());
        if (it.value().isEmpty()) m_missingDependencies.remove(it.key());
        else m_missingDependencies.insert(it.key());
    }
    m_readingDependencies = false;
    emit loadingChanged();
    // Another load on its way: they wait for it.
    if (!loading()) takeDeliveries();
}

void AppManager::recount()
{
    int apps = 0;
    int available = 0;
    for (int r = 0; r < m_model->rowCount(); ++r) {
        const QModelIndex at = m_model->index(r);
        if (!isApp(at.data(PackageModel::TypeRole).toString(), at.data(PackageModel::NameRole).toString())
            || !fromEnabledSource(at.data(PackageModel::RepositoryUrlRole).toString()))
            continue;
        ++apps;
        // As the list hides it when it doesn't show unavailable apps.
        if (at.data(PackageModel::HasInstallableVersionRole).toBool()
            || at.data(PackageModel::IsInstalledRole).toBool())
            ++available;
    }
    if (apps == m_appCount && available == m_availableCount) return;
    m_appCount = apps;
    m_availableCount = available;
    emit countsChanged();
}

bool AppManager::isApp(const QVariantMap& row)
{
    return isApp(str(row, "type"), str(row, "name"));
}

bool AppManager::isApp(const QString& type, const QString& name)
{
    return type == QLatin1String("ui_qml") && name != kShell;
}

bool AppManager::fromEnabledSource(const QVariantMap& row) const
{
    return fromEnabledSource(str(row, "repositoryUrl"));
}

bool AppManager::fromEnabledSource(const QString& repositoryUrl) const
{
    return repositoryUrl.isEmpty() || !m_disabledRepositories.contains(repositoryUrl);
}

bool AppManager::showsPackage(const QString& name, const QString& repositoryUrl) const
{
    for (const QVariant& v : m_details.value(QStringLiteral("packages")).toList()) {
        const QVariantMap p = v.toMap();
        if (!p.value(QStringLiteral("subject")).toBool() && str(p, "name") == name
            && str(p, "repositoryUrl") == repositoryUrl)
            return true;
    }
    return false;
}

void AppManager::readTrustedKeys()
{
    if (!m_packages) return;
    // An older read may answer last, with the keyring as it was before.
    const int asked = ++m_keyReads;
    QPointer<AppManager> self(this);
    m_packages->listTrustedKeys([self, asked](const QVariantList& keys, bool read) {
        if (!self || asked != self->m_keyReads
            || (self->m_keysAnswered && keys == self->m_trustedKeys && read == self->m_keysRead))
            return;
        self->m_trustedKeys = keys;
        self->m_keysRead = read;
        self->m_keysAnswered = true;
        self->refreshDetails();
    });
}

void AppManager::refreshDetails()
{
    QVariantMap details;
    const int row = rowOf(m_detailsName, m_detailsRepositoryUrl);
    const QVariantMap shown = row >= 0 ? m_model->rowAt(row) : QVariantMap();
    if (row >= 0 && fromEnabledSource(shown)) {
        details = shown;
        QVariantList packages = m_model->packagesBroughtBy(row, m_optional, m_versions);
        // Nothing said of who signed what until the keyring answers.
        if (m_keysAnswered) {
            const QVariantMap trust =
                trustOfBrought(*m_model, packages, m_trustedKeys, m_keysRead, m_detailsName);
            for (QVariant& v : packages) {
                QVariantMap p = v.toMap();
                p.insert(QStringLiteral("trust"), trust.value(str(p, "name")));
                v = p;
            }
            // Who signed the app: what it is, not a row a plan leaves as it is.
            QVariantMap own = trust.value(m_detailsName).toMap();
            own.remove(QStringLiteral("installed"));
            details.insert(QStringLiteral("trust"), own);
        }
        details.insert(QStringLiteral("packages"), packages);
    } else if (!m_detailsName.isEmpty()) {
        // Gone from every list, or its repository turned off: closed for
        // good, not reopened if it comes back.
        forgetPicks();
        m_detailsName.clear();
        m_detailsRepositoryUrl.clear();
    }
    if (details == m_details) return;
    m_details = details;
    emit detailsChanged();
}

}  // namespace appmanager
