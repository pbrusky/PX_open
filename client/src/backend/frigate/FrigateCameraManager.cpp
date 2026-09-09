#include "FrigateCameraManager.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QSet>
#include <QUrl>

FrigateCameraManager::FrigateCameraManager(QObject* parent)
    : QObject(parent),
      m_net(new QNetworkAccessManager(this)),
      m_statsTimer(new QTimer(this))
{
    m_statsTimer->setInterval(10000); // every 10s
    connect(m_statsTimer, &QTimer::timeout, this, &FrigateCameraManager::refreshCameraStats);
}

void FrigateCameraManager::setServer(const QString& server)
{
    m_server = server;
    if (m_server.isEmpty()) {
        m_statsTimer->stop();
        clearCameraOnlineState();
    }
}

void FrigateCameraManager::setModuleServer(const QString& server)
{
    m_moduleServer = server;
}

void FrigateCameraManager::setServerIp(const QString& ip)
{
    m_serverIp = ip;
}

void FrigateCameraManager::setCameraOnline(const QString& id, bool online)
{
    if (id.trimmed().isEmpty())
        return;

    const bool prev = m_cameraOnline.value(id, false);
    if (prev == online)
        return;

    m_cameraOnline[id] = online;
    if (online)
        emit cameraOnline(id);
    else
        emit cameraOffline(id);
}

void FrigateCameraManager::clearCameraOnlineState()
{
    const QStringList ids = m_cameraOnline.keys();
    m_cameraOnline.clear();
    for (const QString& id : ids)
        emit cameraOffline(id);
}

void FrigateCameraManager::refreshCameraStats()
{
    if (m_server.isEmpty())
        return;

    QUrl url(m_server + "/api/stats");
    QNetworkRequest req(url);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray data = reply->readAll();
        reply->deleteLater();
        if (data.isEmpty())
            return;
        applyStatsPayload(data);
    });
}

void FrigateCameraManager::applyStatsPayload(const QByteArray& data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
        return;

    const QJsonObject root = doc.object();
    const QJsonObject cams = root.value(QStringLiteral("cameras")).toObject();
    if (cams.isEmpty())
        return;

    QSet<QString> known;
    for (const QVariant& v : m_cameraList) {
        const QString id = v.toMap().value(QStringLiteral("id")).toString();
        if (!id.isEmpty())
            known.insert(id);
    }

    for (auto it = cams.begin(); it != cams.end(); ++it) {
        const QString id = it.key();
        if (!known.isEmpty() && !known.contains(id))
            continue;

        const QJsonObject cam = it.value().toObject();

        const double cameraFps  = cam.value(QStringLiteral("camera_fps")).toDouble(0.0);
        const double processFps = cam.value(QStringLiteral("process_fps")).toDouble(0.0);
        const double detection  = cam.value(QStringLiteral("detection_fps")).toDouble(0.0);
        const bool ffmpegPid    = cam.value(QStringLiteral("ffmpeg_pid")).toInt(0) > 0
                               || cam.value(QStringLiteral("pid")).toInt(0) > 0;

        const bool online = (cameraFps > 0.05)
                         || (processFps > 0.05)
                         || (detection > 0.0)
                         || ffmpegPid;

        setCameraOnline(id, online);
    }
}

void FrigateCameraManager::loadCameras()
{
    if (m_server.isEmpty()) {
        m_cameraList.clear();
        m_cameraOnline.clear();
        m_statsTimer->stop();
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
        QHash<QString, bool> previousOnline = m_cameraOnline;
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

                QString subPath;
                QString mainPath;
                if (camObj.contains("ffmpeg")) {
                    QJsonObject ff = camObj["ffmpeg"].toObject();
                    if (ff.contains("inputs")) {
                        QJsonArray inputs = ff["inputs"].toArray();
                        for (const QJsonValue& v : inputs) {
                            QJsonObject inp = v.toObject();
                            const QString path = inp.value("path").toString().trimmed();
                            if (path.isEmpty())
                                continue;
                            QJsonArray roles = inp.value("roles").toArray();
                            bool isDetect = false;
                            bool isRecord = false;
                            for (const QJsonValue& r : roles) {
                                const QString role = r.toString();
                                if (role == QLatin1String("detect"))
                                    isDetect = true;
                                if (role == QLatin1String("record"))
                                    isRecord = true;
                            }
                            if (isRecord && mainPath.isEmpty())
                                mainPath = path;
                            if (isDetect && subPath.isEmpty())
                                subPath = path;
                            if (subPath.isEmpty())
                                subPath = path;
                            if (mainPath.isEmpty())
                                mainPath = path;
                        }
                    }
                }
                if (mainPath.isEmpty())
                    mainPath = subPath;
                if (subPath.isEmpty())
                    subPath = mainPath;

                entry["rtsp"]      = subPath;
                entry["streamUrl"] = subPath;
                entry["mainUrl"]   = mainPath;
                entry["subUrl"]    = subPath;

                QString username = camObj.value("username").toString();
                QString password = camObj.value("password").toString();
                QString ip;

                const QString parseSrc = mainPath.isEmpty() ? subPath : mainPath;
                if (parseSrc.startsWith("rtsp://")) {
                    QString withoutPrefix = parseSrc.mid(7);
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
                        ip = (slashIndex > 0) ? hostPart.left(slashIndex) : hostPart;
                    } else {
                        int slashIndex = withoutPrefix.indexOf("/");
                        ip = (slashIndex > 0) ? withoutPrefix.left(slashIndex) : withoutPrefix;
                    }
                }

                entry["username"]    = username;
                entry["password"]    = password;
                entry["ip"]          = ip;
                entry["resolution"]  = "";
                entry["fps"]         = 0;
                entry["codec"]       = "";
                entry["bitrateKbps"] = 0;
                entry["streamType"]  = "rtsp";
                entry["isOnline"]    = previousOnline.value(id, false);

                m_cameraList.append(entry);

                const bool wasOnline = previousOnline.value(id, false);
                m_cameraOnline[id] = wasOnline;
                if (wasOnline)
                    emit cameraOnline(id);
                else
                    emit cameraOffline(id);

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

        refreshCameraStats();
        if (!m_statsTimer->isActive())
            m_statsTimer->start();
    });
}

void FrigateCameraManager::addCamera(const QString& id,
                                     const QString& mainUrl,
                                     const QString& subUrl,
                                     bool record)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraAddResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/addCamera");
    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QString username;
    QString password;
    const QString source = mainUrl.isEmpty() ? subUrl : mainUrl;

    if (source.startsWith("rtsp://")) {
        QString withoutPrefix = source.mid(7);
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
    obj["rtsp"]     = mainUrl;
    obj["rtsp_sub"] = subUrl.isEmpty() ? mainUrl : subUrl;
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
        if (event == "cameraAddResult")
            emit cameraAddResult(ok, msg);
        else
            emit cameraAddResult(ok, ok ? "Camera added" : "Failed to add camera");
        if (ok)
            loadCameras();
    });
}

void FrigateCameraManager::editCamera(const QString& id, const QString& url)
{
    if (m_moduleServer.isEmpty()) {
        emit cameraEditResult(false, "Module server not set");
        return;
    }

    QUrl endpoint(m_moduleServer + "/api/editCamera");
    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

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
        if (event == "cameraEditResult")
            emit cameraEditResult(ok, msg);
        else
            emit cameraEditResult(ok, ok ? "OK" : "Failed to update camera");
        if (ok)
            loadCameras();
    });
}

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
        if (!ok && root.contains("ok"))
            ok = root.value("ok").toBool();
        QString msg   = root.value("message").toString();
        if (event == "cameraRemoveResult")
            emit cameraRemoveResult(ok, msg);
        else
            emit cameraRemoveResult(ok, ok ? "Camera removed" : "Failed to remove camera");
        if (ok)
            loadCameras();
    });
}

bool FrigateCameraManager::isCameraOnline(const QString& id) const
{
    return m_cameraOnline.value(id, false);
}

QVariantList FrigateCameraManager::getCameraList() const
{
    return m_cameraList;
}

QVariantMap FrigateCameraManager::getCameraMetadata(const QString& id) const
{
    return m_cameraMetadata.value(id);
}

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

void FrigateCameraManager::loadFrigateConfig()
{
    if (m_moduleServer.isEmpty()) {
        emit frigateConfigLoaded(false, QString(), QString(),
                                 QStringLiteral("No module server"));
        return;
    }

    QUrl endpoint(m_moduleServer + QStringLiteral("/api/getFrigateConfig"));
    QNetworkRequest req(endpoint);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray data = reply->readAll();
        const auto err = reply->error();
        reply->deleteLater();

        if (err != QNetworkReply::NoError) {
            emit frigateConfigLoaded(false, QString(), QString(),
                                     QStringLiteral("Network error"));
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(data).object();
        const bool ok = root.value(QStringLiteral("ok")).toBool(false);
        emit frigateConfigLoaded(
            ok,
            root.value(QStringLiteral("content")).toString(),
            root.value(QStringLiteral("path")).toString(),
            root.value(QStringLiteral("message")).toString());
    });
}

void FrigateCameraManager::saveFrigateConfig(const QString& content, bool restart)
{
    if (m_moduleServer.isEmpty()) {
        emit frigateConfigSaved(false, QStringLiteral("No module server"));
        return;
    }

    QUrl endpoint(m_moduleServer + QStringLiteral("/api/saveFrigateConfig"));
    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QJsonObject obj;
    obj.insert(QStringLiteral("content"), content);
    obj.insert(QStringLiteral("restart"), restart);

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray data = reply->readAll();
        const auto err = reply->error();
        reply->deleteLater();

        if (err != QNetworkReply::NoError) {
            emit frigateConfigSaved(false, QStringLiteral("Network error"));
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(data).object();
        const bool ok = root.value(QStringLiteral("ok")).toBool(false);
        emit frigateConfigSaved(ok, root.value(QStringLiteral("message")).toString());
    });
}

void FrigateCameraManager::loadGo2rtcConfig()
{
    if (m_moduleServer.isEmpty()) {
        emit go2rtcConfigLoaded(false, QString(), QString(),
                                QStringLiteral("No module server"));
        return;
    }

    QUrl endpoint(m_moduleServer + QStringLiteral("/api/getGo2rtcConfig"));
    QNetworkRequest req(endpoint);
    QNetworkReply* reply = m_net->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray data = reply->readAll();
        const auto err = reply->error();
        reply->deleteLater();

        if (err != QNetworkReply::NoError) {
            emit go2rtcConfigLoaded(false, QString(), QString(),
                                    QStringLiteral("Network error"));
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(data).object();
        const bool ok = root.value(QStringLiteral("ok")).toBool(false);
        emit go2rtcConfigLoaded(
            ok,
            root.value(QStringLiteral("content")).toString(),
            root.value(QStringLiteral("path")).toString(),
            root.value(QStringLiteral("message")).toString());
    });
}

void FrigateCameraManager::saveGo2rtcConfig(const QString& content, bool restart)
{
    if (m_moduleServer.isEmpty()) {
        emit go2rtcConfigSaved(false, QStringLiteral("No module server"));
        return;
    }

    QUrl endpoint(m_moduleServer + QStringLiteral("/api/saveGo2rtcConfig"));
    QNetworkRequest req(endpoint);
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QJsonObject obj;
    obj.insert(QStringLiteral("content"), content);
    obj.insert(QStringLiteral("restart"), restart);

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray data = reply->readAll();
        const auto err = reply->error();
        reply->deleteLater();

        if (err != QNetworkReply::NoError) {
            emit go2rtcConfigSaved(false, QStringLiteral("Network error"));
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(data).object();
        const bool ok = root.value(QStringLiteral("ok")).toBool(false);
        emit go2rtcConfigSaved(ok, root.value(QStringLiteral("message")).toString());
    });
}