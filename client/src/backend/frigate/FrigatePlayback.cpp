#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>
#include <QMetaObject>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>

namespace {
constexpr qint64 kClipBeforeSec = 3;
constexpr qint64 kClipInitialAfterSec = 15;
constexpr qint64 kClipContinueAfterSec = 60;
constexpr qint64 kClipMinLenSec = 20;
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

    const QStringList prefetchKeys = m_prefetchReplies.keys();
    for (const QString& id : prefetchKeys)
        cancelPrefetch(id);
    for (const QString& id : m_prefetchPaths.keys())
        cancelPrefetch(id);

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

void FrigatePlayback::cancelPrefetch(const QString& cameraId)
{
    QNetworkReply* reply = m_prefetchReplies.take(cameraId);
    if (reply) {
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    QFile* file = m_prefetchFiles.take(cameraId);
    if (file) {
        file->close();
        delete file;
    }
    const QString path = m_prefetchPaths.take(cameraId);
    if (!path.isEmpty())
        QFile::remove(path);
}

void FrigatePlayback::prefetchNextClip(const QString& cameraId, int gen, qint64 startSec, qint64 endSec)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty())
        return;
    if (m_seekGen.value(cameraId, 0) != gen || !m_playbackActiveByCamera.value(cameraId, false))
        return;
    if (m_prefetchReplies.contains(cameraId) || m_prefetchPaths.contains(cameraId))
        return;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (endSec > nowSec - 2)
        endSec = nowSec - 2;
    if (endSec <= startSec)
        return;

    cancelPrefetch(cameraId);

    QDir tmpDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation));
    const QString path = tmpDir.filePath(
        QStringLiteral("px_prefetch_%1_%2_%3.mp4").arg(cameraId).arg(startSec).arg(endSec));

    QFile* outFile = new QFile(path);
    if (!outFile->open(QIODevice::WriteOnly)) {
        delete outFile;
        return;
    }
    m_prefetchFiles.insert(cameraId, outFile);

    QNetworkRequest req;
    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);
    req.setUrl(QUrl(url));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PX_Open/1.0"));
    req.setTransferTimeout(180000);

    QNetworkReply* reply = m_net->get(req);
    m_prefetchReplies.insert(cameraId, reply);

    connect(reply, &QNetworkReply::readyRead, this,
            [this, cameraId, reply]() {
        if (QFile* f = m_prefetchFiles.value(cameraId)) {
            const QByteArray chunk = reply->readAll();
            if (!chunk.isEmpty())
                f->write(chunk);
        }
    });

    connect(reply, &QNetworkReply::finished, this,
            [this, cameraId, gen, path, reply]() {
        m_prefetchReplies.remove(cameraId);

        QFile* file = m_prefetchFiles.take(cameraId);
        if (file) {
            if (reply->bytesAvailable() > 0)
                file->write(reply->readAll());
            file->flush();
            file->close();
            delete file;
        }

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        reply->deleteLater();

        if (m_seekGen.value(cameraId, 0) != gen
                || !m_playbackActiveByCamera.value(cameraId, false)
                || err != QNetworkReply::NoError || status >= 400
                || QFileInfo(path).size() < 1024) {
            QFile::remove(path);
            return;
        }

        m_prefetchPaths.insert(cameraId, path);
    });
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

void FrigatePlayback::startUrlWorker(const QString& cameraId, int gen, const QString& url)
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

    QThread* thread = new QThread();

    connect(worker, &FFmpegWorker::openInputOk, this,
            [this, cameraId, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        emit cameraOnline(cameraId);
        emit playbackStarted(cameraId);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this,
            [this, cameraId, gen, url](const QString& reason) {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;

        {
            QMutexLocker lock(&m_mutex);
            m_playbackWorkers.remove(cameraId);
            m_playbackThreads.remove(cameraId);
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

void FrigatePlayback::startLocalWorker(const QString& cameraId, int gen, const QString& localPath)
{
    startUrlWorker(cameraId, gen, localPath);
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

    const int gen = m_seekGen.value(cameraId, 0) + 1;
    m_seekGen[cameraId] = gen;
    cancelPrefetch(cameraId);

    qint64 seekSec = timestampMs;
    if (timestampMs > 100000000000LL)
        seekSec = timestampMs / 1000;
    else if (timestampMs > 10000000000LL)
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

    const QString prefetched = m_prefetchPaths.take(cameraId);
    if (!prefetched.isEmpty()) {
        m_tempFiles.insert(cameraId, prefetched);
        startLocalWorker(cameraId, gen, prefetched);
    } else {
        const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                                .arg(m_server, cameraId)
                                .arg(startSec)
                                .arg(endSec);
        startUrlWorker(cameraId, gen, url);
    }

    prefetchNextClip(cameraId, gen, endSec, endSec + kClipContinueAfterSec);
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
    cancelPrefetch(cameraId);
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
    endPlaybackSession(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}