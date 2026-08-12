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
    queue->setMaxSize(4);
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

    if (worker && thread) {
        QObject::disconnect(worker, nullptr, this, nullptr);

        QObject::connect(worker, &FFmpegWorker::finished,
                         thread, &QThread::quit,
                         Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished,
                         worker, &QObject::deleteLater,
                         Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished,
                         thread, &QObject::deleteLater,
                         Qt::UniqueConnection);

        QMetaObject::invokeMethod(worker, "stopDecoding", Qt::QueuedConnection);
        return;
    }

    if (worker) {
        QObject::disconnect(worker, nullptr, this, nullptr);
        QMetaObject::invokeMethod(worker, "stopDecoding", Qt::QueuedConnection);
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
    m_clipEndSec.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}

void FrigatePlayback::seek(const QString& cameraId, qint64 timestampMs)
{
    startPlayback(cameraId, timestampMs);
}

void FrigatePlayback::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    startPlaybackInternal(cameraId, timestampMs, false);
}

void FrigatePlayback::startPlaybackInternal(const QString& cameraId,
                                            qint64 timestampMs,
                                            bool isContinue)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty()) {
        qWarning() << "[Playback] missing camera or server"
                   << "cam=" << cameraId << "server=" << m_server;
        return;
    }

    const qint64 wall = QDateTime::currentMSecsSinceEpoch();
    if (!isContinue) {
        if (m_lastSeekMs.contains(cameraId) &&
            (wall - m_lastSeekMs.value(cameraId) < 350)) {
            return;
        }
        m_lastSeekMs[cameraId] = wall;
        m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    }

    const int gen = m_seekGen.value(cameraId, 0);

    qint64 startSec = timestampMs;
    if (timestampMs > 100000000000LL)
        startSec = timestampMs / 1000;

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    // 30s segments — longer play, fewer restarts; still reasonable for Frigate mux
    qint64 endSec = startSec + 30;
    if (endSec > nowSec)
        endSec = nowSec;
    if (endSec <= startSec)
        endSec = startSec + 5;

    m_clipEndSec[cameraId] = endSec;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    qDebug() << "[Playback] start HTTP" << cameraId
             << startSec << "->" << endSec
             << (isContinue ? "(continue)" : "")
             << url;

    stopWorkerAsync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue) {
        qWarning() << "[Playback] no queue" << cameraId;
        return;
    }
    if (!isContinue)
        queue->resetReceived();

    const qint64 posMs = startSec * 1000;
    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);

    QTimer::singleShot(isContinue ? 30 : 80, this, [this, cameraId, gen, url, queue, endSec, isContinue]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;

        FFmpegWorker* worker = new FFmpegWorker(nullptr);
        worker->setUrl(url);
        worker->setFrameQueue(queue);
        // Faster first frames on 4K clips
        worker->setHighQuality(false);

        QThread* thread = new QThread();

        connect(worker, &FFmpegWorker::openInputOk, this,
                [this, cameraId, gen, isContinue]() {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;
            qDebug() << "[Playback] open OK" << cameraId
                     << (isContinue ? "(continue)" : "");
            emit cameraOnline(cameraId);
            if (!isContinue)
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

        // Segment ended — chain next window; do NOT emit playbackStopped
        // so UI stays in PLAYBACK until user presses Live
        connect(worker, &FFmpegWorker::streamStopped, this,
                [this, cameraId, gen, endSec]() {
            if (m_seekGen.value(cameraId, 0) != gen)
                return;

            qDebug() << "[Playback] segment end — chain next" << cameraId
                     << "from" << endSec;

            {
                QMutexLocker lock(&m_mutex);
                m_playbackWorkers.remove(cameraId);
                m_playbackThreads.remove(cameraId);
            }

            QTimer::singleShot(40, this, [this, cameraId, gen, endSec]() {
                if (m_seekGen.value(cameraId, 0) != gen)
                    return;
                const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
                if (endSec >= nowSec - 1)
                    return; // reached near-live; stay on last frame
                startPlaybackInternal(cameraId, endSec * 1000, true);
            });
        }, Qt::QueuedConnection);

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
    m_clipEndSec.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[Playback] live mode" << cameraId;
}