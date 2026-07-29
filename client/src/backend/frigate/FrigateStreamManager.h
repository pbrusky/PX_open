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

    void setServer(const QString& server);
    void setServerIp(const QString& ip);

    Q_INVOKABLE QObject* getQueue(const QString& cameraName);
    Q_INVOKABLE QObject* getFullscreenQueue(const QString& cameraName);
    Q_INVOKABLE QObject* getPlaybackQueue(const QString& cameraName);

    void stopStream(const QString& cameraName);
    void restartStream(const QString& cameraName);
    Q_INVOKABLE void stopAllStreams();

    Q_INVOKABLE QObject* getWorker(const QString& cameraName);
    Q_INVOKABLE QObject* getPlaybackWorker(const QString& cameraName);

signals:
    void cameraOnline(QString id);
    void cameraOffline(QString id);

private:
    QString m_server;
    QString m_serverIp;

    QHash<QString, FrameQueue*>   m_queues;
    QHash<QString, FFmpegWorker*> m_workers;
    QHash<QString, QThread*>      m_threads;

    QHash<QString, FrameQueue*>   m_fullscreenQueues;
    QHash<QString, FFmpegWorker*> m_fullscreenWorkers;
    QHash<QString, QThread*>      m_fullscreenThreads;

    QHash<QString, FrameQueue*>   m_playbackQueues;
    QHash<QString, FFmpegWorker*> m_playbackWorkers;
    QHash<QString, QThread*>      m_playbackThreads;
};

#endif // FRIGATESTREAMMANAGER_H