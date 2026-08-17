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

private:
    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    QNetworkAccessManager* m_net;

    QHash<QString, bool> m_cameraOnline;
    QVariantList m_cameraList;
    QHash<QString, QVariantMap> m_cameraMetadata;
};

#endif
