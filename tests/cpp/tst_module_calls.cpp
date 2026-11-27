// How the module's calls to package_downloader and package_manager fail.

#include "CallFailure.h"
#include "check.h"

#include <QFile>
#include <QRegularExpression>
#include <QStringList>

namespace {

// The source without comments, so prose may still name the call.
QString codeOf(const QString& path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return QString();
    QString text = QString::fromUtf8(file.readAll());
    text.remove(QRegularExpression(QStringLiteral(R"(/\*.*?\*/)"),
                                   QRegularExpression::DotMatchesEverythingOption));
    text.remove(QRegularExpression(QStringLiteral(R"(//[^\n]*)")));
    return text;
}

}  // namespace

// A plain fooAsync() hands a timeout over as an empty reply, which reads as
// "fetched nothing", "not signed as you approved it" or "could not uninstall". These take the result-carrying call.
TEST(calls_that_report_back_carry_the_call_error) {
    const QString code = codeOf(QStringLiteral(APP_SOURCE_DIR "/ModuleCalls.cpp"));
    CHECK(code.contains(QStringLiteral("downloadPinnedAsyncResult(")));
    const QRegularExpression plain(QStringLiteral(
        R"(\b(downloadPinned|refreshCatalog|verifyPackage|inspectPackage|installPlugin|uninstallPackage)Async\()"));
    QStringList offenders;
    for (auto it = plain.globalMatch(code); it.hasNext();) offenders << it.next().captured(1);
    CHECK_EQ(offenders, QStringList());
}

// One package may take every step package_downloader bounds: Logos Storage
// starting (90 s), its manifest (60 s), a stall (60 s), then HTTP (600 s).
TEST(a_download_outlasts_the_downloaders_own_limits) {
    constexpr int bounded = (90 + 60 + 60 + 600) * 1000;
    CHECK(appmanager::kDownloadMs > bounded);
}

TEST(a_timeout_is_reported_as_one) {
    const QString module = QStringLiteral("package_downloader");
    CHECK_EQ(appmanager::callFailure(module, "timeout", "call to 'x' timed out after 1800000ms",
                                     appmanager::kDownloadMs),
             QStringLiteral("package_downloader did not answer within 30 min."));
    CHECK_EQ(appmanager::callFailure(module, "timeout", "", 30 * 1000),
             QStringLiteral("package_downloader did not answer within 30 s."));
    CHECK_EQ(appmanager::callFailure(module, "timeout", "", 90 * 1000),
             QStringLiteral("package_downloader did not answer within 90 s."));
    CHECK_EQ(appmanager::callFailure(module, "transport_error", "connection lost", appmanager::kDownloadMs),
             QStringLiteral("connection lost"));
    CHECK_EQ(appmanager::callFailure(module, "call_failed", "", appmanager::kDownloadMs),
             QStringLiteral("package_downloader did not reply."));
}

CHECK_MAIN()
