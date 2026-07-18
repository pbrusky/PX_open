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
    ~FrigateStreamManager();

    // Server configuration
    void setServer(const QString& server);
    void setServerIp(const QString& ip);

    // Streaming API
    Q_INVOKABLE QObject* getQueue(const QString& cameraName);
    Q_INVOKABLE QObject* getPlaybackQueue(const QString& cameraName);

    void startStream(const QString& cameraName);
    void stopStream(const QString& cameraName);
    void stopAllStreams();
    void restartStream(const QString& cameraName);

    // Worker access for QML
    Q_INVOKABLE QObject* getWorker(const QString& cameraName);
    Q_INVOKABLE QObject* getPlaybackWorker(const QString& cameraName);

signals:
    void cameraOnline(QString id);
    void cameraOffline(QString id);

private:
    QString m_server;
    QString m_serverIp;

    // Live queues
    QHash<QString, FrameQueue*> m_queues;

    // Playback queues
    QHash<QString, FrameQueue*> m_playbackQueues;

    // Workers
    QHash<QString, FFmpegWorker*> m_workers;
    QHash<QString, FFmpegWorker*> m_playbackWorkers;

    // Worker threads
    QHash<QString, QThread*> m_threads;
    QHash<QString, QThread*> m_playbackThreads;
};

#endif
