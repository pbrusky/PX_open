#include "FrigateCameraManager.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
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
                entry["id"] = id;
                entry["name"] = id;
                entry["streamUrl"] = QString("rtsp://%1:8554/%2")
                                        .arg(m_serverIp, id);

                // Metadata extraction
                QVariantMap meta;
                meta["resolution"] = camObj.value("resolution").toString();
                meta["fps"]        = camObj.value("fps").toDouble();
                meta["codec"]      = camObj.value("codec").toString();
                meta["bitrate"]    = camObj.value("bitrate").toInt();
                meta["streamType"] = camObj.value("streamType").toString();

                m_cameraMetadata[id] = meta;

                m_cameraList.append(entry);

                // Mark camera online by default
                m_cameraOnline[id] = true;
                emit cameraOnline(id);
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
    obj["id"] = id;
    obj["rtsp"] = url;
    obj["record"] = record;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root = doc.object();

        bool ok = root.value("status").toString() == "ok";
        emit cameraAddResult(ok, ok ? "Camera added" : "Failed to add camera");

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
    obj["id"] = id;
    obj["rtsp"] = url;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        bool ok = doc.object()["status"].toString() == "ok";

        emit cameraEditResult(ok, ok ? "OK" : "Failed to update camera");

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
        bool ok = doc.object()["status"].toString() == "ok";

        emit cameraRemoveResult(ok, ok ? "Camera removed" : "Failed to remove camera");

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
        // ⭐ FIXED: 5 arguments, not 6
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
        QJsonObject root = doc.object();

        emit moduleInformationReceived(
            root.value("name").toString(),
            root.value("version").toString(),
            root.value("status").toString(),
            root.value("systemId").toString(),
            root.value("moduleId").toString()
        );
    });
}
