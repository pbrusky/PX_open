#include "FrigateTimeline.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrlQuery>
#include <QDateTime>
#include <QTimeZone>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QUrl>
#include <algorithm>

namespace {

constexpr qint64 kCacheTtlMs = 3 * 60 * 1000; // 3 minutes

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

QString sanitizeKey(QString s)
{
    for (QChar& c : s) {
        if (!c.isLetterOrNumber() && c != QLatin1Char('-') && c != QLatin1Char('_')
            && c != QLatin1Char('.'))
            c = QLatin1Char('_');
    }
    if (s.isEmpty())
        s = QStringLiteral("default");
    return s;
}

QString serverKey(const QString& server)
{
    QUrl u(server);
    QString host = u.host();
    if (host.isEmpty())
        host = server;
    const int port = u.port(80);
    return sanitizeKey(host + QLatin1Char('_') + QString::number(port));
}

QString cacheRoot()
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    const QString dir = base + QStringLiteral("/timeline_cache");
    QDir().mkpath(dir);
    return dir;
}

QString cacheFilePath(const QString& server, const QString& kind, const QString& cameraKey)
{
    const QString dir = cacheRoot() + QLatin1Char('/') + serverKey(server);
    QDir().mkpath(dir);
    return dir + QLatin1Char('/') + sanitizeKey(kind) + QLatin1Char('_')
         + sanitizeKey(cameraKey) + QStringLiteral(".json");
}

bool readCacheFile(const QString& path, QJsonObject* outObj, qint64* outSavedAtMs)
{
    if (!outObj)
        return false;
    QFile f(path);
    if (!f.exists() || !f.open(QIODevice::ReadOnly))
        return false;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject())
        return false;
    const QJsonObject root = doc.object();
    if (outSavedAtMs)
        *outSavedAtMs = static_cast<qint64>(root.value(QStringLiteral("savedAt")).toDouble(0));
    *outObj = root;
    return true;
}

void writeCacheFile(const QString& path, const QJsonObject& payload)
{
    QJsonObject root = payload;
    root.insert(QStringLiteral("savedAt"),
                static_cast<double>(QDateTime::currentMSecsSinceEpoch()));
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    f.close();
}

bool cacheIsFresh(qint64 savedAtMs)
{
    if (savedAtMs <= 0)
        return false;
    return (QDateTime::currentMSecsSinceEpoch() - savedAtMs) < kCacheTtlMs;
}

bool diskCacheFresh(const QString& server, const QString& kind, const QString& cameraKey)
{
    if (server.isEmpty())
        return false;
    QJsonObject root;
    qint64 savedAt = 0;
    if (!readCacheFile(cacheFilePath(server, kind, cameraKey), &root, &savedAt))
        return false;
    return cacheIsFresh(savedAt);
}

QVariantList jsonArrayToList(const QJsonArray& arr)
{
    QVariantList list;
    list.reserve(arr.size());
    for (const QJsonValue& v : arr)
        list.append(v.toVariant());
    return list;
}

QJsonArray listToJsonArray(const QVariantList& list)
{
    return QJsonArray::fromVariantList(list);
}

bool loadListFromDisk(const QString& server, const QString& kind, const QString& key,
                      QVariantList* out)
{
    if (!out || server.isEmpty())
        return false;
    QJsonObject root;
    qint64 savedAt = 0;
    if (!readCacheFile(cacheFilePath(server, kind, key), &root, &savedAt))
        return false;
    *out = jsonArrayToList(root.value(QStringLiteral("data")).toArray());
    return true;
}

bool loadStringListFromDisk(const QString& server, const QString& kind, const QString& key,
                            QStringList* out)
{
    if (!out || server.isEmpty())
        return false;
    QJsonObject root;
    qint64 savedAt = 0;
    if (!readCacheFile(cacheFilePath(server, kind, key), &root, &savedAt))
        return false;
    out->clear();
    for (const QJsonValue& v : root.value(QStringLiteral("data")).toArray())
        out->append(v.toString());
    return true;
}

void saveListToDisk(const QString& server, const QString& kind, const QString& key,
                    const QVariantList& data)
{
    if (server.isEmpty())
        return;
    QJsonObject payload;
    payload.insert(QStringLiteral("data"), listToJsonArray(data));
    writeCacheFile(cacheFilePath(server, kind, key), payload);
}

void saveStringListToDisk(const QString& server, const QString& kind, const QString& key,
                          const QStringList& data)
{
    if (server.isEmpty())
        return;
    QJsonArray arr;
    for (const QString& d : data)
        arr.append(d);
    QJsonObject payload;
    payload.insert(QStringLiteral("data"), arr);
    writeCacheFile(cacheFilePath(server, kind, key), payload);
}

void removeCameraDiskFiles(const QString& server, const QString& cameraId)
{
    if (server.isEmpty() || cameraId.isEmpty())
        return;
    QFile::remove(cacheFilePath(server, QStringLiteral("rec"), cameraId));
    QFile::remove(cacheFilePath(server, QStringLiteral("days"), cameraId));
    QFile::remove(cacheFilePath(server, QStringLiteral("evt"), cameraId));
    QFile::remove(cacheFilePath(server, QStringLiteral("mot"), cameraId));
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

    if (m_recordingsByCamera.contains(cameraId)) {
        emit recordingsLoaded(cameraId, m_recordingsByCamera.value(cameraId));
    } else {
        QVariantList fromDisk;
        if (loadListFromDisk(m_server, QStringLiteral("rec"), cameraId, &fromDisk)) {
            m_recordingsByCamera[cameraId] = fromDisk;
            emit recordingsLoaded(cameraId, fromDisk);
        }
    }

    if (m_recordingDaysByCamera.contains(cameraId)) {
        emit recordingDaysLoaded(cameraId, m_recordingDaysByCamera.value(cameraId));
    } else {
        QStringList daysDisk;
        if (loadStringListFromDisk(m_server, QStringLiteral("days"), cameraId, &daysDisk)) {
            m_recordingDaysByCamera[cameraId] = daysDisk;
            emit recordingDaysLoaded(cameraId, daysDisk);
        }
    }

    if (diskCacheFresh(m_server, QStringLiteral("rec"), cameraId))
        return;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    loadRecordingsRange(cameraId, nowSec - 6 * 3600, nowSec);
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
        saveListToDisk(m_server, QStringLiteral("rec"), cameraId, segments);
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

    if (m_recordingDaysByCamera.contains(cameraId)) {
        emit recordingDaysLoaded(cameraId, m_recordingDaysByCamera.value(cameraId));
    } else {
        QStringList daysDisk;
        if (loadStringListFromDisk(m_server, QStringLiteral("days"), cameraId, &daysDisk)) {
            m_recordingDaysByCamera[cameraId] = daysDisk;
            emit recordingDaysLoaded(cameraId, daysDisk);
        }
    }

    if (diskCacheFresh(m_server, QStringLiteral("days"), cameraId))
        return;

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
            saveStringListToDisk(m_server, QStringLiteral("days"), cameraId, days);
            emit recordingDaysLoaded(cameraId, days);
            return;
        }

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
            saveStringListToDisk(m_server, QStringLiteral("days"), cameraId, days2);
            emit recordingDaysLoaded(cameraId, days2);
        });
    });
}

void FrigateTimeline::loadEvents(const QString& cameraId)
{
    const QString key = cameraId.isEmpty() ? QStringLiteral("__all__") : cameraId;

    if (m_eventsByCamera.contains(key)) {
        emit eventsLoaded(cameraId, m_eventsByCamera.value(key));
    } else {
        QVariantList fromDisk;
        if (loadListFromDisk(m_server, QStringLiteral("evt"), key, &fromDisk)) {
            m_eventsByCamera[key] = fromDisk;
            emit eventsLoaded(cameraId, fromDisk);
        }
    }

    if (diskCacheFresh(m_server, QStringLiteral("evt"), key))
        return;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    loadEventsRange(cameraId, nowSec - 6 * 3600, nowSec);
}

void FrigateTimeline::loadEventsRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec)
{
    if (m_server.isEmpty()) {
        m_eventsByCamera[cameraId] = QVariantList();
        emit eventsLoaded(cameraId, QVariantList());
        return;
    }

    const QString cacheKey = cameraId.isEmpty() ? QStringLiteral("__all__") : cameraId;
    if (m_eventsByCamera.contains(cacheKey)) {
        emit eventsLoaded(cameraId, m_eventsByCamera.value(cacheKey));
    } else {
        QVariantList fromDisk;
        if (loadListFromDisk(m_server, QStringLiteral("evt"), cacheKey, &fromDisk)) {
            m_eventsByCamera[cacheKey] = fromDisk;
            emit eventsLoaded(cameraId, fromDisk);
        }
    }

    QUrl url(QStringLiteral("%1/api/events").arg(m_server));
    QUrlQuery query;
    if (!cameraId.isEmpty())
        query.addQueryItem(QStringLiteral("cameras"), cameraId);
    query.addQueryItem(QStringLiteral("after"), QString::number(afterSec));
    query.addQueryItem(QStringLiteral("before"), QString::number(beforeSec));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("100"));
    query.addQueryItem(QStringLiteral("include_thumbnails"), QStringLiteral("0"));
    url.setQuery(query);

    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, cameraId]() {
        const QByteArray data = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();

        QVariantList events;
        if (status < 400) {
            const QJsonDocument doc = QJsonDocument::fromJson(data);
            if (doc.isArray()) {
                QString base = m_server;
                while (base.endsWith(QLatin1Char('/')))
                    base.chop(1);

                for (const QJsonValue& v : doc.array()) {
                    const QJsonObject o = v.toObject();
                    const QString cam = o.value(QStringLiteral("camera")).toString();
                    if (!cameraId.isEmpty() && !cam.isEmpty() && cam != cameraId)
                        continue;

                    double start = o.value(QStringLiteral("start_time")).toDouble();
                    double end   = o.value(QStringLiteral("end_time")).toDouble();
                    if (end <= 0.0)
                        end = start;

                    const QString id = o.value(QStringLiteral("id")).toString();
                    const QString label = o.value(QStringLiteral("label")).toString();

                    double score = o.value(QStringLiteral("score")).toDouble();
                    if (score <= 0.0) {
                        const QJsonObject dataObj = o.value(QStringLiteral("data")).toObject();
                        score = dataObj.value(QStringLiteral("top_score")).toDouble();
                        if (score <= 0.0)
                            score = dataObj.value(QStringLiteral("score")).toDouble();
                    }

                    QVariantMap ev;
                    ev.insert(QStringLiteral("id"), id);
                    ev.insert(QStringLiteral("camera"), cam.isEmpty() ? cameraId : cam);
                    ev.insert(QStringLiteral("label"), label);
                    ev.insert(QStringLiteral("start"), start);
                    ev.insert(QStringLiteral("end"), end);
                    ev.insert(QStringLiteral("score"), score);
                    ev.insert(QStringLiteral("has_snapshot"),
                              o.value(QStringLiteral("has_snapshot")).toBool());
                    ev.insert(QStringLiteral("has_clip"),
                              o.value(QStringLiteral("has_clip")).toBool());

                    if (!id.isEmpty() && !base.isEmpty()) {
                        ev.insert(QStringLiteral("thumbnail"),
                                  base + QStringLiteral("/api/events/") + id
                                      + QStringLiteral("/thumbnail.jpg"));
                        ev.insert(QStringLiteral("snapshot"),
                                  base + QStringLiteral("/api/events/") + id
                                      + QStringLiteral("/snapshot.jpg"));
                    }

                    events.append(ev);
                }
            }
        }

        std::sort(events.begin(), events.end(), [](const QVariant& a, const QVariant& b) {
            return a.toMap().value(QStringLiteral("start")).toDouble()
                 > b.toMap().value(QStringLiteral("start")).toDouble();
        });

        const QString key = cameraId.isEmpty() ? QStringLiteral("__all__") : cameraId;
        m_eventsByCamera[key] = events;
        saveListToDisk(m_server, QStringLiteral("evt"), key, events);
        emit eventsLoaded(cameraId, events);
    });
}

void FrigateTimeline::loadMotionActivity(const QString& cameraId)
{
    if (m_motionByCamera.contains(cameraId)) {
        emit motionActivityLoaded(cameraId, m_motionByCamera.value(cameraId));
    } else {
        QVariantList fromDisk;
        if (loadListFromDisk(m_server, QStringLiteral("mot"), cameraId, &fromDisk)) {
            m_motionByCamera[cameraId] = fromDisk;
            emit motionActivityLoaded(cameraId, fromDisk);
        }
    }

    if (diskCacheFresh(m_server, QStringLiteral("mot"), cameraId))
        return;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    loadMotionActivityRange(cameraId, nowSec - 6 * 3600, nowSec);
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
        saveListToDisk(m_server, QStringLiteral("mot"), cameraId, points);
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
    removeCameraDiskFiles(m_server, cameraId);
}