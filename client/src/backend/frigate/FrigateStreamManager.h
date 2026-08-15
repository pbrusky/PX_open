#ifndef FRIGATESTREAMMANAGER_H
#define FRIGATESTREAMMANAGER_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QSet>
#include <QThread>

class FrameQueue;
class FFmpegWorker;

class FrigateStreamManager : public QObject
{
    Q_OBJECT

public:
    explicit FrigateStreamManager(QObject* parent = nullptr);
    ~FrigateStreamManager();

    void setServer(const QString& server);
    void setServerIp(const QString& ip);

    void setCameraDirectMainUrl(const QString& cameraName,
                                const QString& mainRtspUrl,
                                const QString& username = QString(),
                                const QString& password = QString());
    void clearCameraDirectMainUrls();

    Q_INVOKABLE QObject* getQueue(const QString& cameraName);
    Q_INVOKABLE QObject* getFullscreenQueue(const QString& cameraName);
    Q_INVOKABLE QObject* getPlaybackQueue(const QString& cameraName);

    void stopStream(const QString& cameraName);
    void restartStream(const QString& cameraName);

    Q_INVOKABLE void stopFullscreenStream(const QString& cameraName);
    Q_INVOKABLE void stopAllFullscreenStreams();
    Q_INVOKABLE void stopAllStreams();
    Q_INVOKABLE void stopAllStreamsAndWait(int timeoutMs = 3000);

    Q_INVOKABLE QObject* getWorker(const QString& cameraName);
    Q_INVOKABLE QObject* getPlaybackWorker(const QString& cameraName);

    Q_INVOKABLE QString cameraResolution(const QString& cameraName) const;
    Q_INVOKABLE double cameraFps(const QString& cameraName) const;
    Q_INVOKABLE int cameraBitrateKbps(const QString& cameraName) const;
    Q_INVOKABLE QString cameraCodec(const QString& cameraName) const;

    Q_INVOKABLE bool isFullscreenTrueMain(const QString& cameraName) const;

signals:
    void cameraOnline(QString id);
    void cameraOffline(QString id);
    void cameraStatsChanged(QString cameraName, QString resolution,
                            double fps, int bitrateKbps, QString codec);
    void fullscreenFrameReady(QString cameraName);
    void fullscreenUsingSub(QString cameraName);
    void fullscreenMainStatus(QString cameraName, bool isTrueMain);

private:
    void stopFullscreenInternal(const QString& cameraName);
    // stage 0 = go2rtc name_main, 1 = direct camera main, 2 = go2rtc name (sub)
    void startFullscreenWorker(const QString& cameraName,
                               FrameQueue* queue,
                               int stage);
    QString urlForFullscreenStage(const QString& cameraName, int stage) const;
    static QString injectRtspAuth(const QString& url,
                                  const QString& user,
                                  const QString& pass);

    QString m_server;
    QString m_serverIp;

    QSet<QString> m_mainMissing;
    QSet<QString> m_fullscreenFrameNotified;
    QSet<QString> m_fullscreenIsTrueMain;

    QHash<QString, QString> m_directMainUrls;
    QHash<QString, QString> m_cameraUser;
    QHash<QString, QString> m_cameraPass;

    QHash<QString, FrameQueue*>   m_queues;
    QHash<QString, FFmpegWorker*> m_workers;
    QHash<QString, QThread*>      m_threads;

    QHash<QString, FrameQueue*>   m_fullscreenQueues;
    QHash<QString, FFmpegWorker*> m_fullscreenWorkers;
    QHash<QString, QThread*>      m_fullscreenThreads;

    QHash<QString, FrameQueue*>   m_playbackQueues;
    QHash<QString, FFmpegWorker*> m_playbackWorkers;
    QHash<QString, QThread*>      m_playbackThreads;

    QHash<QString, QString> m_statResolution;
    QHash<QString, double>  m_statFps;
    QHash<QString, int>     m_statBitrate;
    QHash<QString, QString> m_statCodec;
};

#endif