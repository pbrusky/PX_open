#include "FrigateAPI.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QDebug>
#include <QThread>

// Simple caches for timeline + playback
static QHash<QString, QVariantList> s_recordingsByCamera;
static QHash<QString, QVariantList> s_eventsByCamera;
static QHash<QString, qint64>       s_playbackPositionByCamera;

FrigateAPI::FrigateAPI(QObject* parent)
    : QObject(parent),
      m_net(new QNetworkAccessManager(this))
{
}

//
// ⭐ SERVER SETTERS
//
void FrigateAPI::setServerIp(QString ip)
{
    if (m_serverIp == ip)
        return;

    m_serverIp = ip;
    emit serverIpChanged();
}

void FrigateAPI::setServer(QString server)
{
    if (m_server == server)
        return;

    m_server = server;
    emit serverChanged();
}

void FrigateAPI::setModuleServer(QString server)
{
    if (m_moduleServer == server)
        return;

    m_moduleServer = server;
    emit moduleServerChanged();
}

//
// ⭐ MODULE INFORMATION
//
void FrigateAPI::loadModuleInformation()
{
    if (m_moduleServer.isEmpty()) {
        qWarning() << "[FrigateAPI] moduleServer is empty";
        return;
    }

    QUrl url(m_moduleServer + "/api/moduleInformation");
    QNetworkRequest req(url);

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject replyObj = doc.object()["reply"].toObject();

        emit moduleInformationReceived(
            replyObj["name"].toString(),
            replyObj["version"].toString(),
            replyObj["status"].toString(),
            replyObj["systemId"].toString(),
            replyObj["id"].toString()
        );
    });
}

//
// ⭐ LOAD CAMERAS (Frigate /api/config)
//
void FrigateAPI::loadCameras()
{
    if (m_server.isEmpty()) {
        qWarning() << "[FrigateAPI] Cannot load cameras: server URL is empty";
        emit camerasLoaded(QVariantList());
        return;
    }

    QString serverIp = m_server;
    serverIp.remove("http://");
    serverIp.remove("https://");
    serverIp.remove(":5000");
    serverIp.remove("/");

    setServerIp(serverIp);

    QUrl url(m_server + "/api/config");
    QNetworkRequest req(url);

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, serverIp]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();

        QVariantList list;

        if (root.contains("cameras")) {
            QJsonObject cams = root["cameras"].toObject();

            for (auto it = cams.begin(); it != cams.end(); ++it) {
                QString id = it.key();

                QVariantMap entry;
                entry["id"] = id;
                entry["name"] = id;

                entry["streamUrl"] = QString("rtsp://%1:8554/%2")
                                        .arg(serverIp, id);

                list.append(entry);
            }
        }

        emit camerasLoaded(list);
    });
}

//
// ⭐ ADD CAMERA
//
void FrigateAPI::addCamera(QString id, QString url)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraAddResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/addCamera");
    QNetworkRequest req(endpoint);

    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject obj;
    obj["id"] = id;
    obj["rtsp"] = url;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();

        bool ok = root.value("status").toString() == "ok";
        bool go2 = root.value("go2rtc").toBool(false);
        bool frig = root.value("frigate_reload").toBool(false);

        QString msg;
        if (ok)
            msg = QString("Camera added (go2rtc=%1, frigate_reload=%2)").arg(go2).arg(frig);
        else
            msg = QString("Failed to add camera (go2rtc=%1, frigate_reload=%2)").arg(go2).arg(frig);

        qDebug() << "[FrigateAPI] addCamera response:" << msg;
        emit cameraAddResult(ok, msg);

        if (ok) {
            loadCameras();
        }
    });
}

//
// ⭐ EDIT CAMERA
//
void FrigateAPI::editCamera(QString id, QString url)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraEditResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/editCamera");
    QNetworkRequest req(endpoint);

    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject obj;
    obj["id"] = id;
    obj["rtsp"] = url;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        bool ok = doc.object()["status"].toString() == "ok";

        emit cameraEditResult(ok, ok ? "OK" : "Failed to update camera");

        if (ok) {
            loadCameras();
        }
    });
}

//
// ⭐ APPLY NEW CAMERA RTSP
//
void FrigateAPI::applyNewCameraRtsp(const QString& cameraId, const QString& rtspUrl)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraEditResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/editCamera");
    QNetworkRequest req(endpoint);

    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject obj;
    obj["id"] = cameraId;
    obj["rtsp"] = rtspUrl;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished,
            this, [this, reply, cameraId, rtspUrl]() {

        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();

        bool ok = (reply->error() == QNetworkReply::NoError &&
                   root.value("status").toString() == "ok");

        emit cameraEditResult(ok, ok ? "OK" : "Failed to update camera");

        if (ok) {
            loadCameras();
        }
    });
}

//
// ⭐ REMOVE CAMERA
//
void FrigateAPI::removeCamera(QString id)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraRemoveResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/removeCamera");
    QNetworkRequest req(endpoint);

    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject obj;
    obj["id"] = id;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        bool ok = doc.object()["status"].toString() == "ok";

        emit cameraRemoveResult(ok, ok ? "Camera removed" : "Failed to remove camera");

        if (ok) {
            loadCameras();
        }
    });
}

//
// ⭐ ONVIF DISCOVERY
//
void FrigateAPI::discoverOnvif()
{
    if (m_moduleServer.isEmpty()) {
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/onvifDiscover");
    QNetworkRequest req(endpoint);

    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonArray arr = doc.object()["devices"].toArray();

        QVariantList list;

        for (const QJsonValue& v : arr) {
            QJsonObject o = v.toObject();

            QVariantMap entry;
            entry["address"]      = o.value("address").toString();
            entry["manufacturer"] = o.value("manufacturer").toString();
            entry["model"]        = o.value("model").toString();
            entry["username"]     = o.value("username").toString();
            entry["password"]     = o.value("password").toString();
            entry["rtsp"]         = o.value("rtsp").toString();

            list.append(entry);
        }

        emit onvifDevicesDiscovered(list);
    });
}

//
// ⭐ RTSP TEST
//
void FrigateAPI::testRtsp(const QString& url)
{
    qDebug() << "[FrigateAPI] testRtsp(): url =" << url;

    auto* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setTestMode(true);

    auto* thread = new QThread(this);

    connect(thread, &QThread::started,
            worker, &FFmpegWorker::startDecoding);

    connect(worker, &FFmpegWorker::openInputOk, this, [this]() {
        emit rtspTestResult(true, "RTSP stream opened successfully");
    });

    connect(worker, &FFmpegWorker::openInputFailed, this, [this](const QString& reason) {
        emit rtspTestResult(false, reason);
    });

    connect(worker, &FFmpegWorker::finished,
            thread, &QThread::quit);

    connect(worker, &FFmpegWorker::finished,
            worker, &QObject::deleteLater);

    connect(thread, &QThread::finished,
            thread, &QObject::deleteLater);

    worker->moveToThread(thread);
    thread->start();
}

//
// ⭐ LIVE STREAM QUEUE — NX STYLE OFFLINE DETECTION
//
QObject* FrigateAPI::getQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty()) {
        qWarning() << "[FrigateAPI] getQueue(): invalid/empty cameraName";
        return nullptr;
    }

    if (m_queues.contains(cameraName))
        return m_queues[cameraName];

    auto* queue = new FrameQueue(this);
    m_queues.insert(cameraName, queue);

    const QString url = QString("rtsp://%1:8554/%2").arg(m_serverIp, cameraName);

    auto* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    m_workers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::openInputOk,
            this, [this, cameraName]() {
        emit cameraOnline(cameraName);
    });

    connect(worker, &FFmpegWorker::openInputFailed,
            this, [this, cameraName](const QString& reason) {
        qDebug() << "[FrigateAPI] Camera offline:" << cameraName << "reason:" << reason;
        emit cameraOffline(cameraName);
    });

    connect(worker, &FFmpegWorker::frameReady,
            queue, &FrameQueue::pushFrame,
            Qt::QueuedConnection);

    auto* thread = new QThread(this);
    m_threads.insert(cameraName, thread);

    connect(thread, &QThread::started,
            worker, &FFmpegWorker::startDecoding);

    connect(worker, &FFmpegWorker::finished,
            this, [this, cameraName]() {
        m_workers.remove(cameraName);
        m_threads.remove(cameraName);
    });

    connect(worker, &FFmpegWorker::finished,
            thread, &QThread::quit);

    connect(worker, &FFmpegWorker::finished,
            worker, &QObject::deleteLater);

    connect(thread, &QThread::finished,
            thread, &QObject::deleteLater);

    worker->moveToThread(thread);
    thread->start();

    return queue;
}

//
// ⭐ STOP ONE STREAM (NEW — per camera)
//
void FrigateAPI::stopStream(const QString& cameraName)
{
    qDebug() << "[FrigateAPI] stopStream(): stopping FFmpeg for" << cameraName;

    if (!m_workers.contains(cameraName))
        return;

    FFmpegWorker* worker = m_workers.value(cameraName);
    QThread* thread = m_threads.value(cameraName);

    if (worker)
        worker->stopDecoding();

    if (thread) {
        thread->quit();
        thread->wait();
    }

    m_workers.remove(cameraName);
    m_threads.remove(cameraName);
}

//
// ⭐ STOP ALL STREAMS (global shutdown only)
//
void FrigateAPI::stopAllStreams()
{
    qDebug() << "[FrigateAPI] stopAllStreams(): stopping all FFmpeg threads";

    for (auto it = m_workers.begin(); it != m_workers.end(); ++it) {
        FFmpegWorker* worker = it.value();
        if (worker)
            worker->stopDecoding();
    }

    for (auto it = m_threads.begin(); it != m_threads.end(); ++it) {
        QThread* thread = it.value();
        if (thread) {
            thread->quit();
            thread->wait();
        }
    }

    m_workers.clear();
    m_threads.clear();
}

//
// ⭐ TIMELINE — RECORDINGS
//
void FrigateAPI::loadRecordings(const QString& cameraId)
{
    if (m_server.isEmpty()) {
        s_recordingsByCamera[cameraId] = QVariantList();
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
                segments.append(seg);
            }
        }

        s_recordingsByCamera[cameraId] = segments;
        emit recordingsLoaded(cameraId, segments);
    });
}

QVariantList FrigateAPI::getRecordingsForCamera(const QString& cameraId)
{
    return s_recordingsByCamera.value(cameraId);
}

//
// ⭐ TIMELINE — EVENTS
//
void FrigateAPI::loadEvents(const QString& cameraId)
{
    if (m_server.isEmpty()) {
        s_eventsByCamera[cameraId] = QVariantList();
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
                events.append(ev);
            }
        }

        s_eventsByCamera[cameraId] = events;
        emit eventsLoaded(cameraId, events);
    });
}

QVariantList FrigateAPI::getEventsForCamera(const QString& cameraId)
{
    return s_eventsByCamera.value(cameraId);
}

//
// ⭐ SEEK
//
void FrigateAPI::seek(const QString& cameraId, qint64 timestampMs)
{
    s_playbackPositionByCamera[cameraId] = timestampMs;
    emit playbackPositionChanged(cameraId, timestampMs);
}

//
// ⭐ START PLAYBACK
//
void FrigateAPI::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    s_playbackPositionByCamera[cameraId] = timestampMs;
    emit playbackPositionChanged(cameraId, timestampMs);
}

//
// ⭐ CURRENT POSITION
//
qint64 FrigateAPI::currentPosition(const QString& cameraId)
{
    return s_playbackPositionByCamera.value(cameraId, 0);
}

//
// ⭐ SWITCH TO LIVE
//
void FrigateAPI::switchToLive(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty()) {
        qWarning() << "[FrigateAPI] switchToLive(): cameraId is empty";
        return;
    }

    if (m_workers.contains(cameraId)) {
        FFmpegWorker* workerOld = m_workers.value(cameraId);
        if (workerOld)
            workerOld->stopDecoding();
    }

    QString url = QString("rtsp://%1:8554/%2").arg(m_serverIp, cameraId);

    FrameQueue* queue = nullptr;
    if (m_queues.contains(cameraId)) {
        queue = m_queues.value(cameraId);
    } else {
        queue = new FrameQueue(this);
        m_queues.insert(cameraId, queue);
    }

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);

    m_workers.insert(cameraId, worker);

    connect(worker, &FFmpegWorker::openInputOk,
            this, [this, cameraId]() {
        emit cameraOnline(cameraId);
    });

    connect(worker, &FFmpegWorker::openInputFailed,
            this, [this, cameraId](const QString& reason) {
        emit cameraOffline(cameraId);
    });

    connect(worker, &FFmpegWorker::frameReady,
            queue, &FrameQueue::pushFrame,
            Qt::QueuedConnection);

    QThread* thread = new QThread(this);
    m_threads.insert(cameraId, thread);

    connect(thread, &QThread::started,
            worker, &FFmpegWorker::startDecoding);

    connect(worker, &FFmpegWorker::finished,
            thread, &QThread::quit);

    connect(worker, &FFmpegWorker::finished,
            worker, &QObject::deleteLater);

    connect(thread, &QThread::finished,
            thread, &QObject::deleteLater);

    worker->moveToThread(thread);
    thread->start();

    s_playbackPositionByCamera[cameraId] = 0;
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[FrigateAPI] Live mode resumed for" << cameraId;
}
