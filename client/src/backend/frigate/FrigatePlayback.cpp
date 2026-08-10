#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>
#include <QNetworkRequest>
#include <QUrl>
#include <QDir>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
{
}

FrigatePlayback::~FrigatePlayback()
{
    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys) {
        cancelDownload(id);
        stopWorkerAsync(id);
    }
    const QStringList dlKeys = m_replies.keys();
    for (const QString& id : dlKeys)
        cancelDownload(id);
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
    if (m_replies.contains(cameraId)) {
        QNetworkReply* r = m_replies.take(cameraId);
        if (r) {
            QObject::disconnect(r, nullptr, this, nullptr);
            r->abort();
            r->deleteLater();
        }
    }
    if (m_tempFiles.contains(cameraId)) {
        QTemporaryFile* t = m_tempFiles.take(cameraId);
        if (t) {
            t->close();
            t->deleteLater();
        }
    }
}

void FrigatePlayback::stopWorkerAsync(const QString& cameraId)
{
    FFmpegWorker* worker = nullptr;
    QThread* thread = nullptr;

    {
        QMutexLocker lock(&m_mutex);
        worker = m_playbackWorkers.take(cameraId);
        thread = m_playbackThreads.take(cameraId);
    }

    if (!worker && !thread)
        return;

    if (worker)
        QObject::disconnect(worker, nullptr, this, nullptr);

    if (worker)
        worker->stopDecoding();

    if (thread) {
        if (worker) {
            QObject::connect(thread, &QThread::finished,
                             worker, &QObject::deleteLater,
                             Qt::UniqueConnection);
            QObject::connect(worker, &FFmpegWorker::finished,
                             thread, &QThread::quit,
                             Qt::UniqueConnection);
        }
        QObject::connect(thread, &QThread::finished,
                         thread, &QObject::deleteLater,
                         Qt::UniqueConnection);

        if (thread->isRunning()) {
            QMetaObject::invokeMethod(thread, "quit", Qt::QueuedConnection);
        } else {
            if (worker)
                worker->deleteLater();
            thread->deleteLater();
        }
    } else if (worker) {
        worker->deleteLater();
    }
}

void FrigatePlayback::stopPlayback(const QString& cameraId)
{
    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    cancelDownload(cameraId);
    stopWorkerAsync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[Playback] stopPlayback" << cameraId;
}

void FrigatePlayback::seek(const QString& cameraId, qint64 timestampMs)
{
    startPlayback(cameraId, timestampMs);
}

void FrigatePlayback::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty()) {
        qWarning() << "[Playback] missing camera or server";
        return;
    }

    const qint64 wall = QDateTime::currentMSecsSinceEpoch();
    if (m_lastSeekMs.contains(cameraId) &&
        (wall - m_lastSeekMs.value(cameraId) < 600)) {
        return;
    }
    m_lastSeekMs[cameraId] = wall;

    const int gen = m_seekGen.value(cameraId, 0) + 1;
    m_seekGen[cameraId] = gen;

    qint64 startSec = timestampMs;
    if (timestampMs > 100000000000LL)
        startSec = timestampMs / 1000;

    // Short clip — same window that loaded in ~12s in the browser
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    qint64 endSec = startSec + 6;
    if (endSec > nowSec)
        endSec = nowSec;
    if (endSec <= startSec)
        endSec = startSec + 4;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    qDebug() << "[Playback] open HTTP clip" << cameraId << startSec << "->" << endSec << url;

    cancelDownload(cameraId);
    stopWorkerAsync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue)
        return;
    QMetaObject::invokeMethod(queue, "resetReceived");

    const qint64 posMs = startSec * 1000;
    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);

    // Open with FFmpeg directly (same as browser / ffplay) — no QNetworkAccessManager
    startLocalFile(cameraId, url, posMs, gen);
}

void FrigatePlayback::startLocalFile(const QString& cameraId,
                                     const QString& path,
                                     qint64 posMs,
                                     int gen)
{
    if (m_seekGen.value(cameraId, 0) != gen)
        return;

    stopWorkerAsync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue)
        return;

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(path);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true);

    QThread* thread = new QThread();

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraId, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        qDebug() << "[Playback] open OK" << cameraId;
        emit cameraOnline(cameraId);
        emit playbackStarted(cameraId);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this,
            [this, cameraId, gen](const QString& reason) {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        qWarning() << "[Playback] open failed" << cameraId << reason;
        emit cameraOffline(cameraId);
    }, Qt::QueuedConnection);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    {
        QMutexLocker lock(&m_mutex);
        m_playbackWorkers.insert(cameraId, worker);
        m_playbackThreads.insert(cameraId, thread);
    }

    worker->moveToThread(thread);
    thread->start();

    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);
}

qint64 FrigatePlayback::currentPosition(const QString& cameraId) const
{
    return m_playbackPositionByCamera.value(cameraId, 0);
}

void FrigatePlayback::switchToLive(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty())
        return;

    // If a worker is still opening the HTTP clip, allow stop
    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    cancelDownload(cameraId);
    stopWorkerAsync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[Playback] live mode" << cameraId;
}