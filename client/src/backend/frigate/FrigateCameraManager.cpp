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
                entry["id"]   = id;
                entry["name"] = id;

                //
                // ⭐ Extract RTSP from Frigate config
                //
                QString rtsp = "";
                if (camObj.contains("ffmpeg")) {
                    QJsonObject ff = camObj["ffmpeg"].toObject();
                    if (ff.contains("inputs")) {
                        QJsonArray inputs = ff["inputs"].toArray();
                        if (!inputs.isEmpty()) {
                            QJsonObject inp = inputs[0].toObject();
                            rtsp = inp.value("path").toString();
                        }
                    }
                }

                entry["rtsp"]      = rtsp;
                entry["streamUrl"] = rtsp;   // QML compatibility

                //
                // ⭐ Username / password from config (preferred)
                //
                QString username = camObj.value("username").toString();
                QString password = camObj.value("password").toString();
                QString ip       = "";

                //
                // ⭐ Fallback: parse from RTSP if config has no creds
                //
                if (rtsp.startsWith("rtsp://")) {
                    QString withoutPrefix = rtsp.mid(7);

                    int atIndex = withoutPrefix.indexOf("@");
                    if (atIndex > 0) {
                        QString creds    = withoutPrefix.left(atIndex);
                        QString hostPart = withoutPrefix.mid(atIndex + 1);

                        int colonIndex = creds.indexOf(":");
                        if (colonIndex > 0 && (username.isEmpty() || password.isEmpty())) {
                            username = creds.left(colonIndex);
                            password = creds.mid(colonIndex + 1);
                        }

                        int slashIndex = hostPart.indexOf("/");
                        if (slashIndex > 0)
                            ip = hostPart.left(slashIndex);
                        else
                            ip = hostPart;
                    } else {
                        int slashIndex = withoutPrefix.indexOf("/");
                        if (slashIndex > 0)
                            ip = withoutPrefix.left(slashIndex);
                        else
                            ip = withoutPrefix;
                    }
                }

                entry["username"] = username;
                entry["password"] = password;
                entry["ip"]       = ip;

                //
                // Metadata (unchanged)
                //
                entry["resolution"]  = "";
                entry["fps"]         = 0;
                entry["codec"]       = "";
                entry["bitrateKbps"] = 0;
                entry["streamType"]  = "rtsp";

                m_cameraList.append(entry);

                m_cameraOnline[id] = true;
                emit cameraOnline(id);

                QVariantMap meta;
                meta["resolution"]  = "";
                meta["fps"]         = 0;
                meta["codec"]       = "";
                meta["bitrateKbps"] = 0;
                meta["streamType"]  = "rtsp";
                m_cameraMetadata[id] = meta;
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

    //
    // ⭐ Parse username/password from RTSP for module
    //
    QString username;
    QString password;

    if (url.startsWith("rtsp://")) {
        QString withoutPrefix = url.mid(7);
        int atIndex = withoutPrefix.indexOf("@");
        if (atIndex > 0) {
            QString creds = withoutPrefix.left(atIndex);
            int colonIndex = creds.indexOf(":");
            if (colonIndex > 0) {
                username = creds.left(colonIndex);
                password = creds.mid(colonIndex + 1);
            }
        }
    }

    QJsonObject obj;
    obj["id"]       = id;
    obj["rtsp"]     = url;
    obj["record"]   = record;
    obj["username"] = username;
    obj["password"] = password;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root  = doc.object();

        QString event = root.value("event").toString();
        bool ok       = root.value("status").toString() == "ok";
        QString msg   = root.value("message").toString();

        if (event == "cameraAddResult") {
            emit cameraAddResult(ok, msg);
        } else {
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

    //
    // ⭐ Parse username/password from RTSP for module
    //
    QString username;
    QString password;

    if (url.startsWith("rtsp://")) {
        QString withoutPrefix = url.mid(7);
        int atIndex = withoutPrefix.indexOf("@");
        if (atIndex > 0) {
            QString creds = withoutPrefix.left(atIndex);
            int colonIndex = creds.indexOf(":");
            if (colonIndex > 0) {
                username = creds.left(colonIndex);
                password = creds.mid(colonIndex + 1);
            }
        }
    }

    QJsonObject obj;
    obj["id"]       = id;
    obj["rtsp"]     = url;
    obj["username"] = username;
    obj["password"] = password;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        QJsonObject root  = doc.object();

        QString event = root.value("event").toString();
        bool ok       = root.value("status").toString() == "ok";
        QString msg   = root.value("message").toString();

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
        bool ok       = root.value("status").toString() == "ok";
        QString msg   = root.value("message").toString();

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
