#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>
#include <QMetaObject>
#include <QTimer>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
{
}

FrigatePlayback::~FrigatePlayback()
{
    for (auto it = m_seekGen.begin(); it != m_seekGen.end(); ++it)
        it.value() = it.value() + 1;

    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys)
        stopWorkerAsync(id);
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

    if (worker) {
        worker->setFrameQueue(nullptr);
        QObject::disconnect(worker, nullptr, this, nullptr);
        QMetaObject::invokeMethod(worker, "stopDecoding", Qt::QueuedConnection);
    }

    if (worker && thread) {
        QObject::connect(worker, &FFmpegWorker::finished,
                         thread, &QThread::quit,
                         Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished,
                         worker, &QObject::deleteLater,
                         Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished,
                         thread, &QObject::deleteLater,
                         Qt::UniqueConnection);
        return;
    }

    if (worker) {
        QObject::connect(worker, &FFmpegWorker::finished,
                         worker, &QObject::deleteLater,
                         Qt::UniqueConnection);
        return;
    }

    if (thread) {
        QObject::connect(thread, &QThread::finished,
                         thread, &QObject::deleteLater,
                         Qt::UniqueConnection);
        if (thread->isRunning())
            QMetaObject::invokeMethod(thread, "quit", Qt::QueuedConnection);
        else
            thread->deleteLater();
    }
}

void FrigatePlayback::stopPlayback(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty())
        return;

    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    stopWorkerAsync(cameraId);
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
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty()) {
        qWarning() << "[Playback] missing camera or server";
        return;
    }

    const qint64 wall = QDateTime::currentMSecsSinceEpoch();
    if (m_lastSeekMs.contains(cameraId) &&
        (wall - m_lastSeekMs.value(cameraId) < 800)) {
        return;
    }
    m_lastSeekMs[cameraId] = wall;

    const int gen = m_seekGen.value(cameraId, 0) + 1;
    m_seekGen[cameraId] = gen;

    qint64 startSec = timestampMs;
    if (timestampMs > 100000000000LL)
        startSec = timestampMs / 1000;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (startSec > nowSec - 30)
        startSec = nowSec - 30;
    if (startSec < 1)
        startSec = 1;

    qint64 endSec = startSec + 60;
    if (endSec > nowSec - 5)
        endSec = nowSec - 5;
    if (endSec <= startSec)
        endSec = startSec + 10;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    stopWorkerAsync(cameraId);

    FrameQueue* queue = nullptr;
    {
        QMutexLocker lock(&m_mutex);
        if (!m_playbackQueues.contains(cameraId)) {
            FrameQueue* q = new FrameQueue(this);
            q->setMaxSize(2);
            m_playbackQueues.insert(cameraId, q);
        }
        queue = m_playbackQueues.value(cameraId);
        if (queue)
            queue->resetReceived();
    }

    if (!queue) {
        qWarning() << "[Playback] no queue" << cameraId;
        return;
    }

    const qint64 posMs = startSec * 1000;
    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);

    // Let previous worker/thread finish before starting a new one
    QTimer::singleShot(500, this, [this, cameraId, gen, url, queue]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        if (!queue)
            return;

        {
            QMutexLocker lock(&m_mutex);
            if (m_playbackWorkers.contains(cameraId))
                return;
        }

        FFmpegWorker* worker = new FFmpegWorker(nullptr);
        worker->setUrl(url);
        worker->setFrameQueue(queue);
        worker->setHighQuality(false);

        QThread* thread = new QThread();

        connect(worker, &FFmpegWorker::openInputOk, this,
                [this, cameraId, gen]() {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;
            emit cameraOnline(cameraId);
            emit playbackStarted(cameraId);
        }, Qt::QueuedConnection);

        // 400 / no video: clear maps so we never use a deleted worker
        connect(worker, &FFmpegWorker::openInputFailed, this,
                [this, cameraId, gen, url](const QString& reason) {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;
            qWarning() << "[Playback] open failed" << cameraId << reason << url;

            {
                QMutexLocker lock(&m_mutex);
                m_playbackWorkers.remove(cameraId);
                m_playbackThreads.remove(cameraId);
            }

            emit cameraOffline(cameraId);
            emit playbackStopped(cameraId);
        }, Qt::QueuedConnection);

        // Normal end of clip — no auto-chain (that caused races)
        connect(worker, &FFmpegWorker::streamStopped, this,
                [this, cameraId, gen]() {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;

            {
                QMutexLocker lock(&m_mutex);
                m_playbackWorkers.remove(cameraId);
                m_playbackThreads.remove(cameraId);
            }

            emit playbackStopped(cameraId);
        }, Qt::QueuedConnection);

        connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
        connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
        connect(thread, &QThread::finished, worker, &QObject::deleteLater);
        connect(thread, &QThread::finished, thread, &QObject::deleteLater);

        // Thread fully done — clear maps again if still present
        connect(thread, &QThread::finished, this,
                [this, cameraId, gen]() {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;
            QMutexLocker lock(&m_mutex);
            m_playbackWorkers.remove(cameraId);
            m_playbackThreads.remove(cameraId);
        }, Qt::QueuedConnection);

        {
            QMutexLocker lock(&m_mutex);
            if (m_seekGen.value(cameraId, 0) != gen) {
                worker->deleteLater();
                thread->deleteLater();
                return;
            }
            m_playbackWorkers.insert(cameraId, worker);
            m_playbackThreads.insert(cameraId, thread);
        }

        worker->moveToThread(thread);
        thread->start();
    });
}

qint64 FrigatePlayback::currentPosition(const QString& cameraId) const
{
    return m_playbackPositionByCamera.value(cameraId, 0);
}

void FrigatePlayback::switchToLive(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty())
        return;

    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    stopWorkerAsync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}