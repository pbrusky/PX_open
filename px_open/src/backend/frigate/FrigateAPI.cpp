#include "FrigateAPI.h"

#include "FrigateCameraManager.h"
#include "FrigateStreamManager.h"
#include "FrigateTimeline.h"
#include "FrigatePlayback.h"
#include "FrigateOnvif.h"
#include <QProcess>
#include <QDebug>

FrigateAPI::FrigateAPI(QObject* parent)
    : QObject(parent)
{
    m_cameraManager = new FrigateCameraManager(this);
    m_streamManager = new FrigateStreamManager(this);
    m_timeline      = new FrigateTimeline(this);
    m_playback      = new FrigatePlayback(this);
    m_onvif         = new FrigateOnvif(this);

    //
    // CAMERA SIGNALS
    //
    connect(m_cameraManager, &FrigateCameraManager::camerasLoaded,
            this, &FrigateAPI::camerasLoaded);

    connect(m_cameraManager, &FrigateCameraManager::cameraOnline,
            this, &FrigateAPI::cameraOnline);

    connect(m_cameraManager, &FrigateCameraManager::cameraOffline,
            this, &FrigateAPI::cameraOffline);

    connect(m_cameraManager, &FrigateCameraManager::cameraAddResult,
            this, &FrigateAPI::cameraAddResult);

    connect(m_cameraManager, &FrigateCameraManager::cameraEditResult,
            this, &FrigateAPI::cameraEditResult);

    connect(m_cameraManager, &FrigateCameraManager::cameraRemoveResult,
            this, &FrigateAPI::cameraRemoveResult);

    //
    // ONVIF SIGNALS
    //
    connect(m_onvif, &FrigateOnvif::onvifDevicesDiscovered,
            this, &FrigateAPI::onvifDevicesDiscovered);

    connect(m_onvif, &FrigateOnvif::onvifProgress,
            this, &FrigateAPI::onvifProgress);

    connect(m_onvif, &FrigateOnvif::rtspResolved,
            this, &FrigateAPI::rtspResolved);

    connect(m_onvif, &FrigateOnvif::onvifError,
            this, &FrigateAPI::onvifError);

    //
    // TIMELINE SIGNALS
    //
    connect(m_timeline, &FrigateTimeline::recordingsLoaded,
            this, &FrigateAPI::recordingsLoaded);

    connect(m_timeline, &FrigateTimeline::eventsLoaded,
            this, &FrigateAPI::eventsLoaded);

    //
    // PLAYBACK SIGNALS
    //
    connect(m_playback, &FrigatePlayback::playbackPositionChanged,
            this, &FrigateAPI::playbackPositionChanged);

    //
    // STREAM ONLINE/OFFLINE
    //
    connect(m_streamManager, &FrigateStreamManager::cameraOnline,
            this, &FrigateAPI::cameraOnline);

    connect(m_streamManager, &FrigateStreamManager::cameraOffline,
            this, &FrigateAPI::cameraOffline);

    //
    // MODULE INFORMATION SIGNALS
    //
    connect(m_cameraManager, &FrigateCameraManager::moduleInformationReceived,
            this, &FrigateAPI::moduleInformationReceived);
}

//
// SERVER SETTERS
//
void FrigateAPI::setServer(QString server)
{
    m_server = server;
    emit serverChanged();

    m_cameraManager->setServer(server);
    m_timeline->setServer(server);
    m_streamManager->setServer(server);
    m_playback->setServer(server);
}

void FrigateAPI::setModuleServer(QString server)
{
    m_moduleServer = server;
    emit moduleServerChanged();

    m_cameraManager->setModuleServer(server);
    m_onvif->setModuleServer(server);
    m_timeline->setModuleServer(server);
}

void FrigateAPI::setServerIp(QString ip)
{
    m_serverIp = ip;
    emit serverIpChanged();

    m_streamManager->setServerIp(ip);
    m_playback->setServerIp(ip);
}

//
// CAMERA API
//
void FrigateAPI::loadCameras()
{
    m_cameraManager->loadCameras();
}

void FrigateAPI::addCamera(QString id, QString url, bool record)
{
    m_cameraManager->addCamera(id, url, record);
}

void FrigateAPI::editCamera(QString id, QString url)
{
    m_cameraManager->editCamera(id, url);
}

void FrigateAPI::removeCamera(QString id)
{
    m_cameraManager->removeCamera(id);
}

bool FrigateAPI::isCameraOnline(const QString& id) const
{
    return m_cameraManager->isCameraOnline(id);
}

QVariantList FrigateAPI::getCameraList() const
{
    return m_cameraManager->getCameraList();
}

//
// ONVIF API
//
void FrigateAPI::discoverOnvif(const QString& username, const QString& password)
{
    m_onvif->discoverOnvif(username, password);
}

QVariantList FrigateAPI::getOnvifProgress()
{
    return m_onvif->getOnvifProgress();
}

void FrigateAPI::getRtsp(const QString& ip, const QString& username, const QString& password)
{
    m_onvif->getRtsp(ip, username, password);
}

//
// STREAMING API
//
QObject* FrigateAPI::getQueue(const QString& cameraName)
{
    return m_streamManager->getQueue(cameraName);
}

QObject* FrigateAPI::getPlaybackQueue(const QString& cameraName)
{
    return m_playback->getPlaybackQueue(cameraName);
}

void FrigateAPI::stopStream(const QString& cameraName)
{
    m_streamManager->stopStream(cameraName);
}

void FrigateAPI::stopAllStreams()
{
    m_streamManager->stopAllStreams();
}

//
// ⭐ NEW — expose FFmpegWorker to QML
//
QObject* FrigateAPI::getWorker(const QString& cameraName)
{
    return m_streamManager->getWorker(cameraName);
}

//
// TIMELINE API
//
void FrigateAPI::loadRecordings(const QString& cameraId)
{
    m_timeline->loadRecordings(cameraId);
}

void FrigateAPI::loadEvents(const QString& cameraId)
{
    m_timeline->loadEvents(cameraId);
}

QVariantList FrigateAPI::getRecordingsForCamera(const QString& cameraId)
{
    return m_timeline->getRecordings(cameraId);
}

QVariantList FrigateAPI::getEventsForCamera(const QString& cameraId)
{
    return m_timeline->getEvents(cameraId);
}

//
// PLAYBACK API
//
void FrigateAPI::seek(const QString& cameraId, qint64 timestampMs)
{
    m_playback->seek(cameraId, timestampMs);
}

void FrigateAPI::startPlayback(const QString& cameraId, qint64 timestampMs)
{
    m_playback->startPlayback(cameraId, timestampMs);
}

qint64 FrigateAPI::currentPosition(const QString& cameraId)
{
    return m_playback->currentPosition(cameraId);
}

void FrigateAPI::switchToLive(const QString& cameraId)
{
    m_playback->switchToLive(cameraId);
}

//
// MODULE INFORMATION
//
void FrigateAPI::loadModuleInformation()
{
    m_cameraManager->loadModuleInformation();
}

//
// RTSP TESTING
//
void FrigateAPI::testRtsp(const QString& url)
{
    qDebug() << "FrigateAPI::testRtsp REAL TEST for URL:" << url;

    QString program = "ffmpeg";

    QStringList args;
    args << "-rtsp_transport" << "tcp"
         << "-i" << url
         << "-t" << "1"
         << "-f" << "null"
         << "-";

    QProcess* ff = new QProcess(this);

    connect(ff, &QProcess::finished, this, [this, ff](int exitCode, QProcess::ExitStatus status) {
        QByteArray err = ff->readAllStandardError();
        QString errorText = QString(err);

        QString shortError;

        if (errorText.contains("401") || errorText.contains("Unauthorized"))
            shortError = "Invalid username or password";
        else if (errorText.contains("404") || errorText.contains("Not Found"))
            shortError = "Stream not found (wrong channel)";
        else if (errorText.contains("Connection refused"))
            shortError = "Camera refused connection";
        else if (errorText.contains("timed out"))
            shortError = "Connection timed out";
        else if (errorText.contains("Invalid data found"))
            shortError = "Camera returned invalid stream data";
        else if (errorText.contains("No route"))
            shortError = "Camera unreachable";
        else
            shortError = "Unknown RTSP error";

        if (status == QProcess::NormalExit && exitCode == 0) {
            emit rtspTestResult(true, "RTSP Test Passed");
        } else {
            emit rtspTestResult(false, "RTSP Test Failed: " + shortError);
        }

        ff->deleteLater();
    });

    ff->start(program, args);
}
