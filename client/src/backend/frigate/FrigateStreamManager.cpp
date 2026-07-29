#include "FrigateStreamManager.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"
#include <QVariant>
#include <QSet>

#include <QThread>
#include <QDebug>

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

static void stopWorkerThread(FFmpegWorker* worker, QThread* thread)
{
    if (worker)
        worker->stopDecoding();

    if (thread) {
        // Ask the thread's event loop to finish
        thread->quit();

        // Wait until decodeLoop returns and finished() was handled
        if (!thread->wait(5000)) {
            qWarning() << "[StreamManager] Thread did not finish in time, terminating";
            thread->terminate();
            thread->wait(1000);
        }
    }
}

QObject* FrigateStreamManager::getQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty() || m_serverIp.trimmed().isEmpty())
        return nullptr;

    if (m_queues.contains(cameraName))
        return m_queues[cameraName];

    FrameQueue* queue = new FrameQueue(this);
    queue->setMaxSize(1);
    m_queues.insert(cameraName, queue);

    const QString url = buildRtspUrl(m_serverIp, cameraName);

    // IMPORTANT: do not parent worker/thread to this — we control lifetime
    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(false);
    worker->setProperty("isProbe", false);
    m_workers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraName]() {
        emit cameraOnline(cameraName);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this, [this, cameraName](const QString&) {
        emit cameraOffline(cameraName);
    }, Qt::QueuedConnection);

    QThread* thread = new QThread(nullptr);
    m_threads.insert(cameraName, thread);

    worker->moveToThread(thread);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    // Do NOT deleteLater the thread here from finished — stopWorkerThread owns shutdown

    thread->start();
    return queue;
}

QObject* FrigateStreamManager::getFullscreenQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty() || m_serverIp.trimmed().isEmpty())
        return nullptr;

    if (m_fullscreenQueues.contains(cameraName))
        return m_fullscreenQueues[cameraName];

    FrameQueue* queue = new FrameQueue(this);
    queue->setMaxSize(1);
    m_fullscreenQueues.insert(cameraName, queue);

    const QString url = buildRtspUrl(m_serverIp, cameraName);

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true);
    worker->setProperty("isProbe", false);
    m_fullscreenWorkers.insert(cameraName, worker);

    QThread* thread = new QThread(nullptr);
    m_fullscreenThreads.insert(cameraName, thread);

    worker->moveToThread(thread);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);

    thread->start();
    return queue;
}

QObject* FrigateStreamManager::getPlaybackQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty() || m_server.trimmed().isEmpty())
        return nullptr;

    if (m_playbackQueues.contains(cameraName))
        return m_playbackQueues[cameraName];

    FrameQueue* queue = new FrameQueue(this);
    queue->setMaxSize(1);
    m_playbackQueues.insert(cameraName, queue);

    const QString url = QString("%1/api/playback/%2").arg(m_server, cameraName);

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true);
    worker->setProperty("isProbe", false);
    m_playbackWorkers.insert(cameraName, worker);

    QThread* thread = new QThread(nullptr);
    m_playbackThreads.insert(cameraName, thread);

    worker->moveToThread(thread);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);

    thread->start();
    return queue;
}

void FrigateStreamManager::stopStream(const QString& cameraName)
{
    // Live grid
    if (m_workers.contains(cameraName)) {
        FFmpegWorker* worker = m_workers.take(cameraName);
        QThread* thread = m_threads.take(cameraName);
        stopWorkerThread(worker, thread);
        delete worker;
        delete thread;
    }

    // Fullscreen
    if (m_fullscreenWorkers.contains(cameraName)) {
        FFmpegWorker* worker = m_fullscreenWorkers.take(cameraName);
        QThread* thread = m_fullscreenThreads.take(cameraName);
        stopWorkerThread(worker, thread);
        delete worker;
        delete thread;
    }

    // Playback
    if (m_playbackWorkers.contains(cameraName)) {
        FFmpegWorker* worker = m_playbackWorkers.take(cameraName);
        QThread* thread = m_playbackThreads.take(cameraName);
        stopWorkerThread(worker, thread);
        delete worker;
        delete thread;
    }

    m_queues.remove(cameraName);
    m_fullscreenQueues.remove(cameraName);
    m_playbackQueues.remove(cameraName);
}

void FrigateStreamManager::stopAllStreams()
{
    const QStringList names =
        m_workers.keys() +
        m_fullscreenWorkers.keys() +
        m_playbackWorkers.keys();

    const QStringList unique = QSet<QString>(names.begin(), names.end()).values();

    for (const QString& name : unique)
        stopStream(name);

    m_workers.clear();
    m_threads.clear();
    m_fullscreenWorkers.clear();
    m_fullscreenThreads.clear();
    m_playbackWorkers.clear();
    m_playbackThreads.clear();
    m_queues.clear();
    m_fullscreenQueues.clear();
    m_playbackQueues.clear();
}

void FrigateStreamManager::restartStream(const QString& cameraName)
{
    stopStream(cameraName);
    getQueue(cameraName);
}

QObject* FrigateStreamManager::getWorker(const QString& cameraName)
{
    return m_workers.value(cameraName, nullptr);
}

QObject* FrigateStreamManager::getPlaybackWorker(const QString& cameraName)
{
    return m_playbackWorkers.value(cameraName, nullptr);
}