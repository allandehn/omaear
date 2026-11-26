#include "models.h"

#include "covercache.h"

#include <QFileInfo>
#include <QUrl>

namespace {
bool sameEpisode(const EpisodeRow &a, const EpisodeRow &b)
{
    return a.id == b.id
        && a.showId == b.showId
        && a.title == b.title
        && a.description == b.description
        && a.audioUrl == b.audioUrl
        && a.imagePath == b.imagePath
        && a.published == b.published
        && a.durationSecs == b.durationSecs
        && a.played == b.played
        && a.positionMs == b.positionMs
        && a.showTitle == b.showTitle;
}
}

ShowModel::ShowModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ShowModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant ShowModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const ShowRow &row = m_rows.at(index.row());
    switch (role) {
    case ShowIdRole:
        return row.id;
    case TitleRole:
        return row.title;
    case AuthorRole:
        return row.author;
    case CoverRole:
        // Provider: on-disk display-size thumbs + memory cache (see covercache.h).
        return localCoverSource(row.imagePath);
    case UnheardRole:
        return row.unheard;
    case RefreshErrorRole:
        return m_refreshErrors.value(row.id);
    default:
        return {};
    }
}

QHash<int, QByteArray> ShowModel::roleNames() const
{
    return {
        {ShowIdRole, "showId"},
        {TitleRole, "title"},
        {AuthorRole, "author"},
        {CoverRole, "cover"},
        {UnheardRole, "unheard"},
        {RefreshErrorRole, "refreshError"},
    };
}

namespace {
bool sameShow(const ShowRow &a, const ShowRow &b)
{
    return a.id == b.id && a.feedUrl == b.feedUrl && a.title == b.title && a.author == b.author
        && a.imagePath == b.imagePath && a.unheard == b.unheard && a.newest == b.newest
        && a.youngestUnheard == b.youngestUnheard;
}
}

void ShowModel::setRows(const QList<ShowRow> &rows, Update how)
{
    QList<ShowRow> next = rows;
    if (how == KeepOrder && !m_rows.isEmpty()) {
        QHash<qint64, int> place;
        for (int i = 0; i < m_rows.size(); ++i)
            place.insert(m_rows.at(i).id, i);
        QList<const ShowRow *> placed(m_rows.size(), nullptr);
        QList<ShowRow> added;
        for (const ShowRow &row : rows) {
            const auto it = place.constFind(row.id);
            if (it != place.cend())
                placed[it.value()] = &row;
            else
                added.append(row);
        }
        next.clear();
        next.reserve(rows.size());
        for (const ShowRow *row : std::as_const(placed)) {
            if (row)
                next.append(*row);
        }
        next += added;
    }
    bool sameOrder = how != Reset && next.size() == m_rows.size();
    for (int i = 0; sameOrder && i < next.size(); ++i)
        sameOrder = next.at(i).id == m_rows.at(i).id;
    if (sameOrder) {
        // Same shows in the same places: update only the rows that changed, so
        // delegates (and their decoded covers) stay put.
        for (int i = 0; i < next.size(); ++i) {
            if (sameShow(next.at(i), m_rows.at(i)))
                continue;
            m_rows[i] = next.at(i);
            emit dataChanged(index(i), index(i));
        }
        return;
    }
    beginResetModel();
    m_rows = next;
    endResetModel();
}

void ShowModel::setRefreshError(qint64 showId, const QString &reason)
{
    if (showId == 0)
        return;
    if (reason.isEmpty() ? !m_refreshErrors.remove(showId) : m_refreshErrors.value(showId) == reason)
        return;
    if (!reason.isEmpty())
        m_refreshErrors.insert(showId, reason);
    const int row = rowOf(showId);
    if (row >= 0)
        emit dataChanged(index(row), index(row), {RefreshErrorRole});
}

EpisodeModel::EpisodeModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int EpisodeModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant EpisodeModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};
    const EpisodeRow &row = m_rows.at(index.row());
    switch (role) {
    case EpisodeIdRole:
        return row.id;
    case ShowIdRole:
        return row.showId;
    case TitleRole:
        return row.title;
    case DescriptionRole:
        return row.description;
    case PublishedRole:
        return row.published;
    case DurationRole:
        return row.durationSecs;
    case PlayedRole:
        return row.played;
    case PositionRole:
        return row.positionMs;
    case AudioRole:
        return row.audioUrl;
    case CoverRole:
        // Memory-cached local file. A plain file URL is decoded again as soon as
        // Qt Quick evicts its ~2 MB cache of unreferenced images.
        return localCoverSource(row.imagePath);
    case ShowTitleRole:
        return row.showTitle;
    default:
        return {};
    }
}

QHash<int, QByteArray> EpisodeModel::roleNames() const
{
    return {
        {EpisodeIdRole, "episodeId"},
        {ShowIdRole, "showId"},
        {TitleRole, "title"},
        {DescriptionRole, "description"},
        {PublishedRole, "published"},
        {DurationRole, "duration"},
        {PlayedRole, "played"},
        {PositionRole, "positionMs"},
        {AudioRole, "audioUrl"},
        {CoverRole, "cover"},
        {ShowTitleRole, "showTitle"},
    };
}

void EpisodeModel::setRows(const QList<EpisodeRow> &rows)
{
    // Same episodes in the same order: update fields in place. beginResetModel()
    // destroys every delegate, and each Image then reloads its cover.
    if (m_rows.size() == rows.size()) {
        bool sameIds = true;
        for (int i = 0; i < rows.size(); ++i) {
            if (m_rows.at(i).id != rows.at(i).id) {
                sameIds = false;
                break;
            }
        }
        if (sameIds) {
            for (int i = 0; i < rows.size(); ++i) {
                if (sameEpisode(m_rows.at(i), rows.at(i)))
                    continue;
                const bool coverChanged = m_rows.at(i).imagePath != rows.at(i).imagePath;
                m_rows[i] = rows.at(i);
                QList<int> roles = {
                    ShowIdRole, TitleRole, DescriptionRole, PublishedRole,
                    DurationRole, PlayedRole, PositionRole, AudioRole,
                };
                if (coverChanged)
                    roles.append(CoverRole);
                const QModelIndex idx = index(i, 0);
                emit dataChanged(idx, idx, roles);
            }
            return;
        }
    }
    if (m_rows.isEmpty() && rows.isEmpty())
        return;
    beginResetModel();
    m_rows = rows;
    endResetModel();
}

void EpisodeModel::setImagePath(qint64 episodeId, const QString &imagePath)
{
    if (episodeId == 0 || imagePath.isEmpty())
        return;
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).id != episodeId)
            continue;
        if (m_rows.at(i).imagePath == imagePath)
            return;
        m_rows[i].imagePath = imagePath;
        const QModelIndex idx = index(i, 0);
        emit dataChanged(idx, idx, {CoverRole});
        return;
    }
}

bool EpisodeModel::moveRow(int from, int to)
{
    if (from < 0 || to < 0 || from >= m_rows.size() || to >= m_rows.size() || from == to)
        return false;
    // beginMoveRows wants the destination as the index *before* which rows land.
    if (!beginMoveRows(QModelIndex(), from, from, QModelIndex(), to > from ? to + 1 : to))
        return false;
    m_rows.move(from, to);
    endMoveRows();
    return true;
}

QList<qint64> EpisodeModel::ids() const
{
    QList<qint64> out;
    for (const auto &row : m_rows)
        out.append(row.id);
    return out;
}

qint64 ShowModel::showIdAt(int row) const
{
    return row >= 0 && row < m_rows.size() ? m_rows.at(row).id : 0;
}

QString ShowModel::titleAt(int row) const
{
    return row >= 0 && row < m_rows.size() ? m_rows.at(row).title : QString();
}

int ShowModel::rowOf(qint64 showId) const
{
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).id == showId)
            return i;
    }
    return -1;
}

qint64 EpisodeModel::episodeIdAt(int row) const
{
    return row >= 0 && row < m_rows.size() ? m_rows.at(row).id : 0;
}

int EpisodeModel::rowOfEpisode(qint64 episodeId) const
{
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).id == episodeId)
            return i;
    }
    return -1;
}
