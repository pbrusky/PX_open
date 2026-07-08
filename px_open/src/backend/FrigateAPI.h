#ifndef FRIGATEAPI_H
#define FRIGATEAPI_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QString>
#include <QVariantList>
#include <QHash>
#include <QMap>
#include <QThread>

#include "FrameQueue.h"
#include "FFmpegWorker.h"

class FrigateAPI : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString server READ server WRITE setServer NOTIFY serverChanged)
    Q_PROPERTY(QString moduleServer READ moduleServer WRITE setModuleServer NOTIFY moduleServerChanged)
    Q_PROPERTY(QString serverIp READ serverIp WRITE setServerIp NOTIFY serverIpChanged)

public:
    explicit FrigateAPI(QObject* parent = nullptr);

    QString server() const { return m_server; }
    QString moduleServer() const { return m_moduleServer; }
    QString serverIp() const { return m_serverIp; }

    //
    // ⭐ Server setters
    //
    Q_INVOKABLE void setServer(QString server);
    Q_INVOKABLE void setModuleServer(QString server);
    Q_INVOKABLE void setServerIp(QString ip);

    //
    // ⭐ Module + camera management
    //
    Q_INVOKABLE void loadModuleInformation();
    Q_INVOKABLE void loadCameras();

    Q_INVOKABLE void addCamera(QString id, QString url);
    Q_INVOKABLE void editCamera(QString id, QString url);
    Q_INVOKABLE void removeCamera(QString id);

    Q_INVOKABLE void discoverOnvif();
    Q_INVOKABLE void testRtsp(const QString& url);

    //
    // ⭐ Live streaming
    //
    Q_INVOKABLE QObject* getQueue(const QString& cameraName);
    Q_INVOKABLE void stopStream(const QString& cameraName);   // stop one camera
    Q_INVOKABLE void stopAllStreams();                        // global shutdown

    //
    // ⭐ Timeline backend
    //
    Q_INVOKABLE void loadRecordings(const QString& cameraId);
    Q_INVOKABLE void loadEvents(const QString& cameraId);
    Q_INVOKABLE void seek(const QString& cameraId, qint64 timestampMs);

    // NX-style timeline data accessors for QML
    Q_INVOKABLE QVariantList getRecordingsForCamera(const QString& cameraId);
    Q_INVOKABLE QVariantList getEventsForCamera(const QString& cameraId);
    Q_INVOKABLE qint64 currentPosition(const QString& cameraId);

    //
    // ⭐ Playback backend
    //
    Q_INVOKABLE void startPlayback(const QString& cameraId, qint64 timestampMs);
    Q_INVOKABLE void switchToLive(const QString& cameraId);

    //
    // ⭐ Add Camera Popup “Use” button support
    //
    Q_INVOKABLE void applyNewCameraRtsp(const QString& id, const QString& url);

signals:
    //
    // ⭐ Server signals
    //
    void serverChanged();
    void moduleServerChanged();
    void serverIpChanged();

    //
    // ⭐ Module info
    //
    void moduleInformationReceived(QString name,
                                   QString version,
                                   QString status,
                                   QString systemId,
                                   QString moduleId);

    //
    // ⭐ Camera list
    //
    void camerasLoaded(QVariantList cameras);

    //
    // ⭐ Camera CRUD
    //
    void cameraAddResult(bool ok, QString message);
    void cameraEditResult(bool ok, QString message);
    void cameraRemoveResult(bool ok, QString message);

    //
    // ⭐ ONVIF
    //
    void onvifDevicesDiscovered(QVariantList devices);

    //
    // ⭐ RTSP test
    //
    void rtspTestResult(bool ok, QString message);

    //
    // ⭐ Camera online/offline
    //
    void cameraOnline(QString id);
    void cameraOffline(QString id);

    //
    // ⭐ Timeline signals
    //
    void recordingsLoaded(const QString& cameraId, const QVariantList& segments);
    void eventsLoaded(const QString& cameraId, const QVariantList& events);

    //
    // ⭐ Playback signals
    //
    void playbackPositionChanged(const QString& cameraId, qint64 positionMs);

private:
    //
    // ⭐ Internal helpers
    //
    void checkCameraReachable(const QString& cameraName);

    //
    // ⭐ Members
    //
    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    QNetworkAccessManager* m_net;

    QHash<QString, FrameQueue*> m_queues;
    QHash<QString, FFmpegWorker*> m_workers;
    QMap<QString, QThread*> m_threads;

    // NX-style timeline caches
    QHash<QString, QVariantList> m_recordingsByCamera;
    QHash<QString, QVariantList> m_eventsByCamera;
    QHash<QString, qint64>       m_playbackPositionByCamera;
};

#endif // FRIGATEAPI_H
