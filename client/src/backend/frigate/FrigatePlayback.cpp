#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>
#include <QNetworkRequest>
#include <QUrl>
#include <QDir>
#include <QFile>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
{
}

FrigatePlayback::~FrigatePlayback()
{
    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys) {
        cancelDownload(id);
        stopWorkerAsync(id);
    }
    const QStringList dlKeys = m_replies.keys();
    for (const QString& id : dlKeys)
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
    if (m_replies.contains(cameraId)) {
        QNetworkReply* r = m_replies.take(cameraId);
        if (r) {
            QObject::disconnect(r, nullptr, this, nullptr);
            r->abort();
            r->deleteLater();
        }
    }
    if (m_tempFiles.contains(cameraId)) {
        QTemporaryFile* t = m_tempFiles.take(cameraId);
        if (t) {
            t->close();
            t->deleteLater();
        }
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

    const qint64 nowSec = QDateTime::currentSecsSinceEpoch();
    qint64 endSec = startSec + 6;
    if (endSec > nowSec)
        endSec = nowSec;
    if (endSec <= startSec)
        endSec = startSec + 4;

    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    qDebug() << "[Playback] download" << cameraId << startSec << "->" << endSec << url;
    qDebug() << "[Playback] WAIT — do not press Exit for ~15 seconds";

    cancelDownload(cameraId);
    stopWorkerAsync(cameraId);

    FrameQueue* queue = qobject_cast<FrameQueue*>(getPlaybackQueue(cameraId));
    if (!queue)
        return;
    QMetaObject::invokeMethod(queue, "resetReceived");

    QTemporaryFile* tmp = new QTemporaryFile(
        QDir::temp().filePath(QStringLiteral("px_clip_%1_XXXXXX.mp4").arg(cameraId)),
        this);
    tmp->setAutoRemove(true);
    if (!tmp->open()) {
        qWarning() << "[Playback] temp file failed" << cameraId;
        tmp->deleteLater();
        return;
    }
    m_tempFiles.insert(cameraId, tmp);

    QNetworkRequest req{QUrl(url)};
    req.setRawHeader("User-Agent", "Mozilla/5.0 PX-Open");
    req.setRawHeader("Accept", "*/*");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    req.setTransferTimeout(90000);

    QNetworkReply* reply = m_nam->get(req);
    m_replies.insert(cameraId, reply);

    const qint64 posMs = startSec * 1000;
    m_playbackPositionByCamera[cameraId] = posMs;
    emit playbackPositionChanged(cameraId, posMs);

    connect(reply, &QNetworkReply::downloadProgress, this,
            [this, cameraId, gen](qint64 rec, qint64 total) {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        if (rec > 0 && (rec % (2 * 1024 * 1024) < 65536))
            qDebug() << "[Playback] progress" << cameraId << rec << "/" << total;
    });

    connect(reply, &QNetworkReply::readyRead, this,
            [this, cameraId, reply, tmp, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        if (m_replies.value(cameraId) != reply || !tmp)
            return;
        const QByteArray chunk = reply->readAll();
        if (!chunk.isEmpty())
            tmp->write(chunk);
    });

    connect(reply, &QNetworkReply::finished, this,
            [this, cameraId, reply, tmp, posMs, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen) {
            reply->deleteLater();
            if (m_replies.value(cameraId) == reply)
                m_replies.remove(cameraId);
            return;
        }

        if (m_replies.value(cameraId) == reply)
            m_replies.remove(cameraId);

        if (tmp && reply->bytesAvailable() > 0)
            tmp->write(reply->readAll());

        if (reply->error() != QNetworkReply::NoError) {
            if (reply->error() != QNetworkReply::OperationCanceledError)
                qWarning() << "[Playback] download failed" << cameraId
                           << reply->errorString();
            reply->deleteLater();
            if (m_tempFiles.value(cameraId) == tmp) {
                m_tempFiles.remove(cameraId);
                tmp->close();
                tmp->deleteLater();
            }
            return;
        }

        reply->deleteLater();

        if (!tmp) {
            qWarning() << "[Playback] no temp file" << cameraId;
            return;
        }

        tmp->flush();
        tmp->close();

        const qint64 sz = tmp->size();
        if (sz < 1024) {
            qWarning() << "[Playback] clip too small" << cameraId << sz;
            if (m_tempFiles.value(cameraId) == tmp) {
                m_tempFiles.remove(cameraId);
                tmp->deleteLater();
            }
            return;
        }

        qDebug() << "[Playback] downloaded" << sz << "bytes ->" << tmp->fileName();
        startLocalFile(cameraId, tmp->fileName(), posMs, gen);
    });
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

    if (m_replies.contains(cameraId)) {
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