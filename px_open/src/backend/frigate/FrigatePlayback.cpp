#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDebug>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
{
}

//
// Server setters
//
void FrigatePlayback::setServer(const QString& server)
{
    m_server = server;
}

void FrigatePlayback::setModuleServer(const QString& server)
{
    m_moduleServer = server;
}

void FrigatePlayback::setServerIp(const QString& ip)
{
    m_serverIp = ip;
}

//
// Build playback URL
//
static QString buildPlaybackUrl(const QString& moduleServer,
                                const QString& cameraId,
                                qint64 timestampMs)
{
    return QString("%1/api/playback/%2?timestamp=%3")
            .arg(moduleServer, cameraId, QString::number(timestampMs));
}

//
// ⭐ GET PLAYBACK QUEUE
//
QObject* FrigatePlayback::getPlaybackQueue(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty()) {
        qWarning() << "[Playback] getPlaybackQueue(): invalid cameraId";
        return nullptr;
    }

    if (m_playbackQueues.contains(cameraId))
        return m_playbackQueues[cameraId];

    FrameQueue* queue = new FrameQueue(this);
    m_playbackQueues.insert(cameraId, queue);
    return queue;
}

//
// ⭐ SEEK
//
void FrigatePlayback::seek(const QString& cameraId, qint64 timestampMs)
{
    m_playbackPositionByCamera[cameraId] = timestampMs;
    emit playbackPositionChanged(cameraId, timestampMs);
}

//
// ⭐ START PLAYBACK
//
void FrigatePlayback::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    if (cameraId.trimmed().isEmpty()) {
        qWarning() << "[Playback] startPlayback(): cameraId empty";
        return;
    }

    if (m_moduleServer.isEmpty()) {
        qWarning() << "[Playback] startPlayback(): moduleServer not set";
        return;
    }

    // Stop old worker
    if (m_playbackWorkers.contains(cameraId)) {
        FFmpegWorker* oldWorker = m_playbackWorkers.value(cameraId);
        if (oldWorker)
            oldWorker->stopDecoding();
    }

    // Build playback URL
    QString url = buildPlaybackUrl(m_moduleServer, cameraId, timestampMs);

    // Queue
    FrameQueue* queue = nullptr;
    if (m_playbackQueues.contains(cameraId)) {
        queue = m_playbackQueues.value(cameraId);
    } else {
        queue = new FrameQueue(this);
        m_playbackQueues.insert(cameraId, queue);
    }

    // Worker
    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    m_playbackWorkers.insert(cameraId, worker);

    // Online/offline detection
    connect(worker, &FFmpegWorker::openInputOk,
            this, [this, cameraId]() {
        emit cameraOnline(cameraId);
    });

    connect(worker, &FFmpegWorker::openInputFailed,
            this, [this, cameraId](const QString& reason) {
        emit cameraOffline(cameraId);
    });

    // Frame forwarding
    connect(worker, &FFmpegWorker::frameReady,
            queue, &FrameQueue::pushFrame,
            Qt::QueuedConnection);

    // Thread
    QThread* thread = new QThread(this);
    m_playbackThreads.insert(cameraId, thread);

    connect(thread, &QThread::started,
            worker, &FFmpegWorker::startDecoding);

    connect(worker, &FFmpegWorker::finished,
            thread, &QThread::quit);

    connect(worker, &FFmpegWorker::finished,
            worker, &QObject::deleteLater);

    connect(thread, &QThread::finished,
            thread, &QObject::deleteLater);

    worker->moveToThread(thread);
    thread->start();

    // Update playback position
    m_playbackPositionByCamera[cameraId] = timestampMs;
    emit playbackPositionChanged(cameraId, timestampMs);

    qDebug() << "[Playback] Playback started for" << cameraId << "@" << timestampMs;
}

//
// ⭐ CURRENT POSITION
//
qint64 FrigatePlayback::currentPosition(const QString& cameraId) const
{
    return m_playbackPositionByCamera.value(cameraId, 0);
}

//
// ⭐ SWITCH TO LIVE MODE
//
void FrigatePlayback::switchToLive(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty()) {
        qWarning() << "[Playback] switchToLive(): cameraId empty";
        return;
    }

    // Stop playback worker
    if (m_playbackWorkers.contains(cameraId)) {
        FFmpegWorker* worker = m_playbackWorkers.value(cameraId);
        if (worker)
            worker->stopDecoding();
    }

    // Stop playback thread
    if (m_playbackThreads.contains(cameraId)) {
        QThread* thread = m_playbackThreads.value(cameraId);
        if (thread) {
            thread->quit();
            thread->wait();
        }
    }

    m_playbackWorkers.remove(cameraId);
    m_playbackThreads.remove(cameraId);

    // Reset playback position
    m_playbackPositionByCamera[cameraId] = 0;
    emit playbackPositionChanged(cameraId, 0);

    qDebug() << "[Playback] Live mode resumed for" << cameraId;
}
