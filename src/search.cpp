#include "search.h"

#include "covercache.h"

#include <QElapsedTimer>
#include <QSettings>
#include <QStringMatcher>
#include <QTimer>
#include <algorithm>
#include <cstdio>

namespace {

bool isBreakTag(QStringView tag)
{
    static const char *names[] = {"br", "p", "/p", "div", "/div", "li", "/li", "tr", "td", "h1", "h2", "h3", "h4", "/h1", "/h2", "/h3", "/h4"};
    for (const char *name : names) {
        const QLatin1StringView n(name);
        if (tag.size() >= n.size() && tag.left(n.size()).compare(n, Qt::CaseInsensitive) == 0
            && (tag.size() == n.size() || !tag.at(n.size()).isLetterOrNumber()))
            return true;
    }
    return false;
}

QChar entity(QStringView name)
{
    if (name.startsWith(QLatin1Char('#'))) {
        bool ok = false;
        uint code = name.startsWith(QLatin1String("#x")) || name.startsWith(QLatin1String("#X"))
                        ? name.mid(2).toUInt(&ok, 16) : name.mid(1).toUInt(&ok, 10);
        if (ok && code > 0 && code < 0xFFFF)
            return QChar(char16_t(code));
        return QChar();
    }
    if (name == QLatin1String("amp")) return QLatin1Char('&');
    if (name == QLatin1String("lt")) return QLatin1Char('<');
    if (name == QLatin1String("gt")) return QLatin1Char('>');
    if (name == QLatin1String("quot")) return QLatin1Char('"');
    if (name == QLatin1String("apos")) return QLatin1Char('\'');
    if (name == QLatin1String("nbsp")) return QLatin1Char(' ');
    if (name == QLatin1String("rsquo") || name == QLatin1String("lsquo")) return QLatin1Char('\'');
    if (name == QLatin1String("rdquo") || name == QLatin1String("ldquo")) return QLatin1Char('"');
    if (name == QLatin1String("ndash")) return QChar(0x2013);
    if (name == QLatin1String("mdash")) return QChar(0x2014);
    if (name == QLatin1String("hellip")) return QChar(0x2026);
    return QChar();
}

// Search folding, one character in, one out (so match offsets stay valid for
// highlighting): lower case, and accents dropped (é→e, ü→u, ñ→n). æ, ø and å
// stay their own letters, as Danish and Norwegian readers expect.
const char16_t *foldTable()
{
    static char16_t *table = [] {
        auto *t = new char16_t[0x10000];
        for (uint c = 0; c < 0x10000; ++c) {
            const QChar ch{char16_t(c)};
            if (ch.isSurrogate()) {
                t[c] = char16_t(c);
                continue;
            }
            QChar lower = ch.toLower();
            if (lower == QChar(0x00E5) || lower == QChar(0x00E6) || lower == QChar(0x00F8)) {
                t[c] = lower.unicode();
                continue;
            }
            if (lower.decompositionTag() == QChar::Canonical) {
                const QString d = lower.decomposition();
                if (!d.isEmpty() && d.at(0).unicode() < 0x250 && d.at(0).isLetter())
                    lower = d.at(0).toLower();
            }
            t[c] = lower.unicode();
        }
        return t;
    }();
    return table;
}

QString escape(QStringView text)
{
    return text.toString().toHtmlEscaped();
}

} // namespace

QString LibrarySearch::fold(const QString &text)
{
    const char16_t *table = foldTable();
    QString out(text.size(), Qt::Uninitialized);
    const char16_t *src = reinterpret_cast<const char16_t *>(text.constData());
    char16_t *dst = reinterpret_cast<char16_t *>(out.data());
    for (qsizetype i = 0, n = text.size(); i < n; ++i)
        dst[i] = table[src[i]];
    return out;
}

QString LibrarySearch::plainFromHtml(const QString &html)
{
    QString out;
    out.reserve(html.size());
    bool space = true;
    auto put = [&](QChar c) {
        if (c.isSpace()) {
            if (!space)
                out.append(QLatin1Char(' '));
            space = true;
        } else {
            out.append(c);
            space = false;
        }
    };
    const int n = html.size();
    for (int i = 0; i < n; ++i) {
        const QChar c = html.at(i);
        if (c == QLatin1Char('<')) {
            const int end = html.indexOf(QLatin1Char('>'), i + 1);
            if (end < 0)
                break;
            if (isBreakTag(QStringView(html).mid(i + 1, end - i - 1)))
                put(QLatin1Char(' '));
            i = end;
        } else if (c == QLatin1Char('&')) {
            const int end = html.indexOf(QLatin1Char(';'), i + 1);
            QChar decoded;
            if (end > i + 1 && end - i <= 10)
                decoded = entity(QStringView(html).mid(i + 1, end - i - 1));
            if (!decoded.isNull()) {
                put(decoded);
                i = end;
            } else {
                put(c);
            }
        } else {
            put(c);
        }
    }
    if (out.endsWith(QLatin1Char(' ')))
        out.chop(1);
    return out;
}

LibrarySearch::LibrarySearch(Library &library, QObject *parent)
    : QAbstractListModel(parent)
    , m_library(library)
{
    QSettings settings(Library::settingsPath(), QSettings::IniFormat);
    const int saved = settings.value(QStringLiteral("search/fields"), int(FieldAll)).toInt() & FieldAll;
    m_fields = saved == 0 ? int(FieldAll) : saved;
}

bool LibrarySearch::toggleField(int field)
{
    field &= FieldAll;
    if (field == 0)
        return false;
    const int next = m_fields ^ field;
    if (next == 0)
        return false; // never search nothing
    m_fields = next;
    QSettings settings(Library::settingsPath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("search/fields"), m_fields);
    emit fieldsChanged();
    if (!m_query.isEmpty())
        run();
    return true;
}

int LibrarySearch::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant LibrarySearch::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};
    const Hit &hit = m_rows.at(index.row());
    const SearchRow &row = m_docs.at(hit.doc).row;
    switch (role) {
    case EpisodeIdRole: return row.id;
    case ShowIdRole: return row.showId;
    case TitleRole: return row.title;
    case TitleHtmlRole: return hit.titleHtml;
    case ShowTitleRole: return m_showTitles.value(row.showId);
    case PublishedRole: return row.published;
    case DurationRole: return row.durationSecs;
    case PlayedRole: return row.played;
    case PositionRole: return row.positionMs;
    case CoverRole: return localCoverSource(row.imagePath);
    case SnippetHtmlRole: return hit.snippetHtml;
    case InTitleRole: return hit.inTitle;
    case ShowHtmlRole: return hit.showHtml;
    default: return {};
    }
}

QHash<int, QByteArray> LibrarySearch::roleNames() const
{
    return {
        {EpisodeIdRole, "episodeId"},
        {ShowIdRole, "showId"},
        {TitleRole, "title"},
        {TitleHtmlRole, "titleHtml"},
        {ShowTitleRole, "showTitle"},
        {PublishedRole, "published"},
        {DurationRole, "duration"},
        {PlayedRole, "played"},
        {PositionRole, "positionMs"},
        {CoverRole, "cover"},
        {SnippetHtmlRole, "snippetHtml"},
        {InTitleRole, "inTitle"},
        {ShowHtmlRole, "showHtml"},
    };
}

void LibrarySearch::ensureIndex()
{
    if (m_indexed)
        return;
    QElapsedTimer timer;
    timer.start();
    m_signature = m_library.searchSignature();
    m_showTitles.clear();
    m_showFolded.clear();
    QHash<qint64, QString> showFolded;
    for (const ShowRow &show : m_library.shows()) {
        m_showTitles.insert(show.id, show.title);
        m_showFolded.insert(show.id, fold(show.title));
        // Author too (e.g. "DR"), after the title so highlight offsets of the title hold.
        showFolded.insert(show.id, fold(show.title + QLatin1Char('\n') + show.author));
    }
    const QList<SearchRow> rows = m_library.searchRows();
    const qint64 readMs = timer.elapsed();
    m_docs.clear();
    m_docs.reserve(rows.size());
    for (const SearchRow &row : rows) {
        Doc doc;
        doc.row = row;
        doc.row.description.clear(); // the plain copy below is all search needs
        doc.titleLower = fold(row.title);
        doc.showLower = showFolded.value(row.showId); // shared, not copied
        doc.notes = plainFromHtml(row.description);
        doc.notesLower = fold(doc.notes);
        m_docs.append(doc);
    }
    m_indexed = true;
    if (qEnvironmentVariableIsSet("OMAEAR_TIMING"))
        fprintf(stderr, "search: indexed %lld episodes in %lld ms (database read %lld ms)\n", qlonglong(m_docs.size()), qlonglong(timer.elapsed()), qlonglong(readMs));
}

void LibrarySearch::warm()
{
    ensureIndex();
}

void LibrarySearch::setQuery(const QString &query)
{
    const QString trimmed = query.simplified();
    if (trimmed == m_query && m_indexed)
        return;
    m_query = trimmed;
    m_terms = fold(trimmed).split(QLatin1Char(' '), Qt::SkipEmptyParts);
    // Several keystrokes in one event-loop pass (fast typing) run one search.
    if (m_pending)
        return;
    m_pending = true;
    QTimer::singleShot(0, this, [this] {
        m_pending = false;
        run();
    });
}

void LibrarySearch::libraryChanged()
{
    if (!m_indexed)
        return;
    if (m_library.searchSignature() != m_signature) {
        m_indexed = false;
        if (!m_query.isEmpty())
            run();
        return;
    }
    // Same episodes: only played state / progress may have moved.
    const auto state = m_library.playState();
    for (Doc &doc : m_docs) {
        auto it = state.constFind(doc.row.id);
        if (it != state.constEnd()) {
            doc.row.played = it->first;
            doc.row.positionMs = it->second;
        }
    }
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(m_rows.size() - 1), {PlayedRole, PositionRole});
}

QString LibrarySearch::highlight(const QString &text, const QString &lower, int from, int to, bool mark) const
{
    if (!mark)
        return escape(QStringView(text).mid(from, to - from));
    // Mark every occurrence of every term within [from, to).
    QVector<QPair<int, int>> marks;
    for (const QString &term : m_terms) {
        int at = lower.indexOf(term, from);
        while (at >= 0 && at < to) {
            marks.append({at, qMin(to, int(at + term.size()))});
            at = lower.indexOf(term, at + term.size());
        }
    }
    std::sort(marks.begin(), marks.end());
    QString html;
    int pos = from;
    for (const auto &mark : marks) {
        if (mark.second <= pos)
            continue;
        const int start = qMax(pos, mark.first);
        html += escape(QStringView(text).mid(pos, start - pos));
        html += QStringLiteral("<b>") + escape(QStringView(text).mid(start, mark.second - start)) + QStringLiteral("</b>");
        pos = mark.second;
    }
    html += escape(QStringView(text).mid(pos, to - pos));
    return html;
}

void LibrarySearch::run()
{
    QElapsedTimer timer;
    timer.start();
    const int before = m_rows.size();
    QVector<Hit> rows;
    m_total = 0;
    if (!m_terms.isEmpty()) {
        ensureIndex();
        QVector<QStringMatcher> matchers;
        for (const QString &term : m_terms)
            matchers.append(QStringMatcher(term, Qt::CaseSensitive));
        // Tier per word: 0 = in the show name/author, 1 = in the episode title,
        // 2 = only in the notes. A result takes its weakest word. Typing a show's
        // name is the clearest intent, so that show's episodes lead.
        // Only the enabled fields count (a field that is off can't make a match).
        const bool useShow = m_fields & FieldShow;
        const bool useTitle = m_fields & FieldTitle;
        const bool useNotes = m_fields & FieldNotes;
        struct Match { int doc; int tier; };
        QVector<Match> matches;
        for (int d = 0; d < m_docs.size(); ++d) {
            const Doc &doc = m_docs.at(d);
            int tier = 0;
            for (const QStringMatcher &m : matchers) {
                if (useShow && m.indexIn(doc.showLower) >= 0)
                    continue;
                if (useTitle && m.indexIn(doc.titleLower) >= 0) {
                    tier = qMax(tier, 1);
                    continue;
                }
                if (!useNotes || m.indexIn(doc.notesLower) < 0) {
                    tier = -1;
                    break;
                }
                tier = 2;
            }
            if (tier >= 0)
                matches.append({d, tier});
        }
        std::sort(matches.begin(), matches.end(), [this](const Match &a, const Match &b) {
            if (a.tier != b.tier)
                return a.tier < b.tier;
            const qint64 pa = m_docs.at(a.doc).row.published;
            const qint64 pb = m_docs.at(b.doc).row.published;
            if (pa != pb)
                return pa > pb;
            return m_docs.at(a.doc).row.id > m_docs.at(b.doc).row.id;
        });
        m_total = matches.size();
        const int shown = qMin(int(matches.size()), kMaxResults);
        rows.reserve(shown);
        for (int i = 0; i < shown; ++i) {
            const Doc &doc = m_docs.at(matches.at(i).doc);
            Hit hit;
            hit.doc = matches.at(i).doc;
            hit.inTitle = matches.at(i).tier <= 1;
            const QString &showTitle = m_showTitles[doc.row.showId];
            hit.showHtml = highlight(showTitle, m_showFolded[doc.row.showId], 0, showTitle.size(), useShow);
            hit.titleHtml = highlight(doc.row.title, doc.titleLower, 0, doc.row.title.size(), useTitle);
            // Notes excerpt around the first notes hit (or the opening when the title matched).
            int at = -1;
            for (const QString &term : m_terms) {
                if (!useNotes)
                    break; // notes off: show their opening, unmarked
                const int found = doc.notesLower.indexOf(term);
                if (found >= 0 && (at < 0 || found < at))
                    at = found;
            }
            const int len = doc.notes.size();
            int from = at < 0 ? 0 : qMax(0, at - 50);
            if (from > 0) {
                const int sp = doc.notes.indexOf(QLatin1Char(' '), from);
                if (sp >= 0 && sp < at)
                    from = sp + 1;
            }
            int to = qMin(len, from + 220);
            if (to < len) {
                const int sp = doc.notes.lastIndexOf(QLatin1Char(' '), to);
                if (sp > from + 80)
                    to = sp;
            }
            if (len > 0)
                hit.snippetHtml = (from > 0 ? QStringLiteral("…") : QString())
                                  + highlight(doc.notes, doc.notesLower, from, to, useNotes)
                                  + (to < len ? QStringLiteral("…") : QString());
            rows.append(hit);
        }
    }
    m_scanMs = timer.nsecsElapsed() / 1e6;
    // Update in place rather than reset, so the list keeps its delegates and
    // only rebinds them: no teardown and rebuild of every visible row per keystroke.
    const int after = rows.size();
    if (after < before) {
        beginRemoveRows({}, after, before - 1);
        m_rows.resize(after);
        endRemoveRows();
    }
    const int common = qMin(before, after);
    for (int i = 0; i < common; ++i)
        m_rows[i] = rows.at(i);
    if (common > 0)
        emit dataChanged(index(0), index(common - 1));
    if (after > before) {
        beginInsertRows({}, before, after - 1);
        for (int i = before; i < after; ++i)
            m_rows.append(rows.at(i));
        endInsertRows();
    }
    m_elapsedMs = timer.nsecsElapsed() / 1e6;
    if (qEnvironmentVariableIsSet("OMAEAR_TIMING"))
        fprintf(stderr, "search: \"%s\" -> %d hits, match %.2f ms, total %.2f ms\n", qPrintable(m_query), m_total, m_scanMs, m_elapsedMs);
    emit resultsChanged();
}
