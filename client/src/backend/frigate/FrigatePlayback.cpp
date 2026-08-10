#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUuid>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
{
}

FrigatePlayback::~FrigatePlayback()
{
    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys) {
        cancelDownload(id);
        stopWorkerAsync(id);
    }
    const QStringList curlKeys = m_curlProcs.keys();
    for (const QString& id : curlKeys)
        cancelDownload(id);
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

void FrigatePlayback::cancelDownload(const QString& cameraId)
{
    if (m_progressTimers.contains(cameraId)) {
        QTimer* t = m_progressTimers.take(cameraId);
        if (t) {
            t->stop();
            t->deleteLater();
        }
    }

    if (m_curlProcs.contains(cameraId)) {
        QProcess* p = m_curlProcs.take(cameraId);
        if (p) {
            QObject::disconnect(p, nullptr, this, nullptr);
            if (p->state() != QProcess::NotRunning) {
                p->kill();
                p->waitForFinished(2000);
            }
            p->deleteLater();
        }
    }

    if (m_curlPaths.contains(cameraId)) {
        const QString path = m_curlPaths.take(cameraId);
        if (!path.isEmpty() && QFile::exists(path))
            QFile::remove(path);
    }
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

    if (worker)
        QObject::disconnect(worker, nullptr, this, nullptr);

    if (worker)
        worker->stopDecoding();

    if (thread) {
        if (worker) {
            QObject::connect(thread, &QThread::finished,
                             worker, &QObject::deleteLater,
                             Qt::UniqueConnection);
            QObject::connect(worker, &FFmpegWorker::finished,
                             thread, &QThread::quit,
                             Qt::UniqueConnection);
        }
        QObject::connect(thread, &QThread::finished,
                         thread, &QObject::deleteLater,
                         Qt::UniqueConnection);

        if (thread->isRunning()) {
            QMetaObject::invokeMethod(thread, "quit", Qt::QueuedConnection);
        } else {
            if (worker)
                worker->deleteLater();
            thread->deleteLater();
        }
    } else if (worker) {
        worker->deleteLater();
    }
}

void FrigatePlayback::stopPlayback(const QString& cameraId)
{
    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    cancelDownload(cameraId);
    stopWorkerAsync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[Playback] stopPlayback" << cameraId;
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
        (wall - m_lastSeekMs.value(cameraId) < 600)) {
        return;
    }
    m_lastSeekMs[cameraId] = wall;

    const int gen = m_seekGen.value(cameraId, 0) + 1;
    m_seekGen[cameraId] = gen;

    qint64 startSec = timestampMs;
    if (timestampMs > 100000000000LL)
        startSec = timestampMs / 1000;

    // Short 4s window — faster Frigate mux
    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    qint64 endSec = startSec + 4;
    if (endSec > nowSec)
        endSec = nowSec;
    if (endSec <= startSec)
        endSec = startSec + 3;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    const QString tmpDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    const QString path = QDir(tmpDir).filePath(
        QStringLiteral("px_clip_%1_%2.mp4")
            .arg(cameraId, QUuid::createUuid().toString(QUuid::Id128).left(8)));

    qDebug() << "[Playback] curl download" << cameraId << startSec << "->" << endSec << url;
    qDebug() << "[Playback] WAIT until you see 'downloaded' and 'open OK'";

    cancelDownload(cameraId);
    stopWorkerAsync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue)
        return;
    QMetaObject::invokeMethod(queue, "resetReceived");

    const qint64 posMs = startSec * 1000;
    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);

    QProcess* proc = new QProcess(this);
    proc->setProgram(QStringLiteral("curl"));
    proc->setArguments({
        QStringLiteral("-fsSL"),
        QStringLiteral("--max-time"), QStringLiteral("120"),
        QStringLiteral("--connect-timeout"), QStringLiteral("15"),
        QStringLiteral("-o"), path,
        url
    });

    m_curlProcs.insert(cameraId, proc);
    m_curlPaths.insert(cameraId, path);

    // File-size progress every 2 seconds
    QTimer* prog = new QTimer(this);
    prog->setInterval(2000);
    connect(prog, &QTimer::timeout, this, [this, cameraId, path, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        QFileInfo fi(path);
        if (fi.exists())
            qDebug() << "[Playback] progress" << cameraId << (fi.size() / 1024) << "KB";
        else
            qDebug() << "[Playback] progress" << cameraId << "0 KB (waiting for first bytes)";
    });
    m_progressTimers.insert(cameraId, prog);
    prog->start();

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, cameraId, proc, path, posMs, gen](int code, QProcess::ExitStatus st) {
        if (m_progressTimers.contains(cameraId)) {
            QTimer* t = m_progressTimers.take(cameraId);
            if (t) { t->stop(); t->deleteLater(); }
        }

        if (m_curlProcs.value(cameraId) == proc)
            m_curlProcs.remove(cameraId);

        if (m_seekGen.value(cameraId, 0) != gen) {
            if (QFile::exists(path))
                QFile::remove(path);
            m_curlPaths.remove(cameraId);
            proc->deleteLater();
            return;
        }

        if (st != QProcess::NormalExit || code != 0) {
            qWarning() << "[Playback] curl failed" << cameraId
                       << "code" << code
                       << proc->errorString()
                       << QString::fromLocal8Bit(proc->readAllStandardError());
            if (QFile::exists(path))
                QFile::remove(path);
            m_curlPaths.remove(cameraId);
            proc->deleteLater();
            return;
        }

        QFileInfo fi(path);
        const qint64 sz = fi.size();
        if (sz < 1024) {
            qWarning() << "[Playback] clip too small" << cameraId << sz;
            if (QFile::exists(path))
                QFile::remove(path);
            m_curlPaths.remove(cameraId);
            proc->deleteLater();
            return;
        }

        qDebug() << "[Playback] downloaded" << sz << "bytes ->" << path;
        // Keep path until worker finishes — remove on next cancel/stop
        startLocalFile(cameraId, path, posMs, gen);
        proc->deleteLater();
    });

    connect(proc, &QProcess::errorOccurred, this,
            [this, cameraId, proc, path, gen](QProcess::ProcessError) {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        qWarning() << "[Playback] curl process error" << cameraId << proc->errorString();
    });

    proc->start();
    if (!proc->waitForStarted(3000)) {
        qWarning() << "[Playback] curl failed to start — is curl.exe on PATH?";
        cancelDownload(cameraId);
    }
}

void FrigatePlayback::startLocalFile(const QString& cameraId,
                                     const QString& path,
                                     qint64 posMs,
                                     int gen)
{
    if (m_seekGen.value(cameraId, 0) != gen)
        return;

    stopWorkerAsync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue)
        return;

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(path);
    worker->setFrameQueue(queue);
    worker->setHighQuality(true);

    QThread* thread = new QThread();

    connect(worker, &FFmpegWorker::openInputOk, this, [this, cameraId, gen]() {
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
    }, Qt::QueuedConnection);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    {
        QMutexLocker lock(&m_mutex);
        m_playbackWorkers.insert(cameraId, worker);
        m_playbackThreads.insert(cameraId, thread);
    }

    worker->moveToThread(thread);
    thread->start();

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

    if (m_curlProcs.contains(cameraId)) {
        qDebug() << "[Playback] switchToLive ignored (download active)" << cameraId;
        return;
    }

    m_seekGen[cameraId] = m_seekGen.value(cameraId, 0) + 1;
    cancelDownload(cameraId);
    stopWorkerAsync(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
    qDebug() << "[Playback] live mode" << cameraId;
}