#pragma once

#include "library.h"

#include <QAbstractListModel>
#include <QHash>
#include <QStringList>
#include <QVector>

// Library search: titles and show notes of every subscribed episode.
// The whole library is held in memory as lower-cased plain text (HTML stripped
// once), so each keystroke is a plain substring scan with no database round trip.
// Every word must match (title, show name/author, or notes). Ranked: show name
// first, then episode title, then notes; newest first within each.
class LibrarySearch : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(QString query READ query NOTIFY resultsChanged)
    Q_PROPERTY(int count READ count NOTIFY resultsChanged)
    Q_PROPERTY(int total READ total NOTIFY resultsChanged)
    Q_PROPERTY(double elapsedMs READ elapsedMs NOTIFY resultsChanged)
    // Which fields are searched: bit 1 = show name/author, 2 = episode title, 4 = notes.
    Q_PROPERTY(int fields READ fields NOTIFY fieldsChanged)
public:
    enum Roles {
        EpisodeIdRole = Qt::UserRole + 1,
        ShowIdRole,
        TitleRole,
        TitleHtmlRole,
        ShowTitleRole,
        PublishedRole,
        DurationRole,
        PlayedRole,
        PositionRole,
        CoverRole,
        SnippetHtmlRole,
        InTitleRole,
        ShowHtmlRole,
    };

    explicit LibrarySearch(Library &library, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString query() const { return m_query; }
    int count() const { return m_rows.size(); }
    int total() const { return m_total; }
    double elapsedMs() const { return m_elapsedMs; }

    Q_INVOKABLE void setQuery(const QString &query);
    // Build the index ahead of the first keystroke (page opened).
    Q_INVOKABLE void warm();
    // Flip one field (FieldShow / FieldTitle / FieldNotes). The last one on stays
    // on; returns false then. Saved in the settings file (search/fields).
    Q_INVOKABLE bool toggleField(int field);
    int fields() const { return m_fields; }
    enum Field { FieldShow = 1, FieldTitle = 2, FieldNotes = 4, FieldAll = 7 };
    Q_ENUM(Field)

    // The library changed (refresh, mark played, unsubscribe...).
    void libraryChanged();

    // Strip tags and decode common entities; whitespace collapsed.
    static QString plainFromHtml(const QString &html);
    // Lower case, accents dropped, same length as the input.
    static QString fold(const QString &text);

    static constexpr int kMaxResults = 300;

signals:
    void resultsChanged();
    void fieldsChanged();

private:
    struct Doc {
        SearchRow row;
        QString titleLower;
        QString showLower;  // show title + author, folded
        QString notes;      // plain text, original case
        QString notesLower; // same length as notes
    };
    struct Hit {
        int doc = -1;
        bool inTitle = false;
        QString titleHtml;
        QString snippetHtml;
        QString showHtml;
    };

    void ensureIndex();
    void run();
    QString highlight(const QString &text, const QString &lower, int from, int to, bool mark = true) const;

    Library &m_library;
    QVector<Doc> m_docs;
    QHash<qint64, QString> m_showTitles;
    QHash<qint64, QString> m_showFolded;
    QString m_signature;
    bool m_indexed = false;
    QString m_query;
    QStringList m_terms;
    QVector<Hit> m_rows;
    int m_total = 0;
    double m_elapsedMs = 0;
    double m_scanMs = 0;
    bool m_pending = false;
    int m_fields = FieldAll;
};
