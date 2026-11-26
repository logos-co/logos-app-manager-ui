#include "AppSections.h"

#include <QSet>

namespace appmanager {

namespace {

const QString kLocal = QStringLiteral("local");

QString headerId(const QString& key)
{
    return QLatin1Char('\x02') + key;
}

}  // namespace

AppSections::AppSections(QObject* parent)
    : QAbstractListModel(parent)
{
}

void AppSections::setSourceModel(QAbstractItemModel* source)
{
    for (const QMetaObject::Connection& c : m_connections) disconnect(c);
    m_connections.clear();

    beginResetModel();
    m_source = source;
    m_roleNames.clear();
    m_sourceKeyRole = -1;
    m_nameRole = -1;
    if (source) {
        const QHash<int, QByteArray> names = source->roleNames();
        for (auto it = names.cbegin(); it != names.cend(); ++it) {
            m_roleNames.insert(it.key(), it.value());
            if (it.value() == "sourceKey") m_sourceKeyRole = it.key();
            if (it.value() == "name") m_nameRole = it.key();
        }
    }
    m_roleNames.insert(KindRole, "kind");
    m_roleNames.insert(SectionKeyRole, "sectionKey");
    m_roleNames.insert(SectionTitleRole, "sectionTitle");
    m_roleNames.insert(SectionCountRole, "sectionCount");
    m_lines = linesNow();
    reindex();
    endResetModel();

    if (source) {
        auto resync = [this] { sync(); };
        m_connections << connect(source, &QAbstractItemModel::rowsInserted, this, resync)
                      << connect(source, &QAbstractItemModel::rowsRemoved, this, resync)
                      << connect(source, &QAbstractItemModel::rowsMoved, this, resync)
                      << connect(source, &QAbstractItemModel::layoutChanged, this, resync)
                      << connect(source, &QAbstractItemModel::modelReset, this, resync)
                      << connect(source, &QAbstractItemModel::dataChanged, this,
                                 &AppSections::forwardDataChanged);
    }
    emit countsChanged();
}

void AppSections::setTitles(const QVariantMap& titleByKey)
{
    if (titleByKey == m_titles) return;
    QHash<QString, QString> before;
    for (const Line& l : m_lines) {
        if (l.source < 0) before.insert(l.key, titleOf(l.key));
    }
    m_titles = titleByKey;
    for (int i = 0; i < m_lines.size(); ++i) {
        const Line& l = m_lines.at(i);
        if (l.source >= 0 || before.value(l.key) == titleOf(l.key)) continue;
        const QModelIndex mi = index(i);
        emit dataChanged(mi, mi, {SectionTitleRole});
    }
}

void AppSections::setHidden(const QStringList& keys)
{
    if (keys == m_hidden) return;
    m_hidden = keys;
    sync();
}

QStringList AppSections::sectionKeys() const
{
    QStringList keys;
    for (const Line& l : m_lines) {
        if (l.source < 0) keys << l.key;
    }
    return keys;
}

int AppSections::rowCount(const QModelIndex& parent) const
{
    return parent.isValid() ? 0 : m_lines.size();
}

QVariant AppSections::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_lines.size()) return {};
    const Line& l = m_lines.at(index.row());
    const bool section = l.source < 0;
    switch (role) {
    case KindRole:
        return section ? QStringLiteral("section") : QStringLiteral("app");
    case SectionKeyRole:
        return l.key;
    case SectionTitleRole:
        return section ? QVariant(titleOf(l.key)) : QVariant();
    case SectionCountRole:
        return section ? QVariant(m_countByKey.value(l.key)) : QVariant();
    default:
        break;
    }
    if (section || !m_source || l.source >= m_source->rowCount()) return {};
    return m_source->data(m_source->index(l.source, 0), role);
}

QHash<int, QByteArray> AppSections::roleNames() const
{
    return m_roleNames;
}

QList<AppSections::Line> AppSections::linesNow() const
{
    QList<Line> lines;
    if (!m_source) return lines;

    QStringList order;
    QHash<QString, QList<int>> rowsOf;
    const int rows = m_source->rowCount();
    for (int r = 0; r < rows; ++r) {
        QString key = m_source->data(m_source->index(r, 0), m_sourceKeyRole).toString();
        if (key.isEmpty()) key = kLocal;
        if (m_hidden.contains(key)) continue;
        if (!rowsOf.contains(key)) order << key;
        rowsOf[key] << r;
    }

    QSet<QString> ids;
    for (const QString& key : order) {
        lines << Line{key, -1, headerId(key)};
        for (int r : rowsOf.value(key)) {
            const QString name = m_source->data(m_source->index(r, 0), m_nameRole).toString();
            QString id = key + QLatin1Char('\x01') + name;
            for (int n = 2; ids.contains(id); ++n)
                id = key + QLatin1Char('\x01') + name + QLatin1Char('#') + QString::number(n);
            ids.insert(id);
            lines << Line{key, r, id};
        }
    }
    return lines;
}

void AppSections::sync()
{
    const QList<Line> fresh = linesNow();
    QHash<QString, int> freshAt;
    for (int i = 0; i < fresh.size(); ++i) freshAt.insert(fresh.at(i).id, i);

    // What stays reads its new source row from here on.
    for (Line& l : m_lines) {
        const auto it = freshAt.constFind(l.id);
        if (it != freshAt.cend()) l.source = fresh.at(*it).source;
    }

    // What is gone, from the end, a run at a time.
    for (int i = m_lines.size() - 1; i >= 0;) {
        if (freshAt.contains(m_lines.at(i).id)) {
            --i;
            continue;
        }
        int first = i;
        while (first > 0 && !freshAt.contains(m_lines.at(first - 1).id)) --first;
        beginRemoveRows({}, first, i);
        m_lines.erase(m_lines.begin() + first, m_lines.begin() + i + 1);
        endRemoveRows();
        i = first - 1;
    }

    // What stays must be in the order it was; when it isn't, start over.
    int kept = 0;
    for (const Line& f : fresh) {
        if (kept < m_lines.size() && m_lines.at(kept).id == f.id) ++kept;
    }
    const QHash<QString, int> countsBefore = m_countByKey;
    if (kept != m_lines.size()) {
        beginResetModel();
        m_lines = fresh;
        endResetModel();
    } else {
        // What is new, a run at a time.
        int at = 0;
        for (int k = 0; k < fresh.size();) {
            if (at < m_lines.size() && m_lines.at(at).id == fresh.at(k).id) {
                ++at;
                ++k;
                continue;
            }
            int last = k;
            while (last + 1 < fresh.size()
                   && !(at < m_lines.size() && m_lines.at(at).id == fresh.at(last + 1).id))
                ++last;
            beginInsertRows({}, at, at + (last - k));
            for (int j = k; j <= last; ++j) m_lines.insert(at + (j - k), fresh.at(j));
            endInsertRows();
            at += last - k + 1;
            k = last + 1;
        }
    }

    const int appsBefore = m_appCount;
    reindex();

    for (int i = 0; i < m_lines.size(); ++i) {
        const Line& l = m_lines.at(i);
        if (l.source >= 0 || countsBefore.value(l.key, -1) == m_countByKey.value(l.key)) continue;
        const QModelIndex mi = index(i);
        emit dataChanged(mi, mi, {SectionCountRole});
    }
    if (countsBefore != m_countByKey || appsBefore != m_appCount) emit countsChanged();
}

void AppSections::reindex()
{
    m_rowOfSource.fill(-1, m_source ? m_source->rowCount() : 0);
    m_countByKey.clear();
    m_appCount = 0;
    for (int i = 0; i < m_lines.size(); ++i) {
        const Line& l = m_lines.at(i);
        if (l.source < 0) continue;
        if (l.source < m_rowOfSource.size()) m_rowOfSource[l.source] = i;
        ++m_countByKey[l.key];
        ++m_appCount;
    }
}

void AppSections::forwardDataChanged(const QModelIndex& topLeft, const QModelIndex& bottomRight,
                                     const QList<int>& roles)
{
    if (!topLeft.isValid() || !bottomRight.isValid()) return;
    int first = -1;
    int last = -1;
    auto flush = [&] {
        if (first >= 0) emit dataChanged(index(first), index(last), roles);
        first = -1;
    };
    for (int r = topLeft.row(); r <= bottomRight.row(); ++r) {
        const int row = r < m_rowOfSource.size() ? m_rowOfSource.at(r) : -1;
        if (row < 0) {
            flush();
            continue;
        }
        if (first >= 0 && row == last + 1) {
            last = row;
            continue;
        }
        flush();
        first = last = row;
    }
    flush();
}

QString AppSections::titleOf(const QString& key) const
{
    const QString title = m_titles.value(key).toString();
    return title.isEmpty() ? key : title;
}

}  // namespace appmanager
