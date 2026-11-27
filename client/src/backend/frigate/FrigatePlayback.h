#ifndef FRIGATEPLAYBACK_H
#define FRIGATEPLAYBACK_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QMutex>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFile>
#include <QByteArray>
#include <QList>

class FrameQueue;
class FFmpegWorker;
class QThread;

struct SegmentClipState
{
    QString key;
    QString path;
    QString cameraId;
    QString vodUrl;
    QString clipUrl;
    qint64 startSec = 0;
    qint64 endSec = 0;
    qint64 targetSec = 0;
    qint64 queuedTargetSec = 0;
    int gen = 0;
    qint64 startWallMs = 0;
    QString windowKey;
    qint64 windowStartSec = 0;
    qint64 windowEndSec = 0;
    QList<double> durations;
    bool waitingForManifest = false;
    qint64 fileOffsetSec = 0;
    int firstPart = 1;
    int requiredParts = 1;
    int nextPart = 0;   // 0 = init segment, >=1 = absolute hour segment index
    int maxParts = 0;
    QFile* file = nullptr;
    QNetworkReply* reply = nullptr;
    bool startWorker = false;
    bool workerStarted = false;
    bool ready = false;     // init + first segment are on disk
    bool complete = false;  // all segments fetched
};

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
    void warmRecordings(const QString& cameraId, qint64 timestampMs);

    void switchToLive(const QString& cameraId);
    void stopPlayback(const QString& cameraId);

signals:
    void playbackPositionChanged(const QString& cameraId, qint64 positionMs);
    void playbackStarted(const QString& cameraId);
    void playbackStopped(const QString& cameraId);
    void playbackError(const QString& cameraId, const QString& message);
    void cameraOnline(QString id);
    void cameraOffline(QString id);

private:
    void stopWorkerAsync(const QString& cameraId);
    void cancelDownload(const QString& cameraId);
    void startUrlWorker(const QString& cameraId, int gen, const QString& url,
                        const QString& fallbackUrl = QString(), qint64 startOffsetSec = 0);
    void startLocalWorker(const QString& cameraId, int gen, const QString& localPath,
                          qint64 startOffsetSec = 0);
    void downloadThenPlay(const QString& cameraId, int gen, const QString& remoteUrl);
    void beginClip(const QString& cameraId, int gen, qint64 startSec, qint64 endSec, bool resetQueue);
    void continuePlayback(const QString& cameraId, int gen);
    static QString clipKey(const QString& cameraId, qint64 startSec, qint64 endSec);
    void cancelOtherHourManifests(const QString& cameraId, qint64 hourStart);
    void requestHourManifest(const QString& cameraId, qint64 hourStart, const QString& key);
    void prepareHourWindow(SegmentClipState* clip);
    void startSegmentDownload(SegmentClipState* clip);
    void cancelHourManifests(const QString& cameraId);
    void startSegmentClip(const QString& cameraId, int gen, qint64 startSec, qint64 endSec,
                          qint64 targetSec, bool startWorker, bool prefetch,
                          const QString& vodUrl, const QString& clipUrl);
    void requestNextSegmentPart(SegmentClipState* clip);
    void cancelSegmentClip(const QString& key);
    void cancelCameraSegmentClips(const QString& cameraId);
    void prefetchNextClip(const QString& cameraId, int gen, qint64 startSec, qint64 endSec);
    void cancelPrefetch(const QString& cameraId);
    void endPlaybackSession(const QString& cameraId);
    void cleanupTempFile(const QString& cameraId);

    QString m_server;
    QString m_moduleServer;
    QString m_serverIp;

    QNetworkAccessManager* m_net = nullptr;

    QMutex m_mutex;
    QHash<QString, qint64> m_playbackPositionByCamera;
    QHash<QString, qint64> m_clipStartWallMs;
    QHash<QString, qint64> m_playbackEndSecByCamera;
    QHash<QString, bool> m_playbackActiveByCamera;
    QHash<QString, qint64> m_lastSeekMs;
    QHash<QString, qint64> m_pendingTargetSec;
    QHash<QString, int> m_seekGen;

    QHash<QString, FrameQueue*> m_playbackQueues;
    QHash<QString, FFmpegWorker*> m_playbackWorkers;
    QHash<QString, QThread*> m_playbackThreads;

    QHash<QString, QNetworkReply*> m_downloadReplies;
    QHash<QString, QString> m_tempFiles;
    QHash<QString, QFile*> m_downloadFiles;
    QHash<QString, bool> m_downloadStartedPlay;  // true once local worker started mid-download

    QHash<QString, SegmentClipState*> m_segmentClips;
    QHash<QString, QString> m_activeClipKey;
    QHash<QString, QString> m_prefetchClipKey;
    QHash<QString, QByteArray> m_hourManifestCache;
    QHash<QString, QList<double>> m_hourDurationsCache;
    QHash<QString, QNetworkReply*> m_hourManifestReplies;
};

#endif