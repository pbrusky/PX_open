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
        // Detach queue so a dying worker cannot push into a reused queue
        worker->setFrameQueue(nullptr);
        QObject::disconnect(worker, nullptr, this, nullptr);
        QMetaObject::invokeMethod(worker, "stopDecoding", Qt::QueuedConnection);
    }

    if (worker && thread) {
        // Ensure thread exits when worker finishes (may already be connected)
        QObject::connect(worker, &FFmpegWorker::finished,
                         thread, &QThread::quit,
                         Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished,
                         worker, &QObject::deleteLater,
                         Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished,
                         thread, &QObject::deleteLater,
                         Qt::UniqueConnection);
        // If already finished, quit is a no-op and finished may have fired —
        // schedule a fallback cleanup
        if (!thread->isRunning()) {
            worker->deleteLater();
            thread->deleteLater();
        }
        return;
    }

    if (worker)
        worker->deleteLater();

    if (thread) {
        if (thread->isRunning())
            QMetaObject::invokeMethod(thread, "quit", Qt::QueuedConnection);
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
        qWarning() << "[Playback] missing camera or server"
                   << "cam=" << cameraId << "server=" << m_server;
        return;
    }

    const qint64 wall = QDateTime::currentMSecsSinceEpoch();
    if (m_lastSeekMs.contains(cameraId) &&
        (wall - m_lastSeekMs.value(cameraId) < 400)) {
        return;
    }
    m_lastSeekMs[cameraId] = wall;

    const int gen = m_seekGen.value(cameraId, 0) + 1;
    m_seekGen[cameraId] = gen;

    qint64 startSec = timestampMs;
    if (timestampMs > 100000000000LL)
        startSec = timestampMs / 1000;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    if (startSec > nowSec - 10)
        startSec = nowSec - 10;
    if (startSec < 1)
        startSec = 1;

    qint64 endSec = startSec + 6;
    if (endSec > nowSec)
        endSec = nowSec;
    if (endSec <= startSec)
        endSec = startSec + 2;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    qDebug() << "[Playback] start HTTP" << cameraId
             << startSec << "->" << endSec << url;

    // Stop previous worker and clear maps (prevents dangling pointer on 2nd seek)
    stopWorkerAsync(cameraId);

    FrameQueue* queue = nullptr;
    {
        QMutexLocker lock(&m_mutex);
        // Always use a fresh queue per seek generation so a dying worker
        // cannot write into the queue used by the new worker.
        if (m_playbackQueues.contains(cameraId)) {
            FrameQueue* old = m_playbackQueues.take(cameraId);
            if (old) {
                old->setParent(nullptr);
                QTimer::singleShot(500, old, &QObject::deleteLater);
            }
        }
        queue = new FrameQueue(this);
        queue->setMaxSize(2);
        m_playbackQueues.insert(cameraId, queue);
    }

    const qint64 posMs = startSec * 1000;
    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);

    // Brief delay so previous stopDecoding can take effect
    QTimer::singleShot(200, this, [this, cameraId, gen, url, queue]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        if (!queue)
            return;

        // Queue must still be the one we registered for this seek
        {
            QMutexLocker lock(&m_mutex);
            if (m_playbackQueues.value(cameraId) != queue)
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
            qDebug() << "[Playback] open OK" << cameraId;
            emit cameraOnline(cameraId);
            emit playbackStarted(cameraId);
        }, Qt::QueuedConnection);

        connect(worker, &FFmpegWorker::openInputFailed, this,
                [this, cameraId, gen](const QString& reason) {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;
            qWarning() << "[Playback] open failed" << cameraId << reason;
            emit cameraOffline(cameraId);
            emit playbackStopped(cameraId);
        }, Qt::QueuedConnection);

        // When worker finishes (clip end or stop), remove from maps FIRST
        // so a later seek never touches a dangling pointer.
        connect(worker, &FFmpegWorker::finished, this,
                [this, cameraId, worker, thread]() {
            QMutexLocker lock(&m_mutex);
            if (m_playbackWorkers.value(cameraId) == worker)
                m_playbackWorkers.remove(cameraId);
            if (m_playbackThreads.value(cameraId) == thread)
                m_playbackThreads.remove(cameraId);
        }, Qt::DirectConnection);

        connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
        connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
        connect(thread, &QThread::finished, worker, &QObject::deleteLater);
        connect(thread, &QThread::finished, thread, &QObject::deleteLater);

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
    qDebug() << "[Playback] live mode" << cameraId;
}