#include "FrigatePlayback.h"
#include "FrameQueue.h"
#include "FFmpegWorker.h"

#include <QThread>
#include <QDateTime>
#include <QDebug>
#include <QMutexLocker>
#include <QMetaObject>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>

FrigatePlayback::FrigatePlayback(QObject* parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
{
}

FrigatePlayback::~FrigatePlayback()
{
    for (auto it = m_seekGen.begin(); it != m_seekGen.end(); ++it)
        it.value() = it.value() + 1;

    const QStringList keys = m_playbackWorkers.keys();
    for (const QString& id : keys)
        stopWorkerAsync(id);

    const QStringList dlKeys = m_downloadReplies.keys();
    for (const QString& id : dlKeys)
        cancelDownload(id);

    for (auto it = m_tempFiles.begin(); it != m_tempFiles.end(); ++it) {
        if (!it.value().isEmpty())
            QFile::remove(it.value());
    }
    m_tempFiles.clear();
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

void FrigatePlayback::cancelDownload(const QString& cameraId)
{
    QNetworkReply* reply = m_downloadReplies.take(cameraId);
    if (reply) {
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    QFile* file = m_downloadFiles.take(cameraId);
    if (file) {
        file->close();
        delete file;
    }
}

void FrigatePlayback::cleanupTempFile(const QString& cameraId)
{
    const QString path = m_tempFiles.take(cameraId);
    if (!path.isEmpty())
        QFile::remove(path);
}

void FrigatePlayback::stopWorkerAsync(const QString& cameraId)
{
    cancelDownload(cameraId);

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
        QObject::connect(worker, &FFmpegWorker::finished, thread, &QThread::quit, Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished, worker, &QObject::deleteLater, Qt::UniqueConnection);
        QObject::connect(thread, &QThread::finished, thread, &QObject::deleteLater, Qt::UniqueConnection);
        return;
    }
    if (worker) {
        QObject::connect(worker, &FFmpegWorker::finished, worker, &QObject::deleteLater, Qt::UniqueConnection);
        return;
    }
    if (thread) {
        QObject::connect(thread, &QThread::finished, thread, &QObject::deleteLater, Qt::UniqueConnection);
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
    cleanupTempFile(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}

void FrigatePlayback::seek(const QString& cameraId, qint64 timestampMs)
{
    startPlayback(cameraId, timestampMs);
}

void FrigatePlayback::startUrlWorker(const QString& cameraId, int gen, const QString& url)
{
    if (m_seekGen.value(cameraId, 0) != gen)
        return;

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
        if (m_playbackWorkers.contains(cameraId))
            return;
    }
    if (!queue)
        return;

    qInfo() << "[Playback] ffmpeg open" << cameraId << url;

    FFmpegWorker* worker = new FFmpegWorker(nullptr);
    worker->setUrl(url);
    worker->setFrameQueue(queue);
    worker->setHighQuality(false);

    QThread* thread = new QThread();

    connect(worker, &FFmpegWorker::openInputOk, this,
            [this, cameraId, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        qInfo() << "[Playback] open ok" << cameraId;
        emit cameraOnline(cameraId);
        emit playbackStarted(cameraId);
    }, Qt::QueuedConnection);

    // Direct HTTP failed (e.g. -138) → fall back to Qt download then local open
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

        if (url.startsWith(QStringLiteral("http"), Qt::CaseInsensitive)) {
            qInfo() << "[Playback] falling back to download" << cameraId;
            downloadThenPlay(cameraId, gen, url);
            return;
        }

        cleanupTempFile(cameraId);
        emit cameraOffline(cameraId);
        emit playbackStopped(cameraId);
    }, Qt::QueuedConnection);

    connect(worker, &FFmpegWorker::streamStopped, this,
            [this, cameraId, gen]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        {
            QMutexLocker lock(&m_mutex);
            m_playbackWorkers.remove(cameraId);
            m_playbackThreads.remove(cameraId);
        }
        cleanupTempFile(cameraId);
        emit playbackStopped(cameraId);
    }, Qt::QueuedConnection);

    connect(thread, &QThread::started, worker, &FFmpegWorker::startDecoding);
    connect(worker, &FFmpegWorker::finished, thread, &QThread::quit);
    connect(thread, &QThread::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
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
}

void FrigatePlayback::startLocalWorker(const QString& cameraId, int gen, const QString& localPath)
{
    startUrlWorker(cameraId, gen, localPath);
}

void FrigatePlayback::downloadThenPlay(const QString& cameraId, int gen, const QString& remoteUrl)
{
    if (m_seekGen.value(cameraId, 0) != gen)
        return;

    QDir tmpDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation));
    const QString localPath = tmpDir.filePath(
        QStringLiteral("px_playback_%1_%2.mp4").arg(cameraId).arg(gen));

    cleanupTempFile(cameraId);

    QFile* outFile = new QFile(localPath);
    if (!outFile->open(QIODevice::WriteOnly)) {
        qWarning() << "[Playback] cannot write" << localPath;
        delete outFile;
        emit cameraOffline(cameraId);
        emit playbackStopped(cameraId);
        return;
    }
    m_downloadFiles.insert(cameraId, outFile);
    m_tempFiles.insert(cameraId, localPath);

    QNetworkRequest req;
    req.setUrl(QUrl(remoteUrl));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PX_Open/1.0"));
    req.setTransferTimeout(180000);

    QNetworkReply* reply = m_net->get(req);
    m_downloadReplies.insert(cameraId, reply);

    connect(reply, &QNetworkReply::readyRead, this, [this, cameraId, gen, reply]() {
        if (m_seekGen.value(cameraId, 0) != gen)
            return;
        if (QFile* f = m_downloadFiles.value(cameraId)) {
            const QByteArray chunk = reply->readAll();
            if (!chunk.isEmpty())
                f->write(chunk);
        }
    });

    connect(reply, &QNetworkReply::finished, this,
            [this, cameraId, gen, localPath, remoteUrl, reply]() {
        m_downloadReplies.remove(cameraId);
        QFile* file = m_downloadFiles.take(cameraId);
        if (file) {
            if (reply->bytesAvailable() > 0)
                file->write(reply->readAll());
            file->flush();
            file->close();
            delete file;
        }
        if (m_seekGen.value(cameraId, 0) != gen) {
            reply->deleteLater();
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        reply->deleteLater();
        const qint64 size = QFileInfo(localPath).size();
        if (err != QNetworkReply::NoError || status >= 400 || size < 1024) {
            qWarning() << "[Playback] download failed" << cameraId << status << err << size;
            cleanupTempFile(cameraId);
            emit cameraOffline(cameraId);
            emit playbackStopped(cameraId);
            return;
        }
        qInfo() << "[Playback] downloaded" << cameraId << size << "bytes";
        startLocalWorker(cameraId, gen, localPath);
    });
}

void FrigatePlayback::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    if (cameraId.trimmed().isEmpty() || m_server.isEmpty()) {
        qWarning() << "[Playback] missing camera or server";
        return;
    }

    const qint64 wall = QDateTime::currentMSecsSinceEpoch();
    if (m_lastSeekMs.contains(cameraId) && (wall - m_lastSeekMs.value(cameraId) < 800))
        return;
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

    qint64 endSec = startSec + 30;
    if (endSec > nowSec - 5)
        endSec = nowSec - 5;
    if (endSec <= startSec)
        endSec = startSec + 10;

    // Same URL the app used when playback "used to work"
    const QString url = QStringLiteral("%1/api/%2/start/%3/end/%4/clip.mp4")
                            .arg(m_server, cameraId)
                            .arg(startSec)
                            .arg(endSec);

    qInfo() << "[Playback] starting" << cameraId << url;

    stopWorkerAsync(cameraId);
    cleanupTempFile(cameraId);

    {
        QMutexLocker lock(&m_mutex);
        if (!m_playbackQueues.contains(cameraId)) {
            FrameQueue* q = new FrameQueue(this);
            q->setMaxSize(2);
            m_playbackQueues.insert(cameraId, q);
        }
        if (FrameQueue* queue = m_playbackQueues.value(cameraId))
            queue->resetReceived();
    }

    m_playbackPositionByCamera[cameraId] = startSec * 1000;
    emit playbackPositionChanged(cameraId, startSec * 1000);

    startUrlWorker(cameraId, gen, url);
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
    cleanupTempFile(cameraId);
    m_playbackPositionByCamera[cameraId] = 0;
    m_lastSeekMs.remove(cameraId);
    emit playbackStopped(cameraId);
    emit playbackPositionChanged(cameraId, 0);
}