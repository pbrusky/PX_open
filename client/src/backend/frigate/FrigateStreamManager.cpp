#include "FrigateStreamManager.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QVariant>
#include <QSet>
#include <QThread>
#include <QTimer>
#include <QDateTime>

FrigateStreamManager::FrigateStreamManager(QObject* parent)
    : QObject(parent)
{
}

FrigateStreamManager::~FrigateStreamManager()
{
    stopAllStreamsAndWait(2000);
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
    return QStringLiteral("rtsp://%1:8554/%2").arg(serverIp, cameraName);
}

static void stopWorkerThreadAsync(FFmpegWorker* worker, QThread* thread)
{
    Q_UNUSED(thread);
    if (!worker)
        return;
    QObject::disconnect(worker, &FFmpegWorker::openInputFailed, nullptr, nullptr);
    QObject::disconnect(worker, &FFmpegWorker::openInputOk, nullptr, nullptr);
    QObject::disconnect(worker, &FFmpegWorker::statsUpdated, nullptr, nullptr);
    QObject::disconnect(worker, &FFmpegWorker::streamStarted, nullptr, nullptr);
    QObject::disconnect(worker, &FFmpegWorker::streamStopped, nullptr, nullptr);
    worker->stopDecoding();
}

QObject* FrigateStreamManager::getQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty() || m_serverIp.trimmed().isEmpty())
        return nullptr;

    if (m_queues.contains(cameraName))
        return m_queues[cameraName];

    FrameQueue* queue = new FrameQueue(this);
    queue->setMaxSize(2);
    m_queues.insert(cameraName, queue);

    const QString url = buildRtspUrl(m_serverIp, cameraName);

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(false);
    m_workers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraName]() {
        emit cameraOnline(cameraName);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this, [this, cameraName](const QString&) {
        emit cameraOffline(cameraName);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::statsUpdated, this,
            [this, cameraName](const QString& resolution, double fps,
                               int bitrateKbps, const QString& codec) {
        m_statResolution[cameraName] = resolution;
        m_statFps[cameraName] = fps;
        m_statBitrate[cameraName] = bitrateKbps;
        m_statCodec[cameraName] = codec;
        emit cameraStatsChanged(cameraName, resolution, fps, bitrateKbps, codec);
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
    if (m_fullscreenWorkers.contains(cameraName)) {
        FFmpegWorker* oldW = m_fullscreenWorkers.take(cameraName);
        QThread* oldT = m_fullscreenThreads.take(cameraName);
        stopWorkerThreadAsync(oldW, oldT);
    }

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    // highQuality=true caused huge QImage alloc failures → zero frames.
    // false still shows the MAIN profile (e.g. Channels/101) vs SUB (102),
    // scaled to ~1280 for stability.
    worker->setHighQuality(false);
    m_fullscreenWorkers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraName, isFallback]() {
        Q_UNUSED(isFallback);
        emit cameraOnline(cameraName);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::statsUpdated, this,
            [this, cameraName](const QString& resolution, double fps,
                               int bitrateKbps, const QString& codec) {
        m_statResolution[cameraName] = resolution;
        m_statFps[cameraName] = fps;
        m_statBitrate[cameraName] = bitrateKbps;
        m_statCodec[cameraName] = codec;
        emit cameraStatsChanged(cameraName, resolution, fps, bitrateKbps, codec);
    }, Qt::QueuedConnection);

    if (!isFallback) {
        // Trying camera_main. On fail → start base once (do not loop).
        connect(worker, &FFmpegWorker::openInputFailed, this,
                [this, cameraName](const QString& reason) {
            Q_UNUSED(reason);
            m_mainMissing.insert(cameraName);

            FFmpegWorker* w = m_fullscreenWorkers.take(cameraName);
            QThread* t = m_fullscreenThreads.take(cameraName);
            stopWorkerThreadAsync(w, t);

            QTimer::singleShot(50, this, [this, cameraName]() {
                if (!m_fullscreenQueues.contains(cameraName))
                    return;
                FrameQueue* q = m_fullscreenQueues.value(cameraName);
                if (!q)
                    return;
                m_fullscreenFrameNotified.remove(cameraName);
                q->resetReceived();
                const QString baseUrl = buildRtspUrl(m_serverIp, cameraName);
                startFullscreenWorker(cameraName, q, baseUrl, true);
            });
        }, Qt::QueuedConnection);
    } else {
        connect(worker, &FFmpegWorker::openInputFailed, this,
                [this, cameraName](const QString& reason) {
            Q_UNUSED(reason);
            FFmpegWorker* w = m_fullscreenWorkers.take(cameraName);
            QThread* t = m_fullscreenThreads.take(cameraName);
            stopWorkerThreadAsync(w, t);
            emit fullscreenUsingSub(cameraName);
        }, Qt::QueuedConnection);
    }

    QThread* thread = new QThread(nullptr);
    m_fullscreenThreads.insert(cameraName, thread);

    worker->moveToThread(thread);
    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    thread->start();
}

QObject* FrigateStreamManager::getFullscreenQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty() || m_serverIp.trimmed().isEmpty())
        return nullptr;

    // Reuse dedicated fullscreen worker if already running
    if (m_fullscreenQueues.contains(cameraName) &&
        m_fullscreenWorkers.contains(cameraName)) {
        return m_fullscreenQueues[cameraName];
    }

    // Drop stale queue without a worker
    if (m_fullscreenQueues.contains(cameraName)) {
        FrameQueue* stale = m_fullscreenQueues.take(cameraName);
        if (stale) {
            stale->setParent(nullptr);
            QTimer::singleShot(200, stale, &QObject::deleteLater);
        }
    }

    m_fullscreenFrameNotified.remove(cameraName);

    FrameQueue* queue = new FrameQueue(this);
    queue->setMaxSize(2);
    queue->resetReceived();
    m_fullscreenQueues.insert(cameraName, queue);

    connect(queue, &FrameQueue::frameReady, this,
            [this, cameraName]() {
        if (!m_fullscreenQueues.contains(cameraName))
            return;
        if (!m_fullscreenFrameNotified.contains(cameraName))
            m_fullscreenFrameNotified.insert(cameraName);
        emit fullscreenFrameReady(cameraName);
    }, Qt::QueuedConnection);

    // Prefer real main profile (test4_main). Cameras without it get one 404 then base.
    if (!m_mainMissing.contains(cameraName)) {
        const QString mainUrl =
            buildRtspUrl(m_serverIp, cameraName + QStringLiteral("_main"));
        startFullscreenWorker(cameraName, queue, mainUrl, false);
    } else {
        const QString baseUrl = buildRtspUrl(m_serverIp, cameraName);
        startFullscreenWorker(cameraName, queue, baseUrl, true);
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
    return queue;
}

void FrigateStreamManager::stopFullscreenInternal(const QString& cameraName)
{
    m_fullscreenFrameNotified.remove(cameraName);

    if (m_fullscreenWorkers.contains(cameraName)) {
        FFmpegWorker* worker = m_fullscreenWorkers.take(cameraName);
        QThread* thread = m_fullscreenThreads.take(cameraName);
        stopWorkerThreadAsync(worker, thread);
    }

    if (m_fullscreenQueues.contains(cameraName)) {
        FrameQueue* q = m_fullscreenQueues.take(cameraName);
        if (q) {
            q->setParent(nullptr);
            QTimer::singleShot(200, q, &QObject::deleteLater);
        }
    }
}

void FrigateStreamManager::stopFullscreenStream(const QString& cameraName)
{
    stopFullscreenInternal(cameraName);
}

void FrigateStreamManager::stopAllFullscreenStreams()
{
    const QStringList names = m_fullscreenWorkers.keys() + m_fullscreenQueues.keys();
    const QSet<QString> unique(names.begin(), names.end());
    for (const QString& name : unique)
        stopFullscreenInternal(name);
}

void FrigateStreamManager::stopStream(const QString& cameraName)
{
    stopFullscreenInternal(cameraName);

    if (m_workers.contains(cameraName)) {
        FFmpegWorker* worker = m_workers.take(cameraName);
        QThread* thread = m_threads.take(cameraName);
        stopWorkerThreadAsync(worker, thread);
    }

    if (m_queues.contains(cameraName)) {
        FrameQueue* q = m_queues.take(cameraName);
        if (q) {
            q->setParent(nullptr);
            QTimer::singleShot(200, q, &QObject::deleteLater);
        }
    }

    m_statResolution.remove(cameraName);
    m_statFps.remove(cameraName);
    m_statBitrate.remove(cameraName);
    m_statCodec.remove(cameraName);

    if (m_playbackWorkers.contains(cameraName)) {
        FFmpegWorker* worker = m_playbackWorkers.take(cameraName);
        QThread* thread = m_playbackThreads.take(cameraName);
        stopWorkerThreadAsync(worker, thread);
    }

    if (m_playbackQueues.contains(cameraName)) {
        FrameQueue* q = m_playbackQueues.take(cameraName);
        if (q) {
            q->setParent(nullptr);
            QTimer::singleShot(200, q, &QObject::deleteLater);
        }
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

void FrigateStreamManager::stopAllStreamsAndWait(int timeoutMs)
{
    if (timeoutMs < 100)
        timeoutMs = 100;

    QList<FFmpegWorker*> workers;
    QList<QThread*> threads;

    auto harvest = [&](QHash<QString, FFmpegWorker*>& wh,
                       QHash<QString, QThread*>& th) {
        const QStringList keys = wh.keys();
        for (const QString& k : keys) {
            workers.append(wh.take(k));
            if (th.contains(k))
                threads.append(th.take(k));
        }
        th.clear();
    };

    harvest(m_workers, m_threads);
    harvest(m_fullscreenWorkers, m_fullscreenThreads);
    harvest(m_playbackWorkers, m_playbackThreads);

    auto dropQueues = [](QHash<QString, FrameQueue*>& qs) {
        for (FrameQueue* q : qs) {
            if (!q)
                continue;
            q->setParent(nullptr);
            q->deleteLater();
        }
        qs.clear();
    };
    dropQueues(m_queues);
    dropQueues(m_fullscreenQueues);
    dropQueues(m_playbackQueues);
    m_fullscreenFrameNotified.clear();
    m_statResolution.clear();
    m_statFps.clear();
    m_statBitrate.clear();
    m_statCodec.clear();

    for (FFmpegWorker* w : workers) {
        if (!w)
            continue;
        QObject::disconnect(w, nullptr, nullptr, nullptr);
        w->stopDecoding();
    }

    for (QThread* t : threads) {
        if (t)
            t->quit();
    }

    const qint64 startMs = QDateTime::currentMSecsSinceEpoch();
    for (QThread* t : threads) {
        if (!t)
            continue;
        const int left = timeoutMs - int(QDateTime::currentMSecsSinceEpoch() - startMs);
        const unsigned long waitMs = left > 0 ? unsigned(left) : 1u;
        if (!t->wait(waitMs)) {
            t->terminate();
            t->wait(300);
        }
    }
}

void FrigateStreamManager::restartStream(const QString& cameraName)
{
    stopStream(cameraName);
    getQueue(cameraName);
}

QObject* FrigateStreamManager::getWorker(const QString& cameraName)
{
    Q_UNUSED(cameraName);
    return nullptr;
}

QObject* FrigateStreamManager::getPlaybackWorker(const QString& cameraName)
{
    Q_UNUSED(cameraName);
    return nullptr;
}

QString FrigateStreamManager::cameraResolution(const QString& cameraName) const
{
    return m_statResolution.value(cameraName);
}

double FrigateStreamManager::cameraFps(const QString& cameraName) const
{
    return m_statFps.value(cameraName, 0.0);
}

int FrigateStreamManager::cameraBitrateKbps(const QString& cameraName) const
{
    return m_statBitrate.value(cameraName, 0);
}

QString FrigateStreamManager::cameraCodec(const QString& cameraName) const
{
    return m_statCodec.value(cameraName);
}