#pragma once

#include "library.h"

#include <QSet>
#include <QString>
#include <QUrl>
#include <optional>

// Early stop for a refresh: parsing ends once `stopAfterKnown` items in a row
// carry a guid already in `knownGuids`, but only while the feed looks newest-first
// (every item dated, never newer than the one before it) and the channel's title
// and image were already read. Anything else parses the whole feed.
struct FeedParseOptions {
    const QSet<QString> *knownGuids = nullptr;
    int stopAfterKnown = 0;
};

std::optional<ParsedShow> parseFeed(const QByteArray &xml, const QUrl &base, QString *error,
                                    const FeedParseOptions *options = nullptr,
                                    bool *stoppedEarly = nullptr);
QStringList parseOpml(const QByteArray &xml, QString *error);
// OPML 2.0 subscription list: one outline (type rss, text/title, xmlUrl) per show.
QByteArray writeOpml(const QList<ShowRow> &shows);
qint64 parsePublished(const QString &text);
int parseDuration(const QString &text);
