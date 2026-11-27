#pragma once

#include "logos_module_context.h"
#include "rep_app_manager_ui_source.h"

#include <QAbstractItemModel>

#include <functional>
#include <memory>

namespace appmanager {
class AppManager;
class ModuleCalls;
}  // namespace appmanager

namespace logos::installer {
class IntentConsent;
}  // namespace logos::installer

// Runs as the core module `app_manager_ui_backend`; the generated glue
// publishes it to the view, and `apps` beside it. Everything the page shows
// and does is appmanager::AppManager's: this class hands it the package
// modules and Basecamp's consent once modules() is live, forwards the
// modules' events, and mirrors its state into the .rep's properties.
class AppManagerBackend : public AppManagerUiSimpleSource,
                          public LogosModuleContext {
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel* apps READ apps CONSTANT)

public:
    explicit AppManagerBackend(QObject* parent = nullptr);
    ~AppManagerBackend() override;

    QAbstractItemModel* apps() const;

    void onContextReady() override;

    // intents_module's delivery of an intent this app provides; the
    // generated glue lets no one else call it. Taken at once, answered with
    // intents_module's respond() once App Manager has it in hand.
    QString deliver(const QString& dispatch, const QString& intent, const QString& paramsJson,
                    const QString& requester);

    void refresh() override;
    bool install(QString name, QString repositoryUrl) override;
    bool uninstall(QString name, QString repositoryUrl) override;
    void showDetails(QString name, QString repositoryUrl) override;
    void closeDetails() override;
    void selectVersion(QString name, QString repositoryUrl, int versionIndex) override;
    void setOptional(QString name, bool selected) override;

private:
    void mirror();

    appmanager::AppManager* m_manager;
    std::unique_ptr<appmanager::ModuleCalls> m_calls;
    logos::installer::IntentConsent* m_consent = nullptr;
    // intents_module's respond(dispatch, ok, "{}", error).
    std::function<void(const QString& dispatch, bool ok, const QString& error)> m_respond;
};
