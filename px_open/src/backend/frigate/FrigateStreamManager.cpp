#include "FrigateStreamManager.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QDebug>

FrigateStreamManager::FrigateStreamManager(QObject* parent)
    : QObject(parent)
{
}

FrigateStreamManager::~FrigateStreamManager()
{
    // Ensure all threads are stopped before destruction
    stopAllStreams();
}

//
// Server setters
//
void FrigateStreamManager::setServer(const QString& server)
{
    m_server = server;
}

void FrigateStreamManager::setServerIp(const QString& ip)
{
    m_serverIp = ip;
}

//
// Build RTSP URL
//
static QString buildRtspUrl(const QString& serverIp, const QString& cameraName)
{
    return QString("rtsp://%1:8554/%2").arg(serverIp, cameraName);
}

//
// ⭐ GET LIVE QUEUE — starts FFmpegWorker thread
//
QObject* FrigateStreamManager::getQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty()) {
        qWarning() << "[StreamManager] getQueue(): invalid cameraName";
        return nullptr;
    }

    // Already exists?
    if (m_queues.contains(cameraName))
        return m_queues[cameraName];

    // Create queue
    FrameQueue* queue = new FrameQueue(this);
    m_queues.insert(cameraName, queue);

    // Build RTSP URL
    const QString url = buildRtspUrl(m_serverIp, cameraName);

    // Create worker
    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    m_workers.insert(cameraName, worker);

    // Online/offline detection
    connect(worker, &FFmpegWorker::openInputOk,
            this, [this, cameraName]() {
        emit cameraOnline(cameraName);
    });

    connect(worker, &FFmpegWorker::openInputFailed,
            this, [this, cameraName](const QString& reason) {
        qDebug() << "[StreamManager] Camera offline:" << cameraName << "reason:" << reason;
        emit cameraOffline(cameraName);
    });

    // Frame forwarding
    connect(worker, &FFmpegWorker::frameReady,
            queue, &FrameQueue::pushFrame,
            Qt::QueuedConnection);

    // Thread
    QThread* thread = new QThread(this);
    m_threads.insert(cameraName, thread);

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

    return queue;
}

//
// ⭐ GET PLAYBACK QUEUE — separate worker/thread
//
QObject* FrigateStreamManager::getPlaybackQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty()) {
        qWarning() << "[StreamManager] getPlaybackQueue(): invalid cameraName";
        return nullptr;
    }

    // Already exists?
    if (m_playbackQueues.contains(cameraName))
        return m_playbackQueues[cameraName];

    FrameQueue* queue = new FrameQueue(this);
    m_playbackQueues.insert(cameraName, queue);

    // Playback URL (module server)
    const QString url = QString("%1/api/playback/%2")
                            .arg(m_server, cameraName);

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    m_playbackWorkers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::frameReady,
            queue, &FrameQueue::pushFrame,
            Qt::QueuedConnection);

    QThread* thread = new QThread(this);
    m_playbackThreads.insert(cameraName, thread);

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

    return queue;
}

//
// ⭐ STOP ONE STREAM
//
void FrigateStreamManager::stopStream(const QString& cameraName)
{
    qDebug() << "[StreamManager] stopStream(): stopping" << cameraName;

    if (m_workers.contains(cameraName)) {
        FFmpegWorker* worker = m_workers.value(cameraName);
        QThread* thread = m_threads.value(cameraName);

        if (worker)
            worker->stopDecoding();

        if (thread) {
            thread->quit();
            thread->wait();
        }

        m_workers.remove(cameraName);
        m_threads.remove(cameraName);
    }

    if (m_playbackWorkers.contains(cameraName)) {
        FFmpegWorker* worker = m_playbackWorkers.value(cameraName);
        QThread* thread = m_playbackThreads.value(cameraName);

        if (worker)
            worker->stopDecoding();

        if (thread) {
            thread->quit();
            thread->wait();
        }

        m_playbackWorkers.remove(cameraName);
        m_playbackThreads.remove(cameraName);
    }

    if (m_queues.contains(cameraName))
        m_queues.remove(cameraName);

    if (m_playbackQueues.contains(cameraName))
        m_playbackQueues.remove(cameraName);
}

//
// ⭐ STOP ALL STREAMS
//
void FrigateStreamManager::stopAllStreams()
{
    qDebug() << "[StreamManager] stopAllStreams(): stopping all";

    for (auto it = m_workers.begin(); it != m_workers.end(); ++it) {
        if (it.value())
            it.value()->stopDecoding();
    }

    for (auto it = m_threads.begin(); it != m_threads.end(); ++it) {
        if (it.value()) {
            it.value()->quit();
            it.value()->wait();
        }
    }

    for (auto it = m_playbackWorkers.begin(); it != m_playbackWorkers.end(); ++it) {
        if (it.value())
            it.value()->stopDecoding();
    }

    for (auto it = m_playbackThreads.begin(); it != m_playbackThreads.end(); ++it) {
        if (it.value()) {
            it.value()->quit();
            it.value()->wait();
        }
    }

    m_workers.clear();
    m_threads.clear();
    m_playbackWorkers.clear();
    m_playbackThreads.clear();
    m_queues.clear();
    m_playbackQueues.clear();
}

//
// ⭐ RESTART STREAM
//
void FrigateStreamManager::restartStream(const QString& cameraName)
{
    stopStream(cameraName);
    getQueue(cameraName);
}
