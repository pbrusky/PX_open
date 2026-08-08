#include "FrigateTimeline.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDateTime>
#include <QDebug>
#include <algorithm>

namespace {

// Merge tiny Frigate segments into continuous blocks (gap <= 3 seconds)
QVariantList mergeRecordingSegments(QVariantList segments)
{
    if (segments.isEmpty())
        return segments;

    std::sort(segments.begin(), segments.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(QStringLiteral("start")).toDouble()
             < b.toMap().value(QStringLiteral("start")).toDouble();
    });

    QVariantList merged;
    QVariantMap current = segments.first().toMap();

    for (int i = 1; i < segments.size(); ++i) {
        const QVariantMap next = segments.at(i).toMap();
        const double curEnd = current.value(QStringLiteral("end")).toDouble();
        const double nextStart = next.value(QStringLiteral("start")).toDouble();
        const double nextEnd = next.value(QStringLiteral("end")).toDouble();

        // Continuous (or almost continuous) → extend current block
        if (nextStart <= curEnd + 3.0) {
            if (nextEnd > curEnd)
                current.insert(QStringLiteral("end"), nextEnd);
            current.insert(
                QStringLiteral("motion"),
                current.value(QStringLiteral("motion")).toInt()
                    + next.value(QStringLiteral("motion")).toInt());
            current.insert(
                QStringLiteral("objects"),
                current.value(QStringLiteral("objects")).toInt()
                    + next.value(QStringLiteral("objects")).toInt());
        } else {
            merged.append(current);
            current = next;
        }
    }
    merged.append(current);
    return merged;
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

    // Last 24 hours
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    const qint64 afterSec = nowSec - 24 * 3600;

    QUrl url(QStringLiteral("%1/api/%2/recordings").arg(m_server, cameraId));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(nowSec));
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError err = reply->error();
        reply->deleteLater();

        QVariantList segments;

        if (err != QNetworkReply::NoError || status >= 400) {
            qWarning() << "[Timeline] recordings failed for" << cameraId
                       << "status" << status << "error" << err;
            m_recordingsByCamera[cameraId] = segments;
            emit recordingsLoaded(cameraId, segments);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isArray()) {
            const QJsonArray arr = doc.array();
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

                QVariantMap seg;
                seg.insert(QStringLiteral("start"), start);
                seg.insert(QStringLiteral("end"), end);
                seg.insert(QStringLiteral("id"), o.value(QStringLiteral("id")).toString());
                seg.insert(QStringLiteral("duration"), o.value(QStringLiteral("duration")).toDouble());
                seg.insert(QStringLiteral("motion"), o.value(QStringLiteral("motion")).toInt());
                seg.insert(QStringLiteral("objects"), o.value(QStringLiteral("objects")).toInt());
                segments.append(seg);
            }
        }

        const int rawCount = segments.size();
        segments = mergeRecordingSegments(segments);

        m_recordingsByCamera[cameraId] = segments;
        qDebug() << "[Timeline] recordings for" << cameraId
                 << ":" << rawCount << "raw ->" << segments.size() << "merged";
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

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    const qint64 afterSec = nowSec - 24 * 3600;

    QUrl url(QStringLiteral("%1/api/events").arg(m_server));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("cameras"), cameraId);
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(nowSec));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("500"));
    query.addQueryItem(QStringLiteral("include_thumbnails"), QStringLiteral("0"));
    url.setQuery(query);

    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError err = reply->error();
        reply->deleteLater();

        QVariantList events;

        if (err != QNetworkReply::NoError || status >= 400) {
            qWarning() << "[Timeline] events failed for" << cameraId
                       << "status" << status;
            m_eventsByCamera[cameraId] = events;
            emit eventsLoaded(cameraId, events);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isArray()) {
            const QJsonArray arr = doc.array();
            for (const QJsonValue& v : arr) {
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
        qDebug() << "[Timeline] events for" << cameraId << ":" << events.size();
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