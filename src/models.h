#pragma once

#include "library.h"

#include <QAbstractListModel>

class ShowModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        ShowIdRole = Qt::UserRole + 1,
        TitleRole,
        AuthorRole,
        CoverRole,
        UnheardRole,
        RefreshErrorRole,
    };

    // KeepOrder: rows keep their current places (a refresh is running, nothing
    //   may jump under the cursor); new shows go last. Unchanged ids update in
    //   place, without a reset.
    // InPlaceIfSameOrder: the real order, but no reset when it did not change.
    // Reset: always rebuild.
    enum Update { Reset, KeepOrder, InPlaceIfSameOrder };

    explicit ShowModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setRows(const QList<ShowRow> &rows, Update how = Reset);
    // Cover warning badge text after a failed refresh; empty clears it.
    void setRefreshError(qint64 showId, const QString &reason);
    // Keyboard navigation on the shelf: map grid index <-> show id.
    Q_INVOKABLE qint64 showIdAt(int row) const;
    Q_INVOKABLE int rowOf(qint64 showId) const;

private:
    QList<ShowRow> m_rows;
    QHash<qint64, QString> m_refreshErrors;
};

class EpisodeModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        EpisodeIdRole = Qt::UserRole + 1,
        ShowIdRole,
        TitleRole,
        DescriptionRole,
        PublishedRole,
        DurationRole,
        PlayedRole,
        PositionRole,
        AudioRole,
        CoverRole,
        ShowTitleRole,
    };

    explicit EpisodeModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setRows(const QList<EpisodeRow> &rows);
    // Swap one row to a cached file without resetting the list.
    void setImagePath(qint64 episodeId, const QString &imagePath);
    // Move one row without a reset (live drag reordering in the queue).
    bool moveRow(int from, int to);
    QList<qint64> ids() const;
    // Keyboard navigation: map list index <-> episode id.
    Q_INVOKABLE qint64 episodeIdAt(int row) const;
    Q_INVOKABLE int rowOfEpisode(qint64 episodeId) const;

private:
    QList<EpisodeRow> m_rows;
};
