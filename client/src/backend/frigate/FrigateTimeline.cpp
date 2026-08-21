#include "FrigateTimeline.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDateTime>
#include <QTimeZone>
#include <algorithm>

namespace {

QVariantList mergeTouchingOnly(QVariantList blocks, double gapTol = 120.0)
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

QVariantList capMotionPoints(QVariantList points, int maxKeep = 400)
{
    if (points.size() <= maxKeep)
        return points;

    std::sort(points.begin(), points.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(QStringLiteral("motion")).toDouble()
             > b.toMap().value(QStringLiteral("motion")).toDouble();
    });
    QVariantList top;
    top.reserve(maxKeep);
    for (int i = 0; i < maxKeep; ++i)
        top.append(points.at(i));

    std::sort(top.begin(), top.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(QStringLiteral("start")).toDouble()
             < b.toMap().value(QStringLiteral("start")).toDouble();
    });
    return top;
}

QString systemTzName()
{
    const QByteArray id = QTimeZone::systemTimeZoneId();
    if (!id.isEmpty())
        return QString::fromUtf8(id);
    return QStringLiteral("UTC");
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
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    loadRecordingsRange(cameraId, nowSec - 24 * 3600, nowSec);
    loadRecordingDays(cameraId);
}

void FrigateTimeline::loadRecordingsRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec)
{
    if (m_server.isEmpty() || cameraId.isEmpty()) {
        m_recordingsByCamera[cameraId] = QVariantList();
        emit recordingsLoaded(cameraId, QVariantList());
        return;
    }

    QUrl url(QStringLiteral("%1/api/%2/recordings").arg(m_server, cameraId));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(beforeSec));
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

        segments = mergeTouchingOnly(segments, 120.0);
        m_recordingsByCamera[cameraId] = segments;
        emit recordingsLoaded(cameraId, segments);
    });
}

void FrigateTimeline::loadRecordingDays(const QString& cameraId)
{
    if (m_server.isEmpty() || cameraId.isEmpty()) {
        m_recordingDaysByCamera[cameraId] = QStringList();
        emit recordingDaysLoaded(cameraId, QStringList());
        return;
    }

    QUrl url(QStringLiteral("%1/api/recordings/summary").arg(m_server));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("cameras"), cameraId);
    query.addQueryItem(QStringLiteral("timezone"), systemTzName());
    url.setQuery(query);

    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        QStringList days;
        if (status < 400) {
            const QJsonDocument doc = QJsonDocument::fromJson(data);
            if (doc.isObject()) {
                const QJsonObject obj = doc.object();
                for (auto it = obj.begin(); it != obj.end(); ++it) {
                    if (it.key().size() >= 10)
                        days.append(it.key().left(10));
                }
            }
        }

        if (!days.isEmpty()) {
            days.removeDuplicates();
            days.sort();
            m_recordingDaysByCamera[cameraId] = days;
            emit recordingDaysLoaded(cameraId, days);
            return;
        }

        // Fallback: per-camera hourly summary
        QUrl url2(QStringLiteral("%1/api/%2/recordings/summary").arg(m_server, cameraId));
        QUrlQuery q2;
        q2.addQueryItem(QStringLiteral("timezone"), systemTzName());
        url2.setQuery(q2);

        QNetworkRequest req2(url2);
        QNetworkReply* reply2 = m_net->get(req2);
        connect(reply2, &QNetworkReply::finished, this, [this, reply2, cameraId]() {
            const QByteArray data2 = reply2->readAll();
            const int status2 = reply2->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            reply2->deleteLater();

            QStringList days2;
            if (status2 < 400) {
                const QJsonDocument doc2 = QJsonDocument::fromJson(data2);
                if (doc2.isArray()) {
                    for (const QJsonValue& v : doc2.array()) {
                        const QJsonObject o = v.toObject();
                        QString date = o.value(QStringLiteral("date")).toString();
                        if (date.isEmpty()) {
                            const QString hour = o.value(QStringLiteral("hour")).toString();
                            if (hour.size() >= 10)
                                date = hour.left(10);
                        }
                        if (date.size() >= 10)
                            days2.append(date.left(10));
                    }
                } else if (doc2.isObject()) {
                    const QJsonObject root = doc2.object();
                    for (auto it = root.begin(); it != root.end(); ++it) {
                        if (it.key().size() >= 10)
                            days2.append(it.key().left(10));
                    }
                }
            }

            days2.removeDuplicates();
            days2.sort();
            m_recordingDaysByCamera[cameraId] = days2;
            emit recordingDaysLoaded(cameraId, days2);
        });
    });
}

void FrigateTimeline::loadEvents(const QString& cameraId)
{
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    loadEventsRange(cameraId, nowSec - 24 * 3600, nowSec);
}

void FrigateTimeline::loadEventsRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec)
{
    if (m_server.isEmpty() || cameraId.isEmpty()) {
        m_eventsByCamera[cameraId] = QVariantList();
        emit eventsLoaded(cameraId, QVariantList());
        return;
    }

    QUrl url(QStringLiteral("%1/api/events").arg(m_server));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("cameras"), cameraId);
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(beforeSec));
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
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    loadMotionActivityRange(cameraId, nowSec - 24 * 3600, nowSec);
}

void FrigateTimeline::loadMotionActivityRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec)
{
    if (m_server.isEmpty() || cameraId.isEmpty()) {
        m_motionByCamera[cameraId] = QVariantList();
        emit motionActivityLoaded(cameraId, QVariantList());
        return;
    }

    QUrl url(QStringLiteral("%1/api/review/activity/motion").arg(m_server));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("cameras"), cameraId);
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(beforeSec));
    query.addQueryItem(QStringLiteral("scale"), QStringLiteral("300"));
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

        points = capMotionPoints(points, 400);
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

QStringList FrigateTimeline::getRecordingDays(const QString& cameraId) const
{
    return m_recordingDaysByCamera.value(cameraId);
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
    m_recordingDaysByCamera.remove(cameraId);
}