#include "AppManagerBackend.h"

#include "AppManager.h"
#include <logos/installer/IntentConsent.h>
#include "ModuleCalls.h"

#include "logos_sdk.h"

#include <QCoreApplication>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>

using appmanager::AppManager;

namespace {

// intents_module answers a request or a result at once; the person's answer
// comes later, as settled.
constexpr int kIntentCallMs = 10 * 1000;

}  // namespace

AppManagerBackend::AppManagerBackend(QObject* parent)
    : AppManagerUiSimpleSource(parent)
    , m_manager(new AppManager(this))
{
    setAppRoleIds(m_manager->appRoleIds());
    setCategory(m_manager->category());
    mirror();

    connect(m_manager, &AppManager::loadingChanged, this, [this] { setLoading(m_manager->loading()); });
    connect(m_manager, &AppManager::onlineChanged, this, [this] { setOnline(m_manager->online()); });
    connect(m_manager, &AppManager::downloadStateChanged, this, [this] {
        setDownloadSource(m_manager->downloadSource());
        setStorageState(m_manager->storageState());
    });
    connect(m_manager, &AppManager::hostVariantChanged, this,
            [this] { setHostVariant(m_manager->hostVariant()); });
    connect(m_manager, &AppManager::repositoriesChanged, this,
            [this] { setRepositoryCount(m_manager->repositoryCount()); });
    connect(m_manager, &AppManager::categoriesChanged, this,
            [this] { setCategories(m_manager->categories()); });
    connect(m_manager, &AppManager::countsChanged, this, [this] {
        setVisibleCount(m_manager->visibleCount());
        setLocalCount(m_manager->localCount());
    });
    connect(m_manager, &AppManager::detailsChanged, this, [this] { setDetails(m_manager->details()); });
    connect(m_manager, &AppManager::finished, this,
            [this](const QString& name, int outcome, const QString& error) {
                emit finished(name, outcome, error);
            });
    connect(m_manager, &AppManager::searchRequested, this,
            [this](const QString& query) { emit searchRequested(query); });

    // The filters the view pushes.
    connect(this, &AppManagerUiSimpleSource::searchTextChanged, this,
            [this] { m_manager->setSearchText(searchText()); });
    connect(this, &AppManagerUiSimpleSource::categoryChanged, this,
            [this] { m_manager->setCategory(category()); });
    connect(this, &AppManagerUiSimpleSource::installStateChanged, this,
            [this] { m_manager->setInstallState(installState()); });
    connect(this, &AppManagerUiSimpleSource::showUnavailableChanged, this,
            [this] { m_manager->setShowUnavailable(showUnavailable()); });
}

AppManagerBackend::~AppManagerBackend()
{
    // It holds m_calls; nothing may reach the modules through it after.
    delete m_manager;
    m_manager = nullptr;
}

QAbstractItemModel* AppManagerBackend::apps() const
{
    return m_manager->apps();
}

void AppManagerBackend::onContextReady()
{
    LogosModules& logos = modules();
    m_calls = std::make_unique<appmanager::ModuleCalls>(logos);

    // Basecamp's consent, asked through intents_module, which the shell hosts.
    auto intents = logos.bind_intents(QStringLiteral("intents_module"));
    m_consent = new logos::installer::IntentConsent(
        [intents](const QString& intent, const QString& params,
                  std::function<void(const QString&)> done) mutable {
            intents.requestAsync(intent, params, [done](const QString& reply) { done(reply); },
                                 Timeout(kIntentCallMs));
        },
        [intents](const QString& handle, const QString& receipt,
                  std::function<void(const QString&)> done) mutable {
            intents.resultAsync(handle, receipt, [done](const QString& reply) { done(reply); },
                                Timeout(kIntentCallMs));
        },
        this);
    m_respond = [intents](const QString& dispatch, bool ok, const QString& error) mutable {
        intents.respondAsync(dispatch, ok, QStringLiteral("{}"), error, [](const QString&) {},
                             Timeout(kIntentCallMs));
    };

    // Events can arrive off this thread, and no module may be called from
    // inside one: each is handled from the event loop.
    QPointer<AppManagerBackend> self(this);
    auto later = [self](std::function<void(AppManagerBackend*)> handle) {
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, handle] {
            if (self && self->m_manager) handle(self.data());
        }, Qt::QueuedConnection);
    };
    intents.onSettled([later](const QString& handle) {
        later([handle](AppManagerBackend* b) { b->m_consent->onSettled(handle); });
    });
    intents.onSubscriptionStatus([later](logos::SubStatus status, std::uint64_t generation) {
        // Armed again after the first time: intents_module started over.
        if (status == logos::SubStatus::Armed && generation > 1)
            later([](AppManagerBackend* b) { b->m_consent->onRestarted(); });
    });

    m_manager->setModules(m_calls.get(), m_calls.get(), m_consent);
    const std::string dataDir = instancePersistencePath();
    if (!dataDir.empty())
        m_manager->setIconCacheDirectory(
            QDir(QString::fromStdString(dataDir)).filePath(QStringLiteral("icons")));

    auto packagesChanged = [later](const QVariantList&) {
        later([](AppManagerBackend* b) { b->m_manager->onPackagesChanged(); });
    };
    logos.package_manager.on(QStringLiteral("corePluginFileInstalled"), packagesChanged);
    logos.package_manager.on(QStringLiteral("uiPluginFileInstalled"), packagesChanged);
    logos.package_manager.on(QStringLiteral("corePluginUninstalled"), packagesChanged);
    logos.package_manager.on(QStringLiteral("uiPluginUninstalled"), packagesChanged);
    logos.package_downloader.on(QStringLiteral("catalogChanged"), [later](const QVariantList&) {
        later([](AppManagerBackend* b) { b->m_manager->onCatalogChanged(); });
    });
    logos.package_downloader.on(QStringLiteral("storageStateChanged"), [later](const QVariantList& data) {
        const QString state = data.value(0).toString();
        const QString error = data.value(1).toString();
        later([state, error](AppManagerBackend* b) { b->m_manager->onStorageStateChanged(state, error); });
    });
    // [name, received, total, transport]; a downloader before transports sends three.
    logos.package_downloader.on(QStringLiteral("downloadProgress"), [later](const QVariantList& data) {
        if (data.size() < 3) return;
        const QString name = data.at(0).toString();
        const quint64 received = data.at(1).toULongLong();
        const quint64 total = data.at(2).toULongLong();
        const QString transport = data.value(3).toString();
        later([=](AppManagerBackend* b) { b->m_manager->onDownloadProgress(name, received, total, transport); });
    });
    logos.package_downloader.onSubscriptionStatus([later](logos::SubStatus status, std::uint64_t) {
        if (status == logos::SubStatus::Armed)
            later([](AppManagerBackend* b) { b->m_manager->onSubscriptionArmed(); });
    });

    m_manager->load();
}

QString AppManagerBackend::deliver(const QString& dispatch, const QString& intent,
                                   const QString& paramsJson, const QString& requester)
{
    if (!m_respond || !AppManager::provides(intent)) return QStringLiteral("{\"ok\":false}");
    const QVariantMap params = QJsonDocument::fromJson(paramsJson.toUtf8()).object().toVariantMap();
    // Answered now; the work waits for the event loop, where a module may be called.
    QPointer<AppManagerBackend> self(this);
    QMetaObject::invokeMethod(this, [self, dispatch, intent, params, requester] {
        if (!self || !self->m_manager) return;
        const auto respond = self->m_respond;
        self->m_manager->deliver(intent, params, requester, [respond, dispatch](bool ok, const QString& error) {
            respond(dispatch, ok, error);
        });
    }, Qt::QueuedConnection);
    return QStringLiteral("{\"ok\":true}");
}

void AppManagerBackend::refresh()
{
    m_manager->refresh();
}

bool AppManagerBackend::install(QString name, QString repositoryUrl)
{
    return m_manager->install(name, repositoryUrl);
}

bool AppManagerBackend::uninstall(QString name, QString repositoryUrl)
{
    return m_manager->uninstall(name, repositoryUrl);
}

void AppManagerBackend::showDetails(QString name, QString repositoryUrl)
{
    m_manager->showDetails(name, repositoryUrl);
}

void AppManagerBackend::closeDetails()
{
    m_manager->closeDetails();
}

void AppManagerBackend::selectVersion(QString name, QString repositoryUrl, int versionIndex)
{
    m_manager->selectVersion(name, repositoryUrl, versionIndex);
}

void AppManagerBackend::setOptional(QString name, bool selected)
{
    m_manager->setOptional(name, selected);
}

void AppManagerBackend::mirror()
{
    setLoading(m_manager->loading());
    setOnline(m_manager->online());
    setDownloadSource(m_manager->downloadSource());
    setStorageState(m_manager->storageState());
    setHostVariant(m_manager->hostVariant());
    setRepositoryCount(m_manager->repositoryCount());
    setCategories(m_manager->categories());
    setVisibleCount(m_manager->visibleCount());
    setLocalCount(m_manager->localCount());
    setDetails(m_manager->details());
}
