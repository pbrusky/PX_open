#include "FrigateTimeline.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDateTime>
#include <algorithm>

namespace {

QVariantList mergeTouchingOnly(QVariantList blocks, double gapTol = 3.0)
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
        const double cEnd = cur.value(QStringLiteral("end")).toDouble();
        const double nextStart = next.value(QStringLiteral("start")).toDouble();
        const double nextEnd = next.value(QStringLiteral("end")).toDouble();

        if (nextStart <= cEnd + gapTol) {
            if (nextEnd > cEnd)
                cur.insert(QStringLiteral("end"), nextEnd);
        } else {
            out.append(cur);
            cur = next;
        }
    }
    out.append(cur);
    return out;
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

    if (m_recordingsByCamera.contains(cameraId)
            && !m_recordingsByCamera.value(cameraId).isEmpty()) {
        emit recordingsLoaded(cameraId, m_recordingsByCamera.value(cameraId));
    }

    loadRecordingsFallback(cameraId);
}

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
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        QVariantList segments;
        if (status < 400) {
            const QJsonDocument doc = QJsonDocument::fromJson(data);
            if (doc.isArray()) {
                for (const QJsonValue& v : doc.array()) {
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
                    segments.append(seg);
                }
            }
        }

        segments = mergeTouchingOnly(segments, 3.0);
        m_recordingsByCamera[cameraId] = segments;
        emit recordingsLoaded(cameraId, segments);
    });
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
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("500"));
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

void FrigateTimeline::loadMotionActivity(const QString& cameraId)
{
    if (m_server.isEmpty() || cameraId.isEmpty()) {
        m_motionByCamera[cameraId] = QVariantList();
        emit motionActivityLoaded(cameraId, QVariantList());
        return;
    }

    if (m_motionByCamera.contains(cameraId)
            && !m_motionByCamera.value(cameraId).isEmpty()) {
        emit motionActivityLoaded(cameraId, m_motionByCamera.value(cameraId));
    }

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    const qint64 afterSec = nowSec - 24 * 3600;

    QUrl url(QStringLiteral("%1/api/review/activity/motion").arg(m_server));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("cameras"), cameraId);
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(nowSec));
    query.addQueryItem(QStringLiteral("scale"), QStringLiteral("30"));
    url.setQuery(query);

    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        QVariantList points;
        if (status < 400) {
            const QJsonDocument doc = QJsonDocument::fromJson(data);
            if (doc.isArray()) {
                for (const QJsonValue& v : doc.array()) {
                    const QJsonObject o = v.toObject();
                    const QString cam = o.value(QStringLiteral("camera")).toString();
                    if (!cam.isEmpty() && cam != cameraId)
                        continue;

                    const double motion = o.value(QStringLiteral("motion")).toDouble();
                    if (motion <= 0.0)
                        continue;

                    double start = o.value(QStringLiteral("start_time")).toDouble();
                    if (start <= 0.0)
                        start = o.value(QStringLiteral("start")).toDouble();
                    if (start <= 0.0)
                        continue;

                    QVariantMap pt;
                    pt.insert(QStringLiteral("start"), start);
                    pt.insert(QStringLiteral("motion"), motion);
                    points.append(pt);
                }
            }
        }

        m_motionByCamera[cameraId] = points;
        emit motionActivityLoaded(cameraId, points);
    });
}

QVariantList FrigateTimeline::getRecordings(const QString& cameraId) const
{
    return m_recordingsByCamera.value(cameraId);
}

QVariantList FrigateTimeline::getEvents(const QString& cameraId) const
{
    return m_eventsByCamera.value(cameraId);
}

QVariantList FrigateTimeline::getMotionActivity(const QString& cameraId) const
{
    return m_motionByCamera.value(cameraId);
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
    m_motionByCamera.remove(cameraId);
}