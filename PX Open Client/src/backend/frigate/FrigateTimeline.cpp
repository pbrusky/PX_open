#include "FrigateTimeline.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QDebug>

FrigateTimeline::FrigateTimeline(QObject* parent)
    : QObject(parent),
      m_net(new QNetworkAccessManager(this))
{
}

//
// Server setters
//
void FrigateTimeline::setServer(const QString& server)
{
    m_server = server;
}

void FrigateTimeline::setModuleServer(const QString& server)
{
    m_moduleServer = server;
}

//
// ⭐ LOAD RECORDINGS
//
void FrigateTimeline::loadRecordings(const QString& cameraId)
{
    if (m_server.isEmpty()) {
        m_recordingsByCamera[cameraId] = QVariantList();
        emit recordingsLoaded(cameraId, QVariantList());
        return;
    }

    QUrl url(m_server + "/api/" + cameraId + "/recordings");
    QNetworkRequest req(url);

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished,
            this, [this, reply, cameraId]() {

        QByteArray data = reply->readAll();
        reply->deleteLater();

        QVariantList segments;

        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isArray()) {
            QJsonArray arr = doc.array();
            for (const QJsonValue& v : arr) {
                QJsonObject o = v.toObject();
                QVariantMap seg;
                seg["start"] = o["start"].toDouble();
                seg["end"]   = o["end"].toDouble();
                seg["type"]  = o["type"].toString();
                seg["id"]    = o["id"].toString();
                segments.append(seg);
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

//
// ⭐ LOAD EVENTS
//
void FrigateTimeline::loadEvents(const QString& cameraId)
{
    if (m_server.isEmpty()) {
        m_eventsByCamera[cameraId] = QVariantList();
        emit eventsLoaded(cameraId, QVariantList());
        return;
    }

    QUrl url(m_server + "/api/events");
    QNetworkRequest req(url);

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished,
            this, [this, reply, cameraId]() {

        QByteArray data = reply->readAll();
        reply->deleteLater();

        QVariantList events;

        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isArray()) {
            QJsonArray arr = doc.array();
            for (const QJsonValue& v : arr) {
                QJsonObject o = v.toObject();
                if (o["camera"].toString() != cameraId)
                    continue;

                QVariantMap ev;
                ev["start"] = o["start_time"].toDouble();
                ev["end"]   = o["end_time"].toDouble();
                ev["label"] = o["label"].toString();
                ev["score"] = o["score"].toDouble();
                ev["id"]    = o["id"].toString();
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

//
// ⭐ LOAD PLAYBACK WINDOW (optional but recommended)
//
void FrigateTimeline::loadPlaybackWindow(const QString& cameraId, qint64 timestampMs)
{
    if (m_moduleServer.isEmpty()) {
        return;
    }

    QUrl url(QString("%1/api/playback/%2?timestamp=%3")
             .arg(m_moduleServer, cameraId, QString::number(timestampMs)));

    QNetworkRequest req(url);

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished,
            this, [this, reply, cameraId]() {

        QByteArray data = reply->readAll();
        reply->deleteLater();

        // Playback window is optional — not used by QML yet
        qDebug() << "[Timeline] Playback window loaded for" << cameraId;
    });
}

//
// ⭐ CLEAR CAMERA
//
void FrigateTimeline::clearCamera(const QString& cameraId)
{
    m_recordingsByCamera.remove(cameraId);
    m_eventsByCamera.remove(cameraId);
}
