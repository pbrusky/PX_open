#include "FrigateCameraManager.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QProcess>
#include <QRegularExpression>
#include <QDebug>

FrigateCameraManager::FrigateCameraManager(QObject* parent)
    : QObject(parent),
      m_net(new QNetworkAccessManager(this))
{
}

//
// Server setters
//
void FrigateCameraManager::setServer(const QString& server)
{
    m_server = server;
}

void FrigateCameraManager::setModuleServer(const QString& server)
{
    m_moduleServer = server;
}

void FrigateCameraManager::setServerIp(const QString& ip)
{
    m_serverIp = ip;
}

//
// Load cameras from Frigate /api/config
//
void FrigateCameraManager::loadCameras()
{
    if (m_server.isEmpty()) {
        m_cameraList.clear();
        emit camerasLoaded(QVariantList());
        return;
    }

    QUrl url(m_server + "/api/config");
    QNetworkRequest req(url);

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();

        m_cameraList.clear();
        m_cameraOnline.clear();
        m_cameraMetadata.clear();

        if (root.contains("cameras")) {
            QJsonObject cams = root["cameras"].toObject();

            for (auto it = cams.begin(); it != cams.end(); ++it) {
                QString id = it.key();
                QJsonObject camObj = it.value().toObject();

                QVariantMap entry;
                entry["id"]        = id;
                entry["name"]      = id;
                entry["streamUrl"] = QString("rtsp://%1:8554/%2")
                                        .arg(m_serverIp, id);

                entry["resolution"]  = "";
                entry["fps"]         = 0;
                entry["codec"]       = "";
                entry["bitrateKbps"] = 0;
                entry["streamType"]  = "rtsp";

                m_cameraList.append(entry);

                m_cameraOnline[id] = true;
                emit cameraOnline(id);

                QString rtspUrl = entry["streamUrl"].toString();

                QProcess* ff = new QProcess(this);

                QStringList args;
                args << "-hide_banner"
                     << "-rtsp_transport" << "tcp"
                     << "-i" << rtspUrl
                     << "-t" << "1"
                     << "-f" << "null"
                     << "-";

                connect(ff, &QProcess::readyReadStandardError, this, [this, ff, id]() {
                    QString output = ff->readAllStandardError();

                    QRegularExpression reRes("(\\d{3,4})x(\\d{3,4})");
                    auto resMatch = reRes.match(output);
                    QString resolution = resMatch.hasMatch() ? resMatch.captured(0) : "";

                    QRegularExpression reFps("(\\d+(?:\\.\\d+)?)\\s?fps");
                    auto fpsMatch = reFps.match(output);
                    double fps = fpsMatch.hasMatch() ? fpsMatch.captured(1).toDouble() : 0;

                    QRegularExpression reCodec("Video:\\s*(\\w+)");
                    auto codecMatch = reCodec.match(output);
                    QString codec = codecMatch.hasMatch() ? codecMatch.captured(1) : "";

                    QRegularExpression reBitrate("(\\d+)\\s?kb/s");
                    auto brMatch = reBitrate.match(output);
                    int bitrate = brMatch.hasMatch() ? brMatch.captured(1).toInt() : 0;

                    QVariantMap meta;
                    meta["resolution"]  = resolution;
                    meta["fps"]         = fps;
                    meta["codec"]       = codec;
                    meta["bitrateKbps"] = bitrate;
                    meta["streamType"]  = "rtsp";

                    m_cameraMetadata[id] = meta;
                });

                connect(ff, &QProcess::finished, this, [this, ff, id](int, QProcess::ExitStatus) {
                    ff->deleteLater();

                    for (int i = 0; i < m_cameraList.size(); ++i) {
                        QVariantMap cam = m_cameraList[i].toMap();
                        if (cam["id"].toString() == id) {
                            QVariantMap meta = m_cameraMetadata[id];
                            for (auto it = meta.begin(); it != meta.end(); ++it)
                                cam[it.key()] = it.value();
                            m_cameraList[i] = cam;
                            break;
                        }
                    }

                    emit camerasLoaded(m_cameraList);
                });

                ff->start("ffmpeg", args);
            }
        }

        emit camerasLoaded(m_cameraList);
    });
}

//
// Add camera
//
void FrigateCameraManager::addCamera(const QString& id, const QString& url, bool record)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraAddResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/addCamera");
    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject obj;
    obj["id"]    = id;
    obj["rtsp"]  = url;
    obj["record"] = record;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root  = doc.object();

        //
        // ⭐ NEW: Parse event "cameraAddResult"
        //
        QString event = root.value("event").toString();
        bool ok = root.value("status").toString() == "ok";
        QString msg = root.value("message").toString();

        if (event == "cameraAddResult") {
            emit cameraAddResult(ok, msg);
        } else {
            // fallback for older module versions
            emit cameraAddResult(ok, ok ? "Camera added" : "Failed to add camera");
        }

        if (ok)
            loadCameras();
    });
}

//
// Edit camera
//
void FrigateCameraManager::editCamera(const QString& id, const QString& url)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraEditResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/editCamera");
    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject obj;
    obj["id"]   = id;
    obj["rtsp"] = url;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root  = doc.object();

        QString event = root.value("event").toString();
        bool ok = root.value("status").toString() == "ok";
        QString msg = root.value("message").toString();

        if (event == "cameraEditResult") {
            emit cameraEditResult(ok, msg);
        } else {
            emit cameraEditResult(ok, ok ? "OK" : "Failed to update camera");
        }

        if (ok)
            loadCameras();
    });
}

//
// Remove camera
//
void FrigateCameraManager::removeCamera(const QString& id)
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
        QJsonObject root  = doc.object();

        QString event = root.value("event").toString();
        bool ok = root.value("status").toString() == "ok";
        QString msg = root.value("message").toString();

        if (event == "cameraRemoveResult") {
            emit cameraRemoveResult(ok, msg);
        } else {
            emit cameraRemoveResult(ok, ok ? "Camera removed" : "Failed to remove camera");
        }

        if (ok)
            loadCameras();
    });
}

//
// Online/offline state
//
bool FrigateCameraManager::isCameraOnline(const QString& id) const
{
    return m_cameraOnline.value(id, false);
}

//
// Camera list accessor
//
QVariantList FrigateCameraManager::getCameraList() const
{
    return m_cameraList;
}

//
// Camera metadata accessor
//
QVariantMap FrigateCameraManager::getCameraMetadata(const QString& id) const
{
    return m_cameraMetadata.value(id);
}

//
// Load module information
//
void FrigateCameraManager::loadModuleInformation()
{
    if (m_moduleServer.isEmpty()) {
        emit moduleInformationReceived("unknown", "unknown", "error", "", "");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/moduleInfo");
    QNetworkRequest req(endpoint);

    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root  = doc.object();

        emit moduleInformationReceived(
            root.value("name").toString(),
            root.value("version").toString(),
            root.value("status").toString(),
            root.value("systemId").toString(),
            root.value("moduleId").toString()
        );
    });
}
