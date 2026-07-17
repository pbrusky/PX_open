#ifndef FRIGATESTREAMMANAGER_H
#define FRIGATESTREAMMANAGER_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QThread>

class FrameQueue;
class FFmpegWorker;

class FrigateStreamManager : public QObject
{
    Q_OBJECT

public:
    explicit FrigateStreamManager(QObject* parent = nullptr);
    ~FrigateStreamManager();   // ⭐ REQUIRED for clean shutdown

    //
    // Server configuration
    //
    void setServer(const QString& server);
    void setServerIp(const QString& ip);

    //
    // Streaming API
    //
    QObject* getQueue(const QString& cameraName);
    QObject* getPlaybackQueue(const QString& cameraName);

    void startStream(const QString& cameraName);
    void stopStream(const QString& cameraName);
    void stopAllStreams();
    void restartStream(const QString& cameraName);

signals:
    //
    // Online/offline state
    //
    void cameraOnline(QString id);
    void cameraOffline(QString id);

private:
    QString m_server;
    QString m_serverIp;

    // Live queues
    QHash<QString, FrameQueue*> m_queues;

    // Playback queues
    QHash<QString, FrameQueue*> m_playbackQueues;

    // FFmpeg workers
    QHash<QString, FFmpegWorker*> m_workers;
    QHash<QString, FFmpegWorker*> m_playbackWorkers;

    // Worker threads
    QHash<QString, QThread*> m_threads;
    QHash<QString, QThread*> m_playbackThreads;
};

#endif
