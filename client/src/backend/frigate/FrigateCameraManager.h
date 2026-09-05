#ifndef FRIGATECAMERAMANAGER_H
#define FRIGATECAMERAMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <QNetworkAccessManager>
#include <QTimer>

class FrigateCameraManager : public QObject
{
    Q_OBJECT

public:
    explicit FrigateCameraManager(QObject* parent = nullptr);

    void setServer(const QString& server);
    void setModuleServer(const QString& server);
    void setServerIp(const QString& ip);

    void loadCameras();
    void addCamera(const QString& id,
                   const QString& mainUrl,
                   const QString& subUrl,
                   bool record);
    void editCamera(const QString& id, const QString& url);
    void removeCamera(const QString& id);

    bool isCameraOnline(const QString& id) const;
    void setCameraOnline(const QString& id, bool online);
    void clearCameraOnlineState();

    QVariantList getCameraList() const;
    QVariantMap getCameraMetadata(const QString& id) const;
    void loadModuleInformation();

    void loadFrigateConfig();
    void saveFrigateConfig(const QString& content, bool restart = true);
    void loadGo2rtcConfig();
    void saveGo2rtcConfig(const QString& content, bool restart = true);

signals:
    void camerasLoaded(QVariantList cameras);
    void cameraAddResult(bool ok, QString message);
    void cameraEditResult(bool ok, QString message);
    void cameraRemoveResult(bool ok, QString message);
    void cameraOnline(QString id);
    void cameraOffline(QString id);
    void moduleInformationReceived(QString name,
                                   QString version,
                                   QString status,
                                   QString systemId,
                                   QString moduleId);

    void frigateConfigLoaded(bool ok, QString content, QString path, QString message);
    void frigateConfigSaved(bool ok, QString message);
    void go2rtcConfigLoaded(bool ok, QString content, QString path, QString message);
    void go2rtcConfigSaved(bool ok, QString message);

private:
    void refreshCameraStats();
    void applyStatsPayload(const QByteArray& data);

    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    QNetworkAccessManager* m_net;
    QTimer* m_statsTimer;

    QHash<QString, bool> m_cameraOnline;
    QVariantList m_cameraList;
    QHash<QString, QVariantMap> m_cameraMetadata;
};

#endif