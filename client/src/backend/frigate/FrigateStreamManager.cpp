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
    if (m_serverIp == ip)
        return;
    m_serverIp = ip;
    m_mainMissing.clear();
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
        thread->quit();
        if (!thread->wait(300))
            qDebug() << "[StreamManager] Thread still stopping (async)";
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

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(false); // grid: low res
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
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    thread->start();
    return queue;
}

void FrigateStreamManager::startFullscreenWorker(const QString& cameraName,
                                                 FrameQueue* queue,
                                                 const QString& url,
                                                 bool isFallback)
{
    qDebug() << "[StreamManager] Starting fullscreen stream:"
             << url << (isFallback ? "(hq-sub)" : "(main)");

    // Replace worker only — keep the same FrameQueue pointer for QML
    if (m_fullscreenWorkers.contains(cameraName)) {
        FFmpegWorker* oldW = m_fullscreenWorkers.take(cameraName);
        QThread* oldT = m_fullscreenThreads.take(cameraName);
        if (oldW)
            disconnect(oldW, nullptr, this, nullptr);
        stopWorkerThread(oldW, oldT);
    }

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true); // fullscreen: up to ~1920
    m_fullscreenWorkers.insert(cameraName, worker);

    QThread* thread = new QThread(nullptr);
    m_fullscreenThreads.insert(cameraName, thread);

    worker->moveToThread(thread);
    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    if (!isFallback) {
        const QString subUrl = buildRtspUrl(m_serverIp, cameraName);

        connect(worker, &FFmpegWorker::openInputFailed, this,
                [this, cameraName, queue, subUrl, worker](const QString& err) {
            if (m_fullscreenWorkers.value(cameraName) != worker)
                return;

            qWarning() << "[StreamManager] MAIN missing for"
                       << cameraName << ":" << err
                       << "→ fallback HQ sub" << subUrl;

            m_mainMissing.insert(cameraName);

            FFmpegWorker* oldW = m_fullscreenWorkers.take(cameraName);
            QThread* oldT = m_fullscreenThreads.take(cameraName);
            if (oldW)
                disconnect(oldW, nullptr, this, nullptr);
            stopWorkerThread(oldW, oldT);

            // Same FrameQueue — QML mainQueue pointer stays valid
            if (m_fullscreenQueues.value(cameraName) == queue)
                startFullscreenWorker(cameraName, queue, subUrl, true);
        }, Qt::QueuedConnection);
    }

    thread->start();
}

QObject* FrigateStreamManager::getFullscreenQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty() || m_serverIp.trimmed().isEmpty())
        return nullptr;

    // Reuse if already running — DO NOT stop/restart (that was killing MAIN)
    if (m_fullscreenQueues.contains(cameraName) &&
        m_fullscreenWorkers.contains(cameraName)) {
        qDebug() << "[StreamManager] Reusing fullscreen queue for" << cameraName;
        return m_fullscreenQueues[cameraName];
    }

    // Clean leftover queue without worker
    if (m_fullscreenQueues.contains(cameraName)) {
        FrameQueue* stale = m_fullscreenQueues.take(cameraName);
        if (stale)
            stale->deleteLater();
    }

    FrameQueue* queue = new FrameQueue(this);
    queue->setMaxSize(3);
    m_fullscreenQueues.insert(cameraName, queue);

    if (m_mainMissing.contains(cameraName)) {
        // Known missing *_main → HQ decode of base stream (real upgrade vs grid 640px)
        const QString subUrl = buildRtspUrl(m_serverIp, cameraName);
        startFullscreenWorker(cameraName, queue, subUrl, true);
    } else {
        const QString mainUrl = buildRtspUrl(m_serverIp, cameraName + QStringLiteral("_main"));
        startFullscreenWorker(cameraName, queue, mainUrl, false);
    }

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
    m_playbackWorkers.insert(cameraName, worker);

    QThread* thread = new QThread(nullptr);
    m_playbackThreads.insert(cameraName, thread);

    worker->moveToThread(thread);
    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    thread->start();
    return queue;
}

void FrigateStreamManager::stopFullscreenInternal(const QString& cameraName)
{
    if (m_fullscreenWorkers.contains(cameraName)) {
        FFmpegWorker* worker = m_fullscreenWorkers.take(cameraName);
        QThread* thread = m_fullscreenThreads.take(cameraName);
        if (worker)
            disconnect(worker, nullptr, this, nullptr);
        stopWorkerThread(worker, thread);
        qDebug() << "[StreamManager] Stopped fullscreen stream:" << cameraName;
    }

    if (m_fullscreenQueues.contains(cameraName)) {
        FrameQueue* q = m_fullscreenQueues.take(cameraName);
        if (q)
            q->deleteLater();
    }
}

void FrigateStreamManager::stopFullscreenStream(const QString& cameraName)
{
    stopFullscreenInternal(cameraName);
}

void FrigateStreamManager::stopAllFullscreenStreams()
{
    QStringList names = m_fullscreenWorkers.keys() + m_fullscreenQueues.keys();
    names = QSet<QString>(names.begin(), names.end()).values();
    for (const QString& name : names)
        stopFullscreenInternal(name);
}

void FrigateStreamManager::stopStream(const QString& cameraName)
{
    // Grid only — never touch fullscreen here
    if (m_workers.contains(cameraName)) {
        FFmpegWorker* worker = m_workers.take(cameraName);
        QThread* thread = m_threads.take(cameraName);
        if (worker)
            disconnect(worker, nullptr, this, nullptr);
        stopWorkerThread(worker, thread);
    }

    if (m_queues.contains(cameraName)) {
        FrameQueue* q = m_queues.take(cameraName);
        if (q)
            q->deleteLater();
    }

    if (m_playbackWorkers.contains(cameraName)) {
        FFmpegWorker* worker = m_playbackWorkers.take(cameraName);
        QThread* thread = m_playbackThreads.take(cameraName);
        if (worker)
            disconnect(worker, nullptr, this, nullptr);
        stopWorkerThread(worker, thread);
    }

    if (m_playbackQueues.contains(cameraName)) {
        FrameQueue* q = m_playbackQueues.take(cameraName);
        if (q)
            q->deleteLater();
    }
}

void FrigateStreamManager::stopAllStreams()
{
    stopAllFullscreenStreams();

    QStringList names = m_workers.keys() + m_playbackWorkers.keys()
                      + m_queues.keys() + m_playbackQueues.keys();
    names = QSet<QString>(names.begin(), names.end()).values();
    for (const QString& name : names)
        stopStream(name);

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
    stopFullscreenStream(cameraName);
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