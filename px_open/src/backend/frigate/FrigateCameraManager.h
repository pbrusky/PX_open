#ifndef FRIGATECAMERAMANAGER_H
#define FRIGATECAMERAMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <QNetworkAccessManager>

class FrigateCameraManager : public QObject
{
    Q_OBJECT

public:
    explicit FrigateCameraManager(QObject* parent = nullptr);

    // Server configuration
    void setServer(const QString& server);
    void setModuleServer(const QString& server);
    void setServerIp(const QString& ip);

    // Camera API
    void loadCameras();
    void addCamera(const QString& id, const QString& url, bool record);
    void editCamera(const QString& id, const QString& url);
    void removeCamera(const QString& id);

    bool isCameraOnline(const QString& id) const;

    // Full camera list for QML
    QVariantList getCameraList() const;

    // Camera metadata (resolution, fps, codec, bitrate)
    QVariantMap getCameraMetadata(const QString& id) const;

    // Module information
    void loadModuleInformation();

signals:
    // Camera list
    void camerasLoaded(QVariantList cameras);

    // Camera CRUD
    void cameraAddResult(bool ok, QString message);
    void cameraEditResult(bool ok, QString message);
    void cameraRemoveResult(bool ok, QString message);

    // Camera online/offline
    void cameraOnline(QString id);
    void cameraOffline(QString id);

    // Module information
    void moduleInformationReceived(QString name,
                                   QString version,
                                   QString status,
                                   QString systemId,
                                   QString moduleId);

private:
    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    QNetworkAccessManager* m_net;

    // Online/offline state map
    QHash<QString, bool> m_cameraOnline;

    // Full camera list storage
    QVariantList m_cameraList;

    // Metadata storage
    QHash<QString, QVariantMap> m_cameraMetadata;
};

#endif
