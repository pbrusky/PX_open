#ifndef FRIGATEPLAYBACK_H
#define FRIGATEPLAYBACK_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QHash>

class FrameQueue;
class FFmpegWorker;
class QThread;

class FrigatePlayback : public QObject
{
    Q_OBJECT

public:
    explicit FrigatePlayback(QObject* parent = nullptr);

    //
    // Server configuration
    //
    void setServer(const QString& server);
    void setModuleServer(const QString& server);
    void setServerIp(const QString& ip);

    //
    // Playback API
    //
    QObject* getPlaybackQueue(const QString& cameraId);

    void seek(const QString& cameraId, qint64 timestampMs);
    void startPlayback(const QString& cameraId, qint64 timestampMs);
    qint64 currentPosition(const QString& cameraId) const;

    void switchToLive(const QString& cameraId);

signals:
    void playbackPositionChanged(const QString& cameraId, qint64 positionMs);
    void cameraOnline(QString id);
    void cameraOffline(QString id);

private:
    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    // Playback position tracking
    QHash<QString, qint64> m_playbackPositionByCamera;

    // Playback queues
    QHash<QString, FrameQueue*> m_playbackQueues;

    // Playback workers
    QHash<QString, FFmpegWorker*> m_playbackWorkers;

    // Playback threads
    QHash<QString, QThread*> m_playbackThreads;
};

#endif
