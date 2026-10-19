#pragma once

#include "library.h"

#include <QString>
#include <QUrl>
#include <optional>

std::optional<ParsedShow> parseFeed(const QByteArray &xml, const QUrl &base, QString *error);
QStringList parseOpml(const QByteArray &xml, QString *error);
// OPML 2.0 subscription list: one outline (type rss, text/title, xmlUrl) per show.
QByteArray writeOpml(const QList<ShowRow> &shows);
qint64 parsePublished(const QString &text);
int parseDuration(const QString &text);
