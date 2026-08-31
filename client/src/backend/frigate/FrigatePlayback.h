#ifndef FRIGATEPLAYBACK_H
#define FRIGATEPLAYBACK_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QMutex>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFile>

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
    void startUrlWorker(const QString& cameraId, int gen, const QString& url);
    void startLocalWorker(const QString& cameraId, int gen, const QString& localPath);
    void downloadThenPlay(const QString& cameraId, int gen, const QString& remoteUrl);
    void cleanupTempFile(const QString& cameraId);

    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    QNetworkAccessManager* m_net = nullptr;

    QMutex m_mutex;
    QHash<QString, qint64> m_playbackPositionByCamera;
    QHash<QString, qint64> m_lastSeekMs;
    QHash<QString, int> m_seekGen;

    QHash<QString, FrameQueue*> m_playbackQueues;
    QHash<QString, FFmpegWorker*> m_playbackWorkers;
    QHash<QString, QThread*> m_playbackThreads;

    QHash<QString, QNetworkReply*> m_downloadReplies;
    QHash<QString, QString> m_tempFiles;
    QHash<QString, QFile*> m_downloadFiles;
};

#endif