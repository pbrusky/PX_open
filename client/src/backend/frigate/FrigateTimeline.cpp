#include "FrigateTimeline.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDateTime>
#include <QTimeZone>

namespace {

QVariantList mergeBlocks(QVariantList blocks)
{
    if (blocks.isEmpty())
        return blocks;

    std::sort(blocks.begin(), blocks.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(QStringLiteral("start")).toDouble()
             < b.toMap().value(QStringLiteral("start")).toDouble();
    });

    QVariantList out;
    QVariantMap cur = blocks.first().toMap();

    for (int i = 1; i < blocks.size(); ++i) {
        const QVariantMap next = blocks.at(i).toMap();
        const double curEnd = cur.value(QStringLiteral("end")).toDouble();
        const double nextStart = next.value(QStringLiteral("start")).toDouble();
        const double nextEnd = next.value(QStringLiteral("end")).toDouble();

        // Merge if touching / overlapping within 2 minutes
        if (nextStart <= curEnd + 120.0) {
            if (nextEnd > curEnd)
                cur.insert(QStringLiteral("end"), nextEnd);
        } else {
            out.append(cur);
            cur = next;
        }
    }
    out.append(cur);
    return out;
}

// Build timeline blocks from Frigate hourly summary (fast path)
QVariantList blocksFromSummary(const QJsonArray& days, qint64 windowStart, qint64 windowEnd)
{
    QVariantList blocks;

    for (const QJsonValue& dayVal : days) {
        const QJsonObject dayObj = dayVal.toObject();
        const QString dayStr = dayObj.value(QStringLiteral("day")).toString(); // "YYYY-MM-DD"
        if (dayStr.isEmpty())
            continue;

        const QJsonArray hours = dayObj.value(QStringLiteral("hours")).toArray();
        for (const QJsonValue& hourVal : hours) {
            const QJsonObject h = hourVal.toObject();
            const double duration = h.value(QStringLiteral("duration")).toDouble();
            if (duration <= 0.0)
                continue;

            // hour is "00" .. "23"
            const QString hourStr = h.value(QStringLiteral("hour")).toString();
            bool ok = false;
            const int hour = hourStr.toInt(&ok);
            if (!ok)
                continue;

            // Interpret day+hour as local time, convert to epoch seconds
            QDate date = QDate::fromString(dayStr, QStringLiteral("yyyy-MM-dd"));
            if (!date.isValid())
                continue;

            QDateTime dt(date, QTime(hour, 0, 0));
            dt.setTimeZone(QTimeZone::systemTimeZone());
            const qint64 start = dt.toSecsSinceEpoch();
            const qint64 end = start + qint64(duration);

            // Keep only hours overlapping the requested window
            if (end < windowStart || start > windowEnd)
                continue;

            QVariantMap seg;
            seg.insert(QStringLiteral("start"), double(qMax(start, windowStart)));
            seg.insert(QStringLiteral("end"), double(qMin(end, windowEnd)));
            seg.insert(QStringLiteral("motion"), h.value(QStringLiteral("motion")).toInt());
            seg.insert(QStringLiteral("objects"), h.value(QStringLiteral("objects")).toInt());
            blocks.append(seg);
        }
    }

    return mergeBlocks(blocks);
}

} // namespace

FrigateTimeline::FrigateTimeline(QObject* parent)
    : QObject(parent),
      m_net(new QNetworkAccessManager(this))
{
}

void FrigateTimeline::setServer(const QString& server)
{
    m_server = server;
    while (m_server.endsWith(QLatin1Char('/')))
        m_server.chop(1);
}

void FrigateTimeline::setModuleServer(const QString& server)
{
    m_moduleServer = server;
    while (m_moduleServer.endsWith(QLatin1Char('/')))
        m_moduleServer.chop(1);
}

void FrigateTimeline::loadRecordings(const QString& cameraId)
{
    if (m_server.isEmpty() || cameraId.isEmpty()) {
        m_recordingsByCamera[cameraId] = QVariantList();
        emit recordingsLoaded(cameraId, QVariantList());
        return;
    }

    // Serve cache immediately if we already loaded this camera
    if (m_recordingsByCamera.contains(cameraId)
            && !m_recordingsByCamera.value(cameraId).isEmpty()) {
        emit recordingsLoaded(cameraId, m_recordingsByCamera.value(cameraId));
        // Still refresh in background below
    }

    // FAST PATH: hourly summary (tiny payload, NX-style overview)
    QUrl url(QStringLiteral("%1/api/%2/recordings/summary").arg(m_server, cameraId));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("timezone"), QStringLiteral("browser"));
    url.setQuery(query);

    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError netErr = reply->error();
        reply->deleteLater();

        const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
        const qint64 afterSec = nowSec - 24 * 3600;

        QVariantList segments;

        if (netErr != QNetworkReply::NoError || status >= 400) {
            Q_UNUSED(status);
            loadRecordingsFallback(cameraId);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(data);
        if (!doc.isArray()) {
            loadRecordingsFallback(cameraId);
            return;
        }

        segments = blocksFromSummary(doc.array(), afterSec, nowSec);

        m_recordingsByCamera[cameraId] = segments;
        emit recordingsLoaded(cameraId, segments);
    });
}

// Slow fallback: raw segment list (only if summary fails)
void FrigateTimeline::loadRecordingsFallback(const QString& cameraId)
{
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    const qint64 afterSec = nowSec - 24 * 3600;

    QUrl url(QStringLiteral("%1/api/%2/recordings").arg(m_server, cameraId));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(nowSec));
    url.setQuery(query);

    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        reply->deleteLater();

        QVariantList segments;
        double rangeStart = 0.0;
        double rangeEnd = 0.0;
        int rawCount = 0;

        const QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isArray()) {
            const QJsonArray arr = doc.array();
            rawCount = arr.size();

            double blockStart = 0.0;
            double blockEnd = 0.0;
            bool haveBlock = false;
            const double gapTol = 3.0;

            auto flush = [&]() {
                if (!haveBlock || blockEnd <= blockStart)
                    return;
                QVariantMap seg;
                seg.insert(QStringLiteral("start"), blockStart);
                seg.insert(QStringLiteral("end"), blockEnd);
                segments.append(seg);
            };

            for (const QJsonValue& v : arr) {
                const QJsonObject o = v.toObject();
                double start = o.value(QStringLiteral("start_time")).toDouble();
                double end   = o.value(QStringLiteral("end_time")).toDouble();
                if (start <= 0.0)
                    start = o.value(QStringLiteral("start")).toDouble();
                if (end <= 0.0)
                    end = o.value(QStringLiteral("end")).toDouble();
                if (end <= start)
                    continue;

                if (rangeStart == 0.0 || start < rangeStart)
                    rangeStart = start;
                if (end > rangeEnd)
                    rangeEnd = end;

                if (!haveBlock) {
                    blockStart = start;
                    blockEnd = end;
                    haveBlock = true;
                } else if (start <= blockEnd + gapTol) {
                    if (end > blockEnd)
                        blockEnd = end;
                } else {
                    flush();
                    blockStart = start;
                    blockEnd = end;
                }
            }
            flush();

            if (rawCount > 50 && segments.size() <= 3 && rangeEnd > rangeStart) {
                QVariantMap one;
                one.insert(QStringLiteral("start"), rangeStart);
                one.insert(QStringLiteral("end"), rangeEnd);
                segments.clear();
                segments.append(one);
            }
        }

        m_recordingsByCamera[cameraId] = segments;
        emit recordingsLoaded(cameraId, segments);
    });
}

QVariantList FrigateTimeline::getRecordings(const QString& cameraId) const
{
    return m_recordingsByCamera.value(cameraId);
}

void FrigateTimeline::loadEvents(const QString& cameraId)
{
    if (m_server.isEmpty() || cameraId.isEmpty()) {
        m_eventsByCamera[cameraId] = QVariantList();
        emit eventsLoaded(cameraId, QVariantList());
        return;
    }

    if (m_eventsByCamera.contains(cameraId))
        emit eventsLoaded(cameraId, m_eventsByCamera.value(cameraId));

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    const qint64 afterSec = nowSec - 24 * 3600;

    QUrl url(QStringLiteral("%1/api/events").arg(m_server));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("cameras"), cameraId);
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(nowSec));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("300"));
    query.addQueryItem(QStringLiteral("include_thumbnails"), QStringLiteral("0"));
    url.setQuery(query);

    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        reply->deleteLater();

        QVariantList events;
        const QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isArray()) {
            for (const QJsonValue& v : doc.array()) {
                const QJsonObject o = v.toObject();
                const QString cam = o.value(QStringLiteral("camera")).toString();
                if (!cam.isEmpty() && cam != cameraId)
                    continue;

                double start = o.value(QStringLiteral("start_time")).toDouble();
                double end   = o.value(QStringLiteral("end_time")).toDouble();
                if (end <= 0.0)
                    end = start;

                QVariantMap ev;
                ev.insert(QStringLiteral("start"), start);
                ev.insert(QStringLiteral("end"), end);
                ev.insert(QStringLiteral("label"), o.value(QStringLiteral("label")).toString());
                ev.insert(QStringLiteral("score"), o.value(QStringLiteral("score")).toDouble());
                ev.insert(QStringLiteral("id"), o.value(QStringLiteral("id")).toString());
                events.append(ev);
            }
        }

        m_eventsByCamera[cameraId] = events;
        emit eventsLoaded(cameraId, events);
    });
}

QVariantList FrigateTimeline::getEvents(const QString& cameraId) const
{
    return m_eventsByCamera.value(cameraId);
}

void FrigateTimeline::loadPlaybackWindow(const QString& cameraId, qint64 timestampMs)
{
    if (m_moduleServer.isEmpty() || cameraId.isEmpty())
        return;

    QUrl url(QStringLiteral("%1/api/playback/%2?timestamp=%3")
                 .arg(m_moduleServer, cameraId, QString::number(timestampMs)));
    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);
    connect(reply, &QNetworkReply::finished, this, [reply]() {
        reply->deleteLater();
    });
}

void FrigateTimeline::clearCamera(const QString& cameraId)
{
    m_recordingsByCamera.remove(cameraId);
    m_eventsByCamera.remove(cameraId);
}