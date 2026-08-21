#include "FrigateStreamManager.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QVariant>
#include <QSet>
#include <QThread>
#include <QTimer>
#include <QDateTime>
#include <QUrl>

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
    m_fullscreenIsTrueMain.clear();
}

QString FrigateStreamManager::injectRtspAuth(const QString& url,
                                            const QString& user,
                                            const QString& pass)
{
    if (url.isEmpty() || user.isEmpty())
        return url;
    if (!url.startsWith(QLatin1String("rtsp://"), Qt::CaseInsensitive))
        return url;

    QString rest = url.mid(7);
    if (rest.contains(QLatin1Char('@')))
        return url;

    const QString encUser = QString::fromUtf8(QUrl::toPercentEncoding(user));
    const QString encPass = QString::fromUtf8(QUrl::toPercentEncoding(pass));
    return QStringLiteral("rtsp://%1:%2@%3").arg(encUser, encPass, rest);
}

void FrigateStreamManager::setCameraDirectMainUrl(const QString& cameraName,
                                                  const QString& mainRtspUrl,
                                                  const QString& username,
                                                  const QString& password)
{
    if (cameraName.trimmed().isEmpty())
        return;

    if (mainRtspUrl.trimmed().isEmpty()) {
        m_directMainUrls.remove(cameraName);
        m_cameraUser.remove(cameraName);
        m_cameraPass.remove(cameraName);
        return;
    }

    m_directMainUrls.insert(cameraName, mainRtspUrl.trimmed());
    if (!username.isEmpty())
        m_cameraUser.insert(cameraName, username);
    else
        m_cameraUser.remove(cameraName);
    if (!password.isEmpty())
        m_cameraPass.insert(cameraName, password);
    else
        m_cameraPass.remove(cameraName);
}

void FrigateStreamManager::clearCameraDirectMainUrls()
{
    m_directMainUrls.clear();
    m_cameraUser.clear();
    m_cameraPass.clear();
}

static QString buildRtspUrl(const QString& serverIp, const QString& cameraName)
{
    return QStringLiteral("rtsp://%1:8554/%2").arg(serverIp, cameraName);
}

QString FrigateStreamManager::urlForFullscreenStage(const QString& cameraName, int stage) const
{
    // Prefer go2rtc first so we do not hang on camera RTSP 401:
    //   0 = "<name>_main" (dual-stream main)
    //   1 = "<name>"      (single-stream / sub)
    //   2 = direct camera RTSP (last resort)
    if (stage == 0)
        return buildRtspUrl(m_serverIp, cameraName + QStringLiteral("_main"));

    if (stage == 1)
        return buildRtspUrl(m_serverIp, cameraName);

    if (stage == 2) {
        const QString direct = m_directMainUrls.value(cameraName);
        if (direct.isEmpty())
            return QString();
        if (direct.contains(QLatin1String(":8554/")))
            return QString();
        return injectRtspAuth(direct,
                              m_cameraUser.value(cameraName),
                              m_cameraPass.value(cameraName));
    }

    return QString();
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

void FrigateStreamManager::startGridWorker(const QString& cameraName,
                                           FrameQueue* queue,
                                           int attempt)
{
    if (!queue || cameraName.isEmpty() || m_serverIp.isEmpty())
        return;

    if (m_workers.contains(cameraName)) {
        FFmpegWorker* oldW = m_workers.take(cameraName);
        QThread* oldT = m_threads.take(cameraName);
        stopWorkerThreadAsync(oldW, oldT);
    }

    const QString url = buildRtspUrl(m_serverIp, cameraName);

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(false);
    m_workers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraName]() {
        emit cameraOnline(cameraName);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this,
            [this, cameraName, attempt](const QString&) {
        emit cameraOffline(cameraName);

        FFmpegWorker* w = m_workers.take(cameraName);
        QThread* t = m_threads.take(cameraName);
        stopWorkerThreadAsync(w, t);

        if (attempt < 4) {
            const int delayMs = (attempt == 0) ? 2000
                              : (attempt == 1) ? 3000
                              : (attempt == 2) ? 5000
                              : 8000;
            QTimer::singleShot(delayMs, this, [this, cameraName, attempt]() {
                if (!m_queues.contains(cameraName))
                    return;
                FrameQueue* q = m_queues.value(cameraName);
                if (!q)
                    return;
                startGridWorker(cameraName, q, attempt + 1);
            });
        }
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
}

QObject* FrigateStreamManager::getQueue(const QString& cameraName)
{
    if (cameraName.trimmed().isEmpty() || m_serverIp.trimmed().isEmpty())
        return nullptr;

    if (m_queues.contains(cameraName) && m_workers.contains(cameraName))
        return m_queues[cameraName];

    FrameQueue* queue = m_queues.value(cameraName, nullptr);
    if (!queue) {
        queue = new FrameQueue(this);
        queue->setMaxSize(2);
        m_queues.insert(cameraName, queue);
    }

    startGridWorker(cameraName, queue, 0);
    return queue;
}

void FrigateStreamManager::startFullscreenWorker(const QString& cameraName,
                                                 FrameQueue* queue,
                                                 int stage)
{
    if (stage < 0 || stage > 2)
        return;

    QString url = urlForFullscreenStage(cameraName, stage);
    while (url.isEmpty() && stage < 2) {
        ++stage;
        url = urlForFullscreenStage(cameraName, stage);
    }
    if (url.isEmpty())
        return;

    if (m_fullscreenWorkers.contains(cameraName)) {
        FFmpegWorker* oldW = m_fullscreenWorkers.take(cameraName);
        QThread* oldT = m_fullscreenThreads.take(cameraName);
        stopWorkerThreadAsync(oldW, oldT);
    }

    m_fullscreenIsTrueMain.remove(cameraName);

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true);
    m_fullscreenWorkers.insert(cameraName, worker);

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraName, stage]() {
        const bool trueMain = (stage == 0)
            || (stage == 1 && m_mainMissing.contains(cameraName))
            || (stage == 2);
        if (trueMain) {
            m_fullscreenIsTrueMain.insert(cameraName);
            emit fullscreenMainStatus(cameraName, true);
        } else {
            m_fullscreenIsTrueMain.remove(cameraName);
            emit fullscreenMainStatus(cameraName, false);
        }
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

    connect(worker, &FFmpegWorker::openInputFailed, this,
            [this, cameraName, stage](const QString&) {
        FFmpegWorker* w = m_fullscreenWorkers.take(cameraName);
        QThread* t = m_fullscreenThreads.take(cameraName);
        stopWorkerThreadAsync(w, t);

        if (stage == 0)
            m_mainMissing.insert(cameraName);

        if (stage < 2) {
            QTimer::singleShot(50, this, [this, cameraName, stage]() {
                if (!m_fullscreenQueues.contains(cameraName))
                    return;
                FrameQueue* q = m_fullscreenQueues.value(cameraName);
                if (!q)
                    return;
                m_fullscreenFrameNotified.remove(cameraName);
                q->resetReceived();
                startFullscreenWorker(cameraName, q, stage + 1);
            });
        } else {
            m_fullscreenIsTrueMain.remove(cameraName);
            emit fullscreenMainStatus(cameraName, false);
            emit fullscreenUsingSub(cameraName);
        }
    }, Qt::QueuedConnection);

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

    if (m_fullscreenQueues.contains(cameraName) &&
        m_fullscreenWorkers.contains(cameraName)) {
        return m_fullscreenQueues[cameraName];
    }

    if (m_fullscreenQueues.contains(cameraName)) {
        FrameQueue* stale = m_fullscreenQueues.take(cameraName);
        if (stale) {
            stale->setParent(nullptr);
            QTimer::singleShot(200, stale, &QObject::deleteLater);
        }
    }

    m_fullscreenFrameNotified.remove(cameraName);
    m_fullscreenIsTrueMain.remove(cameraName);

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

    const int startStage = m_mainMissing.contains(cameraName) ? 1 : 0;
    startFullscreenWorker(cameraName, queue, startStage);

    return queue;
}

bool FrigateStreamManager::isFullscreenTrueMain(const QString& cameraName) const
{
    return m_fullscreenIsTrueMain.contains(cameraName);
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
    m_fullscreenIsTrueMain.remove(cameraName);

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
    m_fullscreenIsTrueMain.clear();
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