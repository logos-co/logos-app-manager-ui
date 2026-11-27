// The App Manager's list: a row per section, then its apps, kept in step
// with the filtered list a row at a time, so a view's tiles stay put.

#include "check.h"

#include "AppSections.h"

#include <QSignalSpy>
#include <QSortFilterProxyModel>
#include <QStandardItemModel>

using appmanager::AppSections;

namespace {

constexpr int kName = Qt::UserRole + 1;
constexpr int kSourceKey = Qt::UserRole + 2;
constexpr int kRank = Qt::UserRole + 3;
constexpr int kStage = Qt::UserRole + 4;

struct Source {
    QStandardItemModel model;
    QSortFilterProxyModel filter;

    Source()
    {
        model.setItemRoleNames({{kName, "name"}, {kSourceKey, "sourceKey"}, {kRank, "rank"},
                                {kStage, "installStage"}});
        filter.setSourceModel(&model);
        filter.setFilterRole(kName);
        filter.setSortRole(kRank);
        filter.setDynamicSortFilter(true);
        filter.sort(0);
    }
    void add(const QString& key, const QString& name, int rank)
    {
        auto* item = new QStandardItem;
        item->setData(name, kName);
        item->setData(key, kSourceKey);
        item->setData(rank, kRank);
        model.appendRow(item);
    }
    QStandardItem* item(const QString& name)
    {
        for (int r = 0; r < model.rowCount(); ++r)
            if (model.item(r)->data(kName).toString() == name) return model.item(r);
        return nullptr;
    }
    void remove(const QString& name)
    {
        model.removeRow(item(name)->row());
    }
};

// "§key n" for a section's row, the name for an app's.
QStringList lines(const AppSections& s)
{
    QStringList out;
    for (int r = 0; r < s.rowCount(); ++r) {
        const QModelIndex i = s.index(r);
        if (s.data(i, AppSections::KindRole).toString() == QLatin1String("section"))
            out << QStringLiteral("§%1 %2").arg(s.data(i, AppSections::SectionTitleRole).toString())
                       .arg(s.data(i, AppSections::SectionCountRole).toInt());
        else
            out << s.data(i, kName).toString();
    }
    return out;
}

// Two repositories and a local app, in the order a PackageFilter sorts them.
void fill(Source& src)
{
    src.add("https://default", "wallet", 1);
    src.add("https://default", "chat", 2);
    src.add("https://mine", "notes", 3);
    src.add("local", "scratch", 4);
}

}  // namespace

TEST(each_section_is_a_row_then_its_apps) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    CHECK_EQ(lines(s), (QStringList{"§https://default 2", "wallet", "chat", "§https://mine 1", "notes",
                                    "§local 1", "scratch"}));
    CHECK_EQ(s.appCount(), 4);
    CHECK_EQ(s.countOf("https://default"), 2);
    CHECK_EQ(s.countOf("local"), 1);
    CHECK_EQ(s.sectionKeys(), (QStringList{"https://default", "https://mine", "local"}));
}

TEST(an_apps_row_passes_the_sources_roles_through) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    CHECK_EQ(s.data(s.index(1), kName).toString(), QStringLiteral("wallet"));
    CHECK_EQ(s.data(s.index(1), AppSections::KindRole).toString(), QStringLiteral("app"));
    CHECK_EQ(s.data(s.index(1), AppSections::SectionKeyRole).toString(), QStringLiteral("https://default"));
    // A section's row has none of an app's.
    CHECK(!s.data(s.index(0), kName).isValid());
    CHECK(s.roleNames().values().contains("sectionTitle"));
    CHECK(s.roleNames().values().contains("installStage"));
}

TEST(titles_name_sections_and_the_key_stands_in) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy changed(&s, &QAbstractItemModel::dataChanged);
    s.setTitles({{"https://default", "Logos"}, {"local", "local"}});
    CHECK_EQ(lines(s).first(), QStringLiteral("§Logos 2"));
    CHECK_EQ(lines(s).at(3), QStringLiteral("§https://mine 1"));
    // Only the renamed section's row changed.
    CHECK_EQ(changed.count(), 1);
    CHECK_EQ(changed.first().at(0).value<QModelIndex>().row(), 0);
}

TEST(a_section_not_grouped_by_the_source_still_is) {
    Source src;
    src.add("https://a", "one", 1);
    src.add("https://b", "two", 2);
    src.add("https://a", "three", 3);
    AppSections s;
    s.setSourceModel(&src.filter);
    CHECK_EQ(lines(s), (QStringList{"§https://a 2", "one", "three", "§https://b 1", "two"}));
}

TEST(filtering_removes_rows_and_never_resets) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy reset(&s, &QAbstractItemModel::modelReset);
    QSignalSpy removed(&s, &QAbstractItemModel::rowsRemoved);
    QSignalSpy inserted(&s, &QAbstractItemModel::rowsInserted);
    QSignalSpy counts(&s, &AppSections::countsChanged);

    src.filter.setFilterFixedString("at");  // chat, scratch
    CHECK_EQ(lines(s), (QStringList{"§https://default 1", "chat", "§local 1", "scratch"}));
    CHECK_EQ(reset.count(), 0);
    CHECK(removed.count() > 0);
    CHECK(counts.count() > 0);
    CHECK_EQ(s.appCount(), 2);

    src.filter.setFilterFixedString("");
    CHECK_EQ(lines(s), (QStringList{"§https://default 2", "wallet", "chat", "§https://mine 1", "notes",
                                    "§local 1", "scratch"}));
    CHECK_EQ(reset.count(), 0);
    CHECK(inserted.count() > 0);
}

TEST(a_sections_last_app_takes_its_row_along) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy removed(&s, &QAbstractItemModel::rowsRemoved);
    src.remove("notes");
    CHECK_EQ(lines(s), (QStringList{"§https://default 2", "wallet", "chat", "§local 1", "scratch"}));
    // The section's row and its app, in one run.
    CHECK_EQ(removed.count(), 1);
    CHECK_EQ(removed.first().at(1).toInt(), 3);
    CHECK_EQ(removed.first().at(2).toInt(), 4);
}

TEST(a_new_app_is_inserted_where_it_sorts) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy inserted(&s, &QAbstractItemModel::rowsInserted);
    QSignalSpy changed(&s, &QAbstractItemModel::dataChanged);
    src.add("https://mine", "maps", 3);
    CHECK_EQ(lines(s), (QStringList{"§https://default 2", "wallet", "chat", "§https://mine 2", "notes",
                                    "maps", "§local 1", "scratch"}));
    CHECK_EQ(inserted.count(), 1);
    CHECK_EQ(inserted.first().at(1).toInt(), 5);
    // The section's row says its new count.
    bool countChanged = false;
    for (const QList<QVariant>& args : changed) {
        if (args.at(0).value<QModelIndex>().row() == 3
            && args.at(2).value<QList<int>>().contains(AppSections::SectionCountRole))
            countChanged = true;
    }
    CHECK(countChanged);
}

TEST(a_change_to_an_app_reaches_its_row) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy changed(&s, &QAbstractItemModel::dataChanged);
    src.item("notes")->setData(3, kStage);
    CHECK_EQ(changed.count(), 1);
    CHECK_EQ(changed.first().at(0).value<QModelIndex>().row(), 4);
    CHECK_EQ(changed.first().at(1).value<QModelIndex>().row(), 4);
    CHECK(changed.first().at(2).value<QList<int>>().contains(kStage));
    CHECK_EQ(s.data(s.index(4), kStage).toInt(), 3);
}

TEST(hidden_sections_are_left_out) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy reset(&s, &QAbstractItemModel::modelReset);
    s.setHidden({"https://mine"});
    CHECK_EQ(lines(s), (QStringList{"§https://default 2", "wallet", "chat", "§local 1", "scratch"}));
    CHECK_EQ(s.appCount(), 3);
    CHECK_EQ(s.countOf("https://mine"), 0);
    CHECK_EQ(reset.count(), 0);
    s.setHidden({});
    CHECK_EQ(s.appCount(), 4);
}

TEST(a_new_order_starts_over) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy reset(&s, &QAbstractItemModel::modelReset);
    // "mine" sorts first now.
    src.item("notes")->setData(0, kRank);
    CHECK_EQ(lines(s), (QStringList{"§https://mine 1", "notes", "§https://default 2", "wallet", "chat",
                                    "§local 1", "scratch"}));
    CHECK_EQ(reset.count(), 1);
    // And changes still reach the right row.
    QSignalSpy changed(&s, &QAbstractItemModel::dataChanged);
    src.item("chat")->setData(1, kStage);
    CHECK_EQ(changed.count(), 1);
    CHECK_EQ(changed.first().at(0).value<QModelIndex>().row(), 4);
}

TEST(a_source_reset_is_followed_row_by_row) {
    Source src;
    fill(src);
    AppSections s;
    s.setSourceModel(&src.filter);
    QSignalSpy reset(&s, &QAbstractItemModel::modelReset);
    QSignalSpy removed(&s, &QAbstractItemModel::rowsRemoved);
    src.filter.setSourceModel(nullptr);
    src.filter.setSourceModel(&src.model);
    CHECK_EQ(lines(s).size(), 7);
    CHECK_EQ(reset.count(), 0);
    CHECK(removed.count() > 0);
}

// A source reset that keeps its rows may change what they hold: a view
// keeping their delegates is told so.
TEST(the_rows_a_source_reset_keeps_say_they_changed) {
    struct Resetting : QStandardItemModel {
        void reset()
        {
            beginResetModel();
            endResetModel();
        }
    } model;
    model.setItemRoleNames({{kName, "name"}, {kSourceKey, "sourceKey"}, {kStage, "installStage"}});
    auto* item = new QStandardItem;
    item->setData("wallet", kName);
    item->setData("https://default", kSourceKey);
    item->setData(0, kStage);
    model.appendRow(item);
    AppSections s;
    s.setSourceModel(&model);
    QSignalSpy reset(&s, &QAbstractItemModel::modelReset);
    QSignalSpy changed(&s, &QAbstractItemModel::dataChanged);
    {
        const QSignalBlocker quiet(&model);
        item->setData(3, kStage);
    }
    model.reset();
    CHECK_EQ(lines(s), (QStringList{"§https://default 1", "wallet"}));
    CHECK_EQ(reset.count(), 0);
    CHECK(changed.count() > 0);
    CHECK_EQ(s.data(s.index(1), kStage).toInt(), 3);
}

CHECK_MAIN()
