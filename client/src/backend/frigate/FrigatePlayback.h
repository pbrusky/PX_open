#ifndef FRIGATEPLAYBACK_H
#define FRIGATEPLAYBACK_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QMutex>
#include <QProcess>
#include <QTimer>

class FrameQueue;
class FFmpegWorker;
class QThread;

class FrigatePlayback : public QObject
{
    Q_OBJECT

public:
    explicit FrigatePlayback(QObject* parent = nullptr);
    ~FrigatePlayback() override;

    void setServer(const QString& server);
    void setModuleServer(const QString& server);
    void setServerIp(const QString& ip);

    QObject* getPlaybackQueue(const QString& cameraId);

    void seek(const QString& cameraId, qint64 timestampMs);
    void startPlayback(const QString& cameraId, qint64 timestampMs);
    qint64 currentPosition(const QString& cameraId) const;

    void switchToLive(const QString& cameraId);
    void stopPlayback(const QString& cameraId);

signals:
    void playbackPositionChanged(const QString& cameraId, qint64 positionMs);
    void playbackStarted(const QString& cameraId);
    void playbackStopped(const QString& cameraId);
    void cameraOnline(QString id);
    void cameraOffline(QString id);

private:
    void stopWorkerAsync(const QString& cameraId);
    void cancelDownload(const QString& cameraId);
    void startLocalFile(const QString& cameraId, const QString& path, qint64 posMs, int gen);

    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    QMutex m_mutex;
    QHash<QString, qint64> m_playbackPositionByCamera;
    QHash<QString, qint64> m_lastSeekMs;
    QHash<QString, int> m_seekGen;

    QHash<QString, FrameQueue*> m_playbackQueues;
    QHash<QString, FFmpegWorker*> m_playbackWorkers;
    QHash<QString, QThread*> m_playbackThreads;

    QHash<QString, QProcess*> m_curlProcs;
    QHash<QString, QString> m_curlPaths;
    QHash<QString, QTimer*> m_progressTimers;
};

#endif