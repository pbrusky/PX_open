#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QMutexLocker>
#include <QTimer>
#include <QMetaObject>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QUrl>

#include <cmath>

namespace {
constexpr qint64 kClipBeforeSec = 1;
constexpr qint64 kClipInitialAfterSec = 29;
constexpr qint64 kClipContinueAfterSec = 60;
constexpr qint64 kClipMinLenSec = 10;
// The current clip is decoded from a local file, so warming the next range
// cannot compete with playback. Give the UI a moment to settle, then start
// preparing the next clip immediately.
constexpr int kPrefetchDelayMs = 1000;
}

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
{
}

FrigatePlayback::~FrigatePlayback()
{
    for (auto it = m_seekGen.begin(); it != m_seekGen.end(); ++it)
        it.value() = it.value() + 1;

    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys)
        stopWorkerAsync(id);

    const QStringList dlKeys = m_downloadReplies.keys();
    for (const QString& id : dlKeys)
        cancelDownload(id);

    const QStringList segmentKeys = m_segmentClips.keys();
    for (const QString& key : segmentKeys)
        cancelSegmentClip(key);

    for (QNetworkReply* reply : m_hourManifestReplies.values()) {
        if (reply) {
            reply->disconnect(this);
            reply->abort();
            reply->deleteLater();
        }
    }
    m_hourManifestReplies.clear();

    for (auto it = m_tempFiles.begin(); it != m_tempFiles.end(); ++it) {
        if (!it.value().isEmpty())
            QFile::remove(it.value());
    }
    m_tempFiles.clear();
    m_downloadStartedPlay.clear();
}

void FrigatePlayback::setServer(const QString& server)
{
    m_server = server;
    while (m_server.endsWith(QLatin1Char('/')))
        m_server.chop(1);
}

void FrigatePlayback::setModuleServer(const QString& server)
{
    m_moduleServer = server;
    while (m_moduleServer.endsWith(QLatin1Char('/')))
        m_moduleServer.chop(1);
}

void FrigatePlayback::setServerIp(const QString& ip)
{
    m_serverIp = ip;
}

QObject* FrigatePlayback::getPlaybackQueue(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty())
        return nullptr;

    QMutexLocker lock(&m_mutex);
    if (m_playbackQueues.contains(cameraId))
        return m_playbackQueues.value(cameraId);

    FrameQueue* queue = new FrameQueue(this);
    queue->setMaxSize(4);
    m_playbackQueues.insert(cameraId, queue);
    return queue;
}

void FrigatePlayback::cancelDownload(const QString& cameraId)
{
    QNetworkReply* reply = m_downloadReplies.take(cameraId);
    if (reply) {
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    QFile* file = m_downloadFiles.take(cameraId);
    if (file) {
        file->close();
        delete file;
    }
    m_downloadStartedPlay.remove(cameraId);
}

void FrigatePlayback::cleanupTempFile(const QString& cameraId)
{
    const QString path = m_tempFiles.take(cameraId);
    if (!path.isEmpty())
        QFile::remove(path);
    m_downloadStartedPlay.remove(cameraId);
}

QString FrigatePlayback::clipKey(const QString& cameraId, qint64 startSec, qint64 endSec)
{
    return QStringLiteral("%1|%2|%3").arg(cameraId).arg(startSec).arg(endSec);
}

void FrigatePlayback::cancelSegmentClip(const QString& key)
{
    SegmentClipState* clip = m_segmentClips.take(key);
    if (!clip)
        return;

    if (m_activeClipKey.value(clip->cameraId) == key)
        m_activeClipKey.remove(clip->cameraId);
    if (m_prefetchClipKey.value(clip->cameraId) == key)
        m_prefetchClipKey.remove(clip->cameraId);

    if (clip->reply) {
        clip->reply->disconnect(this);
        clip->reply->abort();
        clip->reply->deleteLater();
        clip->reply = nullptr;
    }
    if (clip->file) {
        clip->file->close();
        delete clip->file;
        clip->file = nullptr;
    }
    QFile::remove(clip->path);
    delete clip;
}

void FrigatePlayback::cancelHourManifests(const QString& cameraId)
{
    const QString prefix = cameraId + QLatin1Char('|');
    const QStringList keys = m_hourManifestReplies.keys();
    for (const QString& key : keys) {
        if (!key.startsWith(prefix))
            continue;
        QNetworkReply* reply = m_hourManifestReplies.take(key);
        if (reply) {
            reply->disconnect(this);
            reply->abort();
            reply->deleteLater();
        }
    }
}

void FrigatePlayback::cancelCameraSegmentClips(const QString& cameraId)
{
    const QString active = m_activeClipKey.take(cameraId);
    const QString prefetch = m_prefetchClipKey.take(cameraId);
    if (!active.isEmpty())
        cancelSegmentClip(active);
    if (!prefetch.isEmpty() && prefetch != active)
        cancelSegmentClip(prefetch);
    cancelHourManifests(cameraId);
}

void FrigatePlayback::cancelPrefetch(const QString& cameraId)
{
    const QString key = m_prefetchClipKey.take(cameraId);
    if (!key.isEmpty())
        cancelSegmentClip(key);
}

void FrigatePlayback::cancelOtherHourManifests(const QString& cameraId, qint64 hourStart)
{
    const QString prefix = cameraId + QLatin1Char('|');
    const QStringList keys = m_hourManifestReplies.keys();
    for (const QString& key : keys) {
        if (!key.startsWith(prefix))
            continue;
        const qint64 otherHour = key.mid(prefix.length()).toLongLong();
        if (otherHour == hourStart)
            continue;
        QNetworkReply* reply = m_hourManifestReplies.take(key);
        if (reply) {
            reply->disconnect(this);
            reply->abort();
            reply->deleteLater();
        }
    }
}

void FrigatePlayback::requestHourManifest(const QString& cameraId, qint64 hourStart, const QString& key)
{
    if (m_hourManifestCache.contains(key) || m_hourManifestReplies.contains(key))
        return;
    cancelOtherHourManifests(cameraId, hourStart);

    const QString url = QStringLiteral("%1/vod/%2/start/%3/end/%4/index.m3u8")
                            .arg(m_server, cameraId)
                            .arg(hourStart)
                            .arg(hourStart + 3600);

    QNetworkRequest req;
    req.setUrl(QUrl(url));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PX_Open/1.0"));
    req.setTransferTimeout(180000);

    QNetworkReply* reply = m_net->get(req);
    m_hourManifestReplies.insert(key, reply);

    connect(reply, &QNetworkReply::finished, this,
            [this, key, reply]() {
        if (m_hourManifestReplies.value(key) != reply) {
            reply->deleteLater();
            return;
        }
        m_hourManifestReplies.remove(key);

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        const QByteArray body = reply->readAll();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || status >= 400 || body.isEmpty()) {
            for (SegmentClipState* clip : m_segmentClips.values()) {
                if (m_segmentClips.value(clip->key) != clip || clip->windowKey != key
                        || !clip->waitingForManifest)
                    continue;
                clip->waitingForManifest = false;
                const QString vod = clip->vodUrl;
                const QString mp4 = clip->clipUrl;
                const int gen = clip->gen;
                const QString cameraId = clip->cameraId;
                cancelSegmentClip(clip->key);
                startUrlWorker(cameraId, gen, vod, mp4);
            }
            return;
        }

        QList<double> durations;
        const QByteArrayList lines = body.split('\n');
        for (const QByteArray& rawLine : lines) {
            const QByteArray line = rawLine.trimmed();
            if (!line.startsWith("#EXTINF:"))
                continue;
            QByteArray value = line.mid(8);
            const int comma = value.indexOf(',');
            if (comma > 0)
                value.truncate(comma);
            bool ok = false;
            const double d = value.trimmed().toDouble(&ok);
            if (ok && d > 0)
                durations.append(d);
        }

        m_hourManifestCache.insert(key, body);
        m_hourDurationsCache.insert(key, durations);

        for (SegmentClipState* clip : m_segmentClips.values()) {
            if (m_segmentClips.value(clip->key) != clip || clip->windowKey != key
                    || !clip->waitingForManifest)
                continue;
            clip->waitingForManifest = false;
            clip->durations = durations;
            startSegmentDownload(clip);
        }
    });
}

void FrigatePlayback::warmRecordings(const QString& cameraId, qint64 timestampMs)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty())
        return;
    const qint64 sec = timestampMs > 10000000000LL ? timestampMs / 1000 : timestampMs;
    const qint64 hourStart = (sec / 3600) * 3600;
    const QString key = QStringLiteral("%1|%2").arg(cameraId).arg(hourStart);
    requestHourManifest(cameraId, hourStart, key);
}

void FrigatePlayback::prepareHourWindow(SegmentClipState* clip)
{
    if (!clip)
        return;

    const qint64 hourStart = (clip->targetSec / 3600) * 3600;
    const QString key = QStringLiteral("%1|%2").arg(clip->cameraId).arg(hourStart);

    clip->windowKey = key;
    clip->windowStartSec = hourStart;
    clip->windowEndSec = hourStart + 3600;

    if (m_hourManifestCache.contains(key)) {
        clip->durations = m_hourDurationsCache.value(key);
        startSegmentDownload(clip);
        return;
    }

    clip->waitingForManifest = true;
    requestHourManifest(clip->cameraId, hourStart, key);
}

void FrigatePlayback::startSegmentDownload(SegmentClipState* clip)
{
    if (!clip || m_segmentClips.value(clip->key) != clip)
        return;
    if (clip->durations.isEmpty()) {
        const QString vod = clip->vodUrl;
        const QString mp4 = clip->clipUrl;
        const int gen = clip->gen;
        const QString cameraId = clip->cameraId;
        cancelSegmentClip(clip->key);
        startUrlWorker(cameraId, gen, vod, mp4);
        return;
    }

    const qint64 offStart = qMax<qint64>(0, clip->startSec - clip->windowStartSec);
    const qint64 offEnd = qMax<qint64>(0, clip->endSec - clip->windowStartSec);

    int firstIdx = -1;
    int lastIdx = -1;
    double sum = 0.0;
    for (int i = 0; i < clip->durations.size(); ++i) {
        sum += clip->durations.at(i);
        if (firstIdx < 0 && sum > offStart)
            firstIdx = i + 1;
        if (sum > offEnd) {
            lastIdx = i + 1;
            break;
        }
    }
    if (firstIdx < 0)
        firstIdx = clip->durations.size();
    if (lastIdx < firstIdx)
        lastIdx = firstIdx;
    if (lastIdx > clip->durations.size())
        lastIdx = clip->durations.size();

    double before = 0.0;
    for (int i = 0; i < firstIdx - 1; ++i)
        before += clip->durations.at(i);
    const qint64 segStartSec = clip->windowStartSec + qint64(before);

    clip->firstPart = firstIdx;
    clip->maxParts = lastIdx;
    clip->nextPart = 0;  // init segment first
    clip->fileOffsetSec = qMax<qint64>(0, clip->targetSec - segStartSec);

    double covered = 0.0;
    int needed = firstIdx;
    for (int i = firstIdx - 1; i < clip->durations.size(); ++i) {
        covered += clip->durations.at(i);
        if (covered >= clip->fileOffsetSec)
            break;
        ++needed;
    }
    clip->requiredParts = needed;

    requestNextSegmentPart(clip);
}

void FrigatePlayback::startSegmentClip(const QString& cameraId, int gen, qint64 startSec, qint64 endSec,
                                       qint64 targetSec, bool startWorker, bool prefetch,
                                       const QString& vodUrl, const QString& clipUrl)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty())
        return;

    const QString key = clipKey(cameraId, startSec, endSec);
    const QString roleKey = prefetch ? m_prefetchClipKey.value(cameraId)
                                     : m_activeClipKey.value(cameraId);
    if (!roleKey.isEmpty() && roleKey != key)
        cancelSegmentClip(roleKey);

    if (m_segmentClips.contains(key))
        cancelSegmentClip(key);

    QDir tmpDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation));
    const QString path = tmpDir.filePath(
        QStringLiteral("px_segments_%1_%2_%3.mp4").arg(cameraId).arg(startSec).arg(endSec));

    SegmentClipState* clip = new SegmentClipState();
    clip->key = key;
    clip->path = path;
    clip->cameraId = cameraId;
    clip->vodUrl = vodUrl;
    clip->clipUrl = clipUrl;
    clip->startSec = startSec;
    clip->endSec = endSec;
    clip->targetSec = targetSec > 0 ? targetSec : startSec;
    clip->gen = gen;
    clip->startWallMs = QDateTime::currentMSecsSinceEpoch();
    m_clipStartWallMs.insert(cameraId, clip->startWallMs);
    clip->startWorker = startWorker;

    clip->file = new QFile(path);
    if (!clip->file->open(QIODevice::WriteOnly)) {
        delete clip->file;
        clip->file = nullptr;
        delete clip;
        emit playbackError(cameraId, QStringLiteral("Could not write temporary playback file."));
        emit playbackStopped(cameraId);
        return;
    }

    m_segmentClips.insert(key, clip);
    if (prefetch)
        m_prefetchClipKey.insert(cameraId, key);
    else
        m_activeClipKey.insert(cameraId, key);

    prepareHourWindow(clip);
}

void FrigatePlayback::requestNextSegmentPart(SegmentClipState* clip)
{
    if (!clip)
        return;
    if (m_segmentClips.value(clip->key) != clip)
        return;
    if (m_seekGen.value(clip->cameraId, 0) != clip->gen) {
        cancelSegmentClip(clip->key);
        return;
    }
    if (clip->nextPart > clip->maxParts) {
        clip->complete = true;
        if (clip->file) {
            clip->file->flush();
            clip->file->close();
        }
        return;
    }

    const bool isInit = (clip->nextPart == 0);
    const QString partName = isInit
        ? QStringLiteral("init-v1-x3.mp4")
        : QStringLiteral("seg-%1-v1-x3.m4s").arg(clip->nextPart);
    const QString url = QStringLiteral("%1/vod/%2/start/%3/end/%4/%5")
                            .arg(m_server, clip->cameraId)
                            .arg(clip->windowStartSec)
                            .arg(clip->windowEndSec)
                            .arg(partName);

    QNetworkRequest req;
    req.setUrl(QUrl(url));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PX_Open/1.0"));
    req.setTransferTimeout(180000);

    QNetworkReply* reply = m_net->get(req);
    clip->reply = reply;

    connect(reply, &QNetworkReply::readyRead, this,
            [this, clip, reply]() {
        if (m_segmentClips.value(clip->key) != clip)
            return;
        if (QFile* file = clip->file)
            file->write(reply->readAll());
    });

    connect(reply, &QNetworkReply::finished, this,
            [this, clip]() {
        QNetworkReply* reply = clip->reply;
        if (!reply)
            return;
        clip->reply = nullptr;

        if (clip->file && reply->bytesAvailable() > 0)
            clip->file->write(reply->readAll());
        if (clip->file)
            clip->file->flush();

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        reply->deleteLater();

        if (m_segmentClips.value(clip->key) != clip)
            return;
        if (m_seekGen.value(clip->cameraId, 0) != clip->gen) {
            cancelSegmentClip(clip->key);
            return;
        }

        // init or first media segment missing: range cannot be played this
        // way, so fall back to the HLS playlist.
        if (err != QNetworkReply::NoError || status >= 400) {
            if (clip->nextPart == 0 || clip->nextPart == clip->firstPart) {
                const QString vod = clip->vodUrl;
                const QString mp4 = clip->clipUrl;
                const int gen = clip->gen;
                const QString cameraId = clip->cameraId;
                cancelSegmentClip(clip->key);
                startUrlWorker(cameraId, gen, vod, mp4);
                return;
            }
            clip->complete = true;
            if (clip->file) {
                clip->file->flush();
                clip->file->close();
            }
            return;
        }

        if (clip->nextPart == clip->firstPart && !clip->ready)
            clip->ready = true;

        if (clip->nextPart == 0)
            clip->nextPart = clip->firstPart;
        else
            ++clip->nextPart;

        // If the user clicked again while this range was being prepared,
        // start at the newer position inside the same (already warming)
        // range instead of issuing a second server request.
        if (clip->ready && clip->startWorker && !clip->workerStarted) {
            qint64 offset = clip->fileOffsetSec;
            int partsNeeded = clip->requiredParts;
            if (clip->queuedTargetSec > 0) {
                const qint64 delta = clip->queuedTargetSec - clip->targetSec;
                offset += delta;
                if (delta > 0)
                    partsNeeded += int(std::ceil(qreal(delta) / 10.0));
            }
            const qint64 clipLen = clip->endSec - clip->startSec;
            if (offset < 0)
                offset = 0;
            if (offset > clipLen - 1)
                offset = clipLen - 1;

            if (clip->nextPart > partsNeeded) {
                clip->workerStarted = true;
                m_clipStartWallMs.insert(clip->cameraId, QDateTime::currentMSecsSinceEpoch());
                startLocalWorker(clip->cameraId, clip->gen, clip->path, offset);
            }
        }

        if (clip->nextPart > clip->maxParts) {
            clip->complete = true;
            if (clip->file) {
                clip->file->flush();
                clip->file->close();
            }
            return;
        }
        requestNextSegmentPart(clip);
    });
}

void FrigatePlayback::prefetchNextClip(const QString& cameraId, int gen, qint64 startSec, qint64 endSec)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty())
        return;
    if (m_seekGen.value(cameraId, 0) != gen || !m_playbackActiveByCamera.value(cameraId, false))
        return;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (endSec > nowSec - 2)
        endSec = nowSec - 2;
    if (endSec <= startSec)
        return;

    const QString clipUrl = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                                .arg(m_server, cameraId)
                                .arg(startSec)
                                .arg(endSec);
    const QString vodUrl = QStringLiteral("%1/vod/%2/start/%3/end/%4/index.m3u8")
                               .arg(m_server, cameraId)
                               .arg(startSec)
                               .arg(endSec);

    const QString key = clipKey(cameraId, startSec, endSec);
    if (m_prefetchClipKey.value(cameraId) == key && m_segmentClips.contains(key))
        return;

    startSegmentClip(cameraId, gen, startSec, endSec, startSec, false, true, vodUrl, clipUrl);
}

void FrigatePlayback::stopWorkerAsync(const QString& cameraId)
{
    cancelDownload(cameraId);

    FFmpegWorker* worker = nullptr;
    QThread* thread = nullptr;
    {
        QMutexLocker lock(&m_mutex);
        worker = m_playbackWorkers.take(cameraId);
        thread = m_playbackThreads.take(cameraId);
    }
    if (!worker && !thread)
        return;

    if (worker) {
        // stopDecoding() only uses atomics, so it is safe to call while the
        // worker is still draining a frame on its own thread.
        worker->setFrameQueue(nullptr);
        worker->stopDecoding();
        QObject::disconnect(worker, nullptr, this, nullptr);
    }
    if (worker && thread) {
        QObject::connect(worker, &FFmpegWorker::finished, thread, &QThread::quit, Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished, worker, &QObject::deleteLater, Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished, thread, &QObject::deleteLater, Qt::UniqueConnection);
        return;
    }
    if (worker) {
        QObject::connect(worker, &FFmpegWorker::finished, worker, &QObject::deleteLater, Qt::UniqueConnection);
        return;
    }
    if (thread) {
        QObject::connect(thread, &QThread::finished, thread, &QObject::deleteLater, Qt::UniqueConnection);
        if (thread->isRunning())
            QMetaObject::invokeMethod(thread, "quit", Qt::QueuedConnection);
        else
            thread->deleteLater();
    }
}

void FrigatePlayback::stopPlayback(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty())
        return;
    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    stopWorkerAsync(cameraId);
    cleanupTempFile(cameraId);
    cancelCameraSegmentClips(cameraId);
    endPlaybackSession(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}

void FrigatePlayback::seek(const QString& cameraId, qint64 timestampMs)
{
    startPlayback(cameraId, timestampMs);
}

void FrigatePlayback::startUrlWorker(const QString& cameraId, int gen, const QString& url,
                                     const QString& fallbackUrl, qint64 startOffsetSec)
{
    if (m_seekGen.value(cameraId, 0) != gen)
        return;

    FrameQueue* queue = nullptr;
    {
        QMutexLocker lock(&m_mutex);
        if (!m_playbackQueues.contains(cameraId)) {
            FrameQueue* q = new FrameQueue(this);
            q->setMaxSize(4);
            m_playbackQueues.insert(cameraId, q);
        }
        queue = m_playbackQueues.value(cameraId);
        if (queue)
            queue->resetReceived();
        if (m_playbackWorkers.contains(cameraId))
            return;
    }
    if (!queue)
        return;

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    // Match fullscreen live: full resolution decode (up to 4K), not 720p cap
    worker->setHighQuality(true);
    // CameraVideoItem consumes AVFrame directly; skip a duplicate QImage
    // conversion for every recorded-clip frame.
    worker->setEmitRgb(false);
    if (startOffsetSec > 0)
        worker->setStartOffsetSec(startOffsetSec);

    QThread* thread = new QThread();

    connect(worker, &FFmpegWorker::openInputOk, this,
            [this, cameraId, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        emit cameraOnline(cameraId);
        emit playbackStarted(cameraId);

        // Warm the next range only after this clip is open. Playback reads a
        // local file, so this request cannot delay the clip being displayed.
        QTimer::singleShot(kPrefetchDelayMs, this, [this, cameraId, gen]() {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;
            if (!m_playbackActiveByCamera.value(cameraId, false))
                return;
            const qint64 nextStart = m_playbackEndSecByCamera.value(cameraId, 0);
            if (nextStart > 0)
                prefetchNextClip(cameraId, gen, nextStart, nextStart + kClipContinueAfterSec);
        });
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this,
            [this, cameraId, gen, url, fallbackUrl](const QString& reason) {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;

        {
            QMutexLocker lock(&m_mutex);
            m_playbackWorkers.remove(cameraId);
            m_playbackThreads.remove(cameraId);
        }

        const bool isHls = url.contains(QStringLiteral("/vod/"))
                        && url.endsWith(QStringLiteral(".m3u8"), Qt::CaseInsensitive);
        if (isHls && !fallbackUrl.isEmpty()) {
            startUrlWorker(cameraId, gen, fallbackUrl);
            return;
        }

        const QString r = reason.toLower();
        const bool isHttp = url.startsWith(QStringLiteral("http"), Qt::CaseInsensitive);
        const bool noClip = r.contains(QStringLiteral("400"))
                         || r.contains(QStringLiteral("bad request"))
                         || r.contains(QStringLiteral("404"))
                         || r.contains(QStringLiteral("not found"));

        if (isHttp && noClip) {
            endPlaybackSession(cameraId);
            emit playbackError(cameraId,
                QStringLiteral("No recording at this time. Try another place on the timeline."));
            emit playbackStopped(cameraId);
            return;
        }

        if (isHttp) {
            downloadThenPlay(cameraId, gen, url);
            return;
        }

        cleanupTempFile(cameraId);
        endPlaybackSession(cameraId);
        emit playbackError(cameraId,
            reason.isEmpty() ? QStringLiteral("Playback failed.") : reason);
        emit playbackStopped(cameraId);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::streamStopped, this,
            [this, cameraId, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        {
            QMutexLocker lock(&m_mutex);
            m_playbackWorkers.remove(cameraId);
            m_playbackThreads.remove(cameraId);
        }
        cleanupTempFile(cameraId);
        if (m_playbackActiveByCamera.value(cameraId, false)) {
            continuePlayback(cameraId, gen);
            return;
        }
        endPlaybackSession(cameraId);
        emit playbackStopped(cameraId);
    }, Qt::QueuedConnection);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    connect(thread, &QThread::finished, this,
            [this, cameraId, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        QMutexLocker lock(&m_mutex);
        m_playbackWorkers.remove(cameraId);
        m_playbackThreads.remove(cameraId);
    }, Qt::QueuedConnection);

    {
        QMutexLocker lock(&m_mutex);
        if (m_seekGen.value(cameraId, 0) != gen) {
            worker->deleteLater();
            thread->deleteLater();
            return;
        }
        m_playbackWorkers.insert(cameraId, worker);
        m_playbackThreads.insert(cameraId, thread);
    }
    worker->moveToThread(thread);
    thread->start();
}

void FrigatePlayback::startLocalWorker(const QString& cameraId, int gen, const QString& localPath,
                                       qint64 startOffsetSec)
{
    startUrlWorker(cameraId, gen, localPath, QString(), startOffsetSec);
}

void FrigatePlayback::downloadThenPlay(const QString& cameraId, int gen, const QString& remoteUrl)
{
    if (m_seekGen.value(cameraId, 0) != gen)
        return;

    QDir tmpDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation));
    const QString localPath = tmpDir.filePath(
        QStringLiteral("px_playback_%1_%2.mp4").arg(cameraId).arg(gen));

    cleanupTempFile(cameraId);
    m_downloadStartedPlay.remove(cameraId);

    QFile* outFile = new QFile(localPath);
    if (!outFile->open(QIODevice::WriteOnly)) {
        delete outFile;
        emit playbackError(cameraId, QStringLiteral("Could not write temporary playback file."));
        emit playbackStopped(cameraId);
        return;
    }
    m_downloadFiles.insert(cameraId, outFile);
    m_tempFiles.insert(cameraId, localPath);

    QNetworkRequest req;
    req.setUrl(QUrl(remoteUrl));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PX_Open/1.0"));
    req.setTransferTimeout(180000);

    QNetworkReply* reply = m_net->get(req);
    m_downloadReplies.insert(cameraId, reply);

    // Start local FFmpeg once we have enough bytes (play while download continues).
    // static so MSVC does not require capturing into the lambda
    static constexpr qint64 kMinBytesToStart = 512 * 1024;

    auto tryStartEarly = [this, cameraId, gen, localPath]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        if (m_downloadStartedPlay.value(cameraId, false))
            return;

        QFile* f = m_downloadFiles.value(cameraId);
        if (!f || f->size() < kMinBytesToStart)
            return;

        f->flush();

        {
            QMutexLocker lock(&m_mutex);
            if (m_playbackWorkers.contains(cameraId)) {
                m_downloadStartedPlay.insert(cameraId, true);
                return;
            }
        }

        m_downloadStartedPlay.insert(cameraId, true);
        startLocalWorker(cameraId, gen, localPath);
    };

    connect(reply, &QNetworkReply::readyRead, this,
            [this, cameraId, gen, reply, tryStartEarly]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        if (QFile* f = m_downloadFiles.value(cameraId)) {
            const QByteArray chunk = reply->readAll();
            if (!chunk.isEmpty())
                f->write(chunk);
        }
        tryStartEarly();
    });

    connect(reply, &QNetworkReply::finished, this,
            [this, cameraId, gen, localPath, reply]() {
        m_downloadReplies.remove(cameraId);

        QFile* file = m_downloadFiles.take(cameraId);
        if (file) {
            if (reply->bytesAvailable() > 0)
                file->write(reply->readAll());
            file->flush();
            file->close();
            delete file;
        }

        if (m_seekGen.value(cameraId, 0) != gen) {
            reply->deleteLater();
            m_downloadStartedPlay.remove(cameraId);
            return;
        }

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        reply->deleteLater();

        const qint64 size = QFileInfo(localPath).size();
        if (err != QNetworkReply::NoError || status >= 400 || size < 1024) {
            cleanupTempFile(cameraId);
            m_downloadStartedPlay.remove(cameraId);
            endPlaybackSession(cameraId);

            QString msg;
            if (status == 400 || status == 404)
                msg = QStringLiteral("No recording at this time. Try another place on the timeline.");
            else if (status >= 400)
                msg = QStringLiteral("Server error (%1) loading recording.").arg(status);
            else if (size < 1024)
                msg = QStringLiteral("Recording clip was empty.");
            else
                msg = QStringLiteral("Could not download recording.");

            emit playbackError(cameraId, msg);
            emit playbackStopped(cameraId);
            return;
        }

        // Download complete: start only if we never started mid-download
        if (!m_downloadStartedPlay.value(cameraId, false)) {
            m_downloadStartedPlay.insert(cameraId, true);
            startLocalWorker(cameraId, gen, localPath);
        }
        m_downloadStartedPlay.remove(cameraId);
    });
}

void FrigatePlayback::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty()) {
        emit playbackError(cameraId, QStringLiteral("Missing camera or server for playback."));
        return;
    }

    const qint64 wall = QDateTime::currentMSecsSinceEpoch();
    if (m_lastSeekMs.contains(cameraId) && (wall - m_lastSeekMs.value(cameraId) < 50))
        return;
    m_lastSeekMs[cameraId] = wall;

    qint64 seekSec = timestampMs;
    if (timestampMs > 10000000000LL)
        seekSec = timestampMs / 1000;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();

    qint64 startSec = seekSec - kClipBeforeSec;
    if (startSec < 1)
        startSec = 1;

    qint64 endSec = seekSec + kClipInitialAfterSec;
    if (endSec <= startSec)
        endSec = startSec + kClipMinLenSec;

    if (endSec > nowSec - 2)
        endSec = nowSec - 2;
    if (startSec >= endSec) {
        endSec = nowSec - 2;
        startSec = endSec - kClipMinLenSec;
        if (startSec < 1)
            startSec = 1;
    }

    // A second click while a nearby range is still being prepared should not
    // start another server-side generation: Frigate cannot cancel the first
    // one, so two overlapping requests take roughly twice as long. Reuse the
    // warming range and jump to the new position inside it once it is ready.
    SegmentClipState* inflight = m_segmentClips.value(m_activeClipKey.value(cameraId));
    if (inflight && !inflight->ready && !inflight->workerStarted
            && seekSec >= inflight->startSec && seekSec <= inflight->endSec) {
        inflight->queuedTargetSec = seekSec;
        cancelPrefetch(cameraId);
        m_playbackPositionByCamera[cameraId] = seekSec * 1000;
        emit playbackPositionChanged(cameraId, seekSec * 1000);
        return;
    }

    const int gen = m_seekGen.value(cameraId, 0) + 1;
    m_seekGen[cameraId] = gen;
    cancelPrefetch(cameraId);

    m_pendingTargetSec[cameraId] = seekSec;
    m_playbackActiveByCamera[cameraId] = true;
    m_playbackPositionByCamera[cameraId] = seekSec * 1000;
    emit playbackPositionChanged(cameraId, seekSec * 1000);

    beginClip(cameraId, gen, startSec, endSec, true);
}

void FrigatePlayback::beginClip(const QString& cameraId, int gen, qint64 startSec, qint64 endSec, bool resetQueue)
{
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (endSec > nowSec - 2)
        endSec = nowSec - 2;
    if (startSec < 1)
        startSec = 1;
    if (endSec <= startSec) {
        if (!resetQueue) {
            endPlaybackSession(cameraId);
            emit playbackStopped(cameraId);
        }
        return;
    }

    m_playbackEndSecByCamera[cameraId] = endSec;

    stopWorkerAsync(cameraId);
    cleanupTempFile(cameraId);

    {
        QMutexLocker lock(&m_mutex);
        if (!m_playbackQueues.contains(cameraId)) {
            FrameQueue* q = new FrameQueue(this);
            q->setMaxSize(4);
            m_playbackQueues.insert(cameraId, q);
        }
        if (FrameQueue* queue = m_playbackQueues.value(cameraId)) {
            if (resetQueue)
                queue->clear();
            queue->resetReceived();
        }
    }

    const QString clipUrl = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                                .arg(m_server, cameraId)
                                .arg(startSec)
                                .arg(endSec);
    const QString vodUrl = QStringLiteral("%1/vod/%2/start/%3/end/%4/index.m3u8")
                               .arg(m_server, cameraId)
                               .arg(startSec)
                               .arg(endSec);

    const qint64 targetSec = m_pendingTargetSec.take(cameraId);
    const QString key = clipKey(cameraId, startSec, endSec);
    const QString oldActive = m_activeClipKey.value(cameraId);
    if (!oldActive.isEmpty() && oldActive != key)
        cancelSegmentClip(oldActive);

    SegmentClipState* prefetched = m_segmentClips.value(key);
    if (prefetched && prefetched->ready) {
        if (m_prefetchClipKey.value(cameraId) == key)
            m_prefetchClipKey.remove(cameraId);
        m_activeClipKey.insert(cameraId, key);
        prefetched->gen = gen;
        qint64 offset = prefetched->fileOffsetSec;
        if (targetSec > 0 && prefetched->targetSec > 0)
            offset += targetSec - prefetched->targetSec;
        prefetched->targetSec = targetSec > 0 ? targetSec : prefetched->targetSec;
        if (offset < 0)
            offset = 0;
        if (offset > endSec - startSec - 1)
            offset = endSec - startSec - 1;
        m_clipStartWallMs[cameraId] = QDateTime::currentMSecsSinceEpoch();
        startLocalWorker(cameraId, gen, prefetched->path, offset);
        return;
    }

    startSegmentClip(cameraId, gen, startSec, endSec, targetSec, true, false, vodUrl, clipUrl);
}

void FrigatePlayback::continuePlayback(const QString& cameraId, int gen)
{
    if (m_seekGen.value(cameraId, 0) != gen)
        return;
    if (!m_playbackActiveByCamera.value(cameraId, false)) {
        emit playbackStopped(cameraId);
        return;
    }

    const qint64 nextStart = m_playbackEndSecByCamera.value(cameraId, 0);
    if (nextStart <= 0) {
        endPlaybackSession(cameraId);
        emit playbackStopped(cameraId);
        return;
    }

    qint64 nextEnd = nextStart + kClipContinueAfterSec;
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (nextEnd > nowSec - 2)
        nextEnd = nowSec - 2;
    if (nextEnd <= nextStart) {
        endPlaybackSession(cameraId);
        emit playbackStopped(cameraId);
        return;
    }

    beginClip(cameraId, gen, nextStart, nextEnd, false);
}

void FrigatePlayback::endPlaybackSession(const QString& cameraId)
{
    cancelCameraSegmentClips(cameraId);
    m_playbackActiveByCamera.remove(cameraId);
    m_playbackEndSecByCamera.remove(cameraId);
}

qint64 FrigatePlayback::currentPosition(const QString& cameraId) const
{
    return m_playbackPositionByCamera.value(cameraId, 0);
}

void FrigatePlayback::switchToLive(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty())
        return;
    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    stopWorkerAsync(cameraId);
    cleanupTempFile(cameraId);
    cancelCameraSegmentClips(cameraId);
    endPlaybackSession(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}