#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
{
}

FrigatePlayback::~FrigatePlayback()
{
    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys)
        stopWorkerSync(id);
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
    queue->setMaxSize(3);
    m_playbackQueues.insert(cameraId, queue);
    return queue;
}

void FrigatePlayback::stopWorkerSync(const QString& cameraId)
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

    // Prevent auto-cleanup slots from racing with this function
    if (worker)
        QObject::disconnect(worker, nullptr, this, nullptr);
    if (thread)
        QObject::disconnect(thread, nullptr, this, nullptr);

    if (worker) {
        if (thread)
            QObject::disconnect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
        worker->stopDecoding();
    }

    if (thread) {
        if (thread->isRunning()) {
            thread->quit();
            if (!thread->wait(10000)) {
                qWarning() << "[Playback] thread wait timeout, terminate" << cameraId;
                thread->terminate();
                thread->wait(1000);
            }
        }
        // Thread is fully stopped — safe to delete
        delete thread;
        thread = nullptr;
    }

    if (worker) {
        // Worker is no longer running on a thread
        delete worker;
        worker = nullptr;
    }
}

void FrigatePlayback::stopPlayback(const QString& cameraId)
{
    stopWorkerSync(cameraId);
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
        qDebug() << "[Playback] debounced seek" << cameraId;
        return;
    }
    m_lastSeekMs[cameraId] = wall;

    qint64 startSec = timestampMs;
    if (timestampMs > 100000000000LL) // ms → sec
        startSec = timestampMs / 1000;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    qint64 endSec = startSec + 30;
    if (endSec > nowSec)
        endSec = nowSec;
    if (endSec <= startSec)
        endSec = startSec + 10;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    qDebug() << "[Playback] start" << cameraId << startSec << "->" << endSec << url;

    // Fully stop previous worker/thread BEFORE creating a new one
    stopWorkerSync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue)
        return;
    if (queue->metaObject()->indexOfMethod("resetReceived()") >= 0)
        QMetaObject::invokeMethod(queue, "resetReceived");

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true);

    QThread* thread = new QThread(); // no parent — we own lifetime

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraId]() {
        qDebug() << "[Playback] open OK" << cameraId;
        emit cameraOnline(cameraId);
        emit playbackStarted(cameraId);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::openInputFailed, this,
            [this, cameraId](const QString& reason) {
        qWarning() << "[Playback] open failed" << cameraId << reason;
        emit cameraOffline(cameraId);
    }, Qt::QueuedConnection);

    // Only quit the thread when worker finishes — do NOT deleteLater here
    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);

    {
        QMutexLocker lock(&m_mutex);
        m_playbackWorkers.insert(cameraId, worker);
        m_playbackThreads.insert(cameraId, thread);
    }

    worker->moveToThread(thread);
    thread->start();

    const qint64 posMs = startSec * 1000;
    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);
}

qint64 FrigatePlayback::currentPosition(const QString& cameraId) const
{
    return m_playbackPositionByCamera.value(cameraId, 0);
}

void FrigatePlayback::switchToLive(const QString& cameraId)
{
    if (cameraId.trimmed().isEmpty())
        return;

    stopWorkerSync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[Playback] live mode" << cameraId;
}