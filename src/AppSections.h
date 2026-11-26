#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QPointer>
#include <QStringList>
#include <QVariantMap>

namespace appmanager {

// The App Manager's list: a row for each section (a repository, or "local"
// for what was installed from a file), then the section's apps. A sandboxed
// view can make no filter of its own and gets the backend's models once, at
// start, so the sections are rows of the one model it reads.
//
// The source's rows come with a "sourceKey" role naming their section; a
// section is listed where its first row is. Every role of the source is
// passed through for an app's row. Changes reach a view as rows inserted,
// removed and changed, so its delegates stay put while the filters narrow.
class AppSections : public QAbstractListModel {
    Q_OBJECT

public:
    enum Role {
        KindRole = Qt::UserRole + 1000,  // "section" or "app"
        SectionKeyRole,
        SectionTitleRole,                // a section's row only
        SectionCountRole,                // a section's row only
    };
    Q_ENUM(Role)

    explicit AppSections(QObject* parent = nullptr);

    void setSourceModel(QAbstractItemModel* source);
    // A section's title by its key; with none, the key.
    void setTitles(const QVariantMap& titleByKey);
    // Sections left out, with their apps: disabled repositories.
    void setHidden(const QStringList& keys);

    // Apps listed, and those in one section.
    int appCount() const { return m_appCount; }
    int countOf(const QString& key) const { return m_countByKey.value(key); }
    QStringList sectionKeys() const;

    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

signals:
    void countsChanged();

private:
    struct Line {
        QString key;
        int source = -1;  // -1: the section's own row
        QString id;
    };

    QList<Line> linesNow() const;
    void sync();
    void reindex();
    void forwardDataChanged(const QModelIndex& topLeft, const QModelIndex& bottomRight,
                            const QList<int>& roles);
    QString titleOf(const QString& key) const;

    QPointer<QAbstractItemModel> m_source;
    QList<QMetaObject::Connection> m_connections;
    int m_sourceKeyRole = -1;
    int m_nameRole = -1;
    QHash<int, QByteArray> m_roleNames;

    QVariantMap m_titles;
    QStringList m_hidden;

    QList<Line> m_lines;
    QList<int> m_rowOfSource;
    QHash<QString, int> m_countByKey;
    int m_appCount = 0;
};

}  // namespace appmanager
