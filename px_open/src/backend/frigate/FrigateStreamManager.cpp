#include "FrigateStreamManager.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QDebug>
#include <QThread>

FrigateStreamManager::FrigateStreamManager(QObject* parent)
    : QObject(parent)
{
}

FrigateStreamManager::~FrigateStreamManager()
{
    stopAllStreams();
}

void FrigateStreamManager::setServer(const QString& server)
{
    m_server = server;
}

void FrigateStreamManager::setServerIp(const QString& ip)
{
    m_serverIp = ip;
}

static QString buildRtspUrl(const QString& serverIp, const QString& cameraName)
{
    return QString("rtsp://%1:8554/%2").arg(serverIp, cameraName);
}

QObject* FrigateStreamManager::getQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty()) {
        qWarning() << "[StreamManager] getQueue(): invalid cameraName";
        return nullptr;
    }

    // Reuse existing queue
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
    worker->setFrameQueue(queue);   // ⭐ NEW: connect worker → queue
    m_workers.insert(cameraName, worker);

    // Online/offline detection
    connect(worker, &FFmpegWorker::openInputOk,
            this, [this, cameraName]() {
        emit cameraOnline(cameraName);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed,
            this, [this, cameraName](const QString& reason) {
        qDebug() << "[StreamManager] Camera offline:" << cameraName << "reason:" << reason;
        emit cameraOffline(cameraName);
    }, Qt::QueuedConnection);

    // ⭐ REMOVED: old frameReady(img) connection
    // (worker no longer emits frameReady(img))

    // Thread
    QThread* thread = new QThread(this);
    m_threads.insert(cameraName, thread);

    connect(thread, &QThread::started,
            worker, &FFmpegWorker::startDecoding);

    connect(worker, &FFmpegWorker::finished,
            thread, &QThread::quit, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::finished,
            worker, &QObject::deleteLater, Qt::QueuedConnection);

    connect(thread, &QThread::finished,
            thread, &QObject::deleteLater, Qt::QueuedConnection);

    worker->moveToThread(thread);
    thread->start();

    return queue;
}

QObject* FrigateStreamManager::getPlaybackQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty()) {
        qWarning() << "[StreamManager] getPlaybackQueue(): invalid cameraName";
        return nullptr;
    }

    // Reuse existing queue
    if (m_playbackQueues.contains(cameraName))
        return m_playbackQueues[cameraName];

    // Create queue
    FrameQueue* queue = new FrameQueue(this);
    m_playbackQueues.insert(cameraName, queue);

    // Build playback URL
    const QString url = QString("%1/api/playback/%2")
                            .arg(m_server, cameraName);

    // Worker
    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);   // ⭐ NEW: connect worker → queue
    m_playbackWorkers.insert(cameraName, worker);

    // ⭐ REMOVED: old frameReady(img) connection

    // Thread
    QThread* thread = new QThread(this);
    m_playbackThreads.insert(cameraName, thread);

    connect(thread, &QThread::started,
            worker, &FFmpegWorker::startDecoding);

    connect(worker, &FFmpegWorker::finished,
            thread, &QThread::quit, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::finished,
            worker, &QObject::deleteLater, Qt::QueuedConnection);

    connect(thread, &QThread::finished,
            thread, &QObject::deleteLater, Qt::QueuedConnection);

    worker->moveToThread(thread);
    thread->start();

    return queue;
}

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

    m_queues.remove(cameraName);
    m_playbackQueues.remove(cameraName);
}

void FrigateStreamManager::stopAllStreams()
{
    qDebug() << "[StreamManager] stopAllStreams(): stopping all";

    for (auto w : m_workers)
        if (w) w->stopDecoding();

    for (auto t : m_threads)
        if (t) { t->quit(); t->wait(); }

    for (auto w : m_playbackWorkers)
        if (w) w->stopDecoding();

    for (auto t : m_playbackThreads)
        if (t) { t->quit(); t->wait(); }

    m_workers.clear();
    m_threads.clear();
    m_playbackWorkers.clear();
    m_playbackThreads.clear();
    m_queues.clear();
    m_playbackQueues.clear();
}

void FrigateStreamManager::restartStream(const QString& cameraName)
{
    stopStream(cameraName);
    getQueue(cameraName);
}
