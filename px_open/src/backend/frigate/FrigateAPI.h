#ifndef FRIGATEAPI_H
#define FRIGATEAPI_H

#include <QObject>
#include <QString>
#include <QVariantList>

class FrigateCameraManager;
class FrigateStreamManager;
class FrigateTimeline;
class FrigatePlayback;
class FrigateOnvif;

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

    Q_INVOKABLE void setServer(QString server);
    Q_INVOKABLE void setModuleServer(QString server);
    Q_INVOKABLE void setServerIp(QString ip);

    //
    // Camera API
    //
    Q_INVOKABLE void loadCameras();
    Q_INVOKABLE void addCamera(QString id, QString url, bool record);
    Q_INVOKABLE void editCamera(QString id, QString url);
    Q_INVOKABLE void removeCamera(QString id);
    Q_INVOKABLE bool isCameraOnline(const QString& id) const;
    Q_INVOKABLE QVariantList getCameraList() const;

    //
    // ONVIF
    //
    Q_INVOKABLE void discoverOnvif(const QString& username, const QString& password);
    Q_INVOKABLE QVariantList getOnvifProgress();
    Q_INVOKABLE void getRtsp(const QString& ip, const QString& username, const QString& password);

    //
    // Streaming
    //
    Q_INVOKABLE QObject* getQueue(const QString& cameraName);
    Q_INVOKABLE QObject* getPlaybackQueue(const QString& cameraName);
    Q_INVOKABLE void stopStream(const QString& cameraName);
    Q_INVOKABLE void stopAllStreams();

    //
    // Timeline
    //
    Q_INVOKABLE void loadRecordings(const QString& cameraId);
    Q_INVOKABLE void loadEvents(const QString& cameraId);
    Q_INVOKABLE QVariantList getRecordingsForCamera(const QString& cameraId);
    Q_INVOKABLE QVariantList getEventsForCamera(const QString& cameraId);

    //
    // Playback
    //
    Q_INVOKABLE void seek(const QString& cameraId, qint64 timestampMs);
    Q_INVOKABLE void startPlayback(const QString& cameraId, qint64 timestampMs);
    Q_INVOKABLE qint64 currentPosition(const QString& cameraId);
    Q_INVOKABLE void switchToLive(const QString& cameraId);

    //
    // Module Information
    //
    Q_INVOKABLE void loadModuleInformation();

    //
    // RTSP Testing
    //
    Q_INVOKABLE void testRtsp(const QString& url);

signals:
    //
    // Server properties
    //
    void serverChanged();
    void moduleServerChanged();
    void serverIpChanged();

    //
    // Camera list
    //
    void camerasLoaded(QVariantList cameras);

    //
    // Camera CRUD
    //
    void cameraAddResult(bool ok, QString message);
    void cameraEditResult(bool ok, QString message);
    void cameraRemoveResult(bool ok, QString message);

    //
    // Camera online/offline
    //
    void cameraOnline(QString id);
    void cameraOffline(QString id);

    //
    // ONVIF
    //
    void onvifDevicesDiscovered(QVariantList devices);
    void onvifProgress(QVariantList devices);
    void rtspResolved(QString rtsp);
    void onvifError(QString message);

    //
    // Timeline
    //
    void recordingsLoaded(const QString& cameraId, const QVariantList& segments);
    void eventsLoaded(const QString& cameraId, const QVariantList& events);

    //
    // Playback
    //
    void playbackPositionChanged(const QString& cameraId, qint64 positionMs);

    //
    // Module Information
    //
    void moduleInformationReceived(QString name,
                                   QString version,
                                   QString status,
                                   QString systemId,
                                   QString moduleId);

    //
    // RTSP Test Result
    //
    void rtspTestResult(bool ok, QString message);

private:
    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    FrigateCameraManager* m_cameraManager;
    FrigateStreamManager* m_streamManager;
    FrigateTimeline* m_timeline;
    FrigatePlayback* m_playback;
    FrigateOnvif* m_onvif;
};

#endif
