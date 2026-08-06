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

signals:
    void cameraOnline(QString id);
    void cameraOffline(QString id);
    void cameraStatsChanged(QString cameraName, QString resolution,
                            double fps, int bitrateKbps, QString codec);
    void fullscreenFrameReady(QString cameraName);
    void fullscreenUsingSub(QString cameraName);

private:
    void stopFullscreenInternal(const QString& cameraName);
    void startFullscreenWorker(const QString& cameraName,
                               FrameQueue* queue,
                               const QString& url,
                               bool isFallback);

    QString m_server;
    QString m_serverIp;

    QSet<QString> m_mainMissing;
    QSet<QString> m_fullscreenFrameNotified;

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