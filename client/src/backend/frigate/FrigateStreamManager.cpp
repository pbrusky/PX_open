#include "FrigateStreamManager.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QVariant>
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

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(false);   // grid low-res
    worker->setProperty("isProbe", false);

    m_workers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraName]() {
        emit cameraOnline(cameraName);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this, [this, cameraName](const QString&) {
        emit cameraOffline(cameraName);
        stopStream(cameraName);
    }, Qt::QueuedConnection);

    QThread* thread = new QThread(this);
    m_threads.insert(cameraName, thread);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit, Qt::QueuedConnection);
    connect(worker, &FFmpegWorker::finished, worker, &QObject::deleteLater, Qt::QueuedConnection);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater, Qt::QueuedConnection);

    worker->moveToThread(thread);
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
    worker->setHighQuality(true);    // fullscreen primary
    worker->setProperty("isProbe", false);

    m_fullscreenWorkers.insert(cameraName, worker);

    QThread* thread = new QThread(this);
    m_fullscreenThreads.insert(cameraName, thread);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit, Qt::QueuedConnection);
    connect(worker, &FFmpegWorker::finished, worker, &QObject::deleteLater, Qt::QueuedConnection);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater, Qt::QueuedConnection);

    worker->moveToThread(thread);
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

    QThread* thread = new QThread(this);
    m_playbackThreads.insert(cameraName, thread);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit, Qt::QueuedConnection);
    connect(worker, &FFmpegWorker::finished, worker, &QObject::deleteLater, Qt::QueuedConnection);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater, Qt::QueuedConnection);

    worker->moveToThread(thread);
    thread->start();

    return queue;
}

void FrigateStreamManager::stopStream(const QString& cameraName)
{
    auto stopOne = [](QHash<QString, FFmpegWorker*>& workers,
                      QHash<QString, QThread*>& threads,
                      const QString& name) {
        if (!workers.contains(name))
            return;

        FFmpegWorker* worker = workers.take(name);
        QThread* thread = threads.take(name);

        if (worker)
            worker->stopDecoding();

        if (thread) {
            thread->quit();
            thread->wait(2000);
        }
    };

    stopOne(m_workers, m_threads, cameraName);
    stopOne(m_fullscreenWorkers, m_fullscreenThreads, cameraName);
    stopOne(m_playbackWorkers, m_playbackThreads, cameraName);

    m_queues.remove(cameraName);
    m_fullscreenQueues.remove(cameraName);
    m_playbackQueues.remove(cameraName);
}

void FrigateStreamManager::stopAllStreams()
{
    QStringList keys = m_workers.keys();
    keys += m_fullscreenWorkers.keys();
    keys += m_playbackWorkers.keys();
    keys.removeDuplicates();

    for (const QString& name : keys)
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