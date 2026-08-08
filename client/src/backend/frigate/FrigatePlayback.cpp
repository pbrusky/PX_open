#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
{
}

FrigatePlayback::~FrigatePlayback()
{
    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys)
        stopWorkerSync(id);
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
    queue->setMaxSize(2);
    m_playbackQueues.insert(cameraId, queue);
    return queue;
}

void FrigatePlayback::stopWorkerSync(const QString& cameraId)
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

    if (worker) {
        QObject::disconnect(worker, nullptr, this, nullptr);
        worker->stopDecoding();
    }

    if (thread) {
        // Ask thread to finish; do NOT terminate unless it hangs
        if (thread->isRunning()) {
            thread->quit();
            if (!thread->wait(4000)) {
                qWarning() << "[Playback] thread wait timeout, terminating" << cameraId;
                thread->terminate();
                thread->wait(500);
            }
        }
        // Thread object: only delete after it is stopped
        thread->deleteLater();
    }

    // Worker is parented to nullptr and moved to thread.
    // After thread stopped, safe to delete if still alive.
    if (worker) {
        // finished may already have scheduled deleteLater
        worker->deleteLater();
    }
}

void FrigatePlayback::stopPlayback(const QString& cameraId)
{
    stopWorkerSync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}

void FrigatePlayback::seek(const QString& cameraId, qint64 timestampMs)
{
    startPlayback(cameraId, timestampMs);
}

void FrigatePlayback::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    if (cameraId.trimmed().isEmpty()) {
        qWarning() << "[Playback] empty cameraId";
        return;
    }
    if (m_server.isEmpty()) {
        qWarning() << "[Playback] Frigate server not set";
        return;
    }

    // Debounce identical seeks within 500ms (double click/release)
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (m_lastSeekMs.contains(cameraId)) {
        const qint64 prev = m_lastSeekMs.value(cameraId);
        if (qAbs(prev - timestampMs) < 500 && nowMs - (m_playbackPositionByCamera.value(cameraId, 0)) < 1) {
            // fall through still ok
        }
    }
    // Time-based debounce: ignore second call within 400ms for same camera
    static QHash<QString, qint64> s_lastStartWall;
    if (s_lastStartWall.contains(cameraId)
            && (nowMs - s_lastStartWall.value(cameraId)) < 400) {
        qDebug() << "[Playback] debounced seek" << cameraId;
        return;
    }
    s_lastStartWall[cameraId] = nowMs;
    m_lastSeekMs[cameraId] = timestampMs;

    qint64 startSec = timestampMs;
    if (timestampMs > 100000000000LL) // ms epoch
        startSec = timestampMs / 1000;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    qint64 endSec = startSec + 120; // 2 minute clip (faster to open)
    if (endSec > nowSec)
        endSec = nowSec;
    if (endSec <= startSec)
        endSec = startSec + 15;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    qDebug() << "[Playback] start" << cameraId
             << "from" << startSec << "to" << endSec << url;

    // Fully stop previous worker/thread BEFORE starting a new one
    stopWorkerSync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue)
        return;
    queue->resetReceived();

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true);

    QThread* thread = new QThread(); // no parent — we manage lifetime

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraId]() {
        qDebug() << "[Playback] open OK" << cameraId;
        emit cameraOnline(cameraId);
        emit playbackStarted(cameraId);
    });

    connect(worker, &FFmpegWorker::openInputFailed, this,
            [this, cameraId](const QString& reason) {
        qWarning() << "[Playback] open failed" << cameraId << reason;
        emit cameraOffline(cameraId);
    });

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);

    // When thread ends, clear maps if this is still the active thread
    connect(thread, &QThread::finished, this, [this, cameraId, thread, worker]() {
        QMutexLocker lock(&m_mutex);
        if (m_playbackThreads.value(cameraId) == thread)
            m_playbackThreads.remove(cameraId);
        if (m_playbackWorkers.value(cameraId) == worker)
            m_playbackWorkers.remove(cameraId);
        thread->deleteLater();
        worker->deleteLater();
    });

    {
        QMutexLocker lock(&m_mutex);
        m_playbackWorkers.insert(cameraId, worker);
        m_playbackThreads.insert(cameraId, thread);
    }

    worker->moveToThread(thread);
    thread->start();

    const qint64 posMs = startSec * 1000;
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
    stopWorkerSync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[Playback] live mode" << cameraId;
}