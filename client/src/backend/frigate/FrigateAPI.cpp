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

    connect(m_cameraManager, &FrigateCameraManager::camerasLoaded,
            this, &FrigateAPI::camerasLoaded);
    connect(m_cameraManager, &FrigateCameraManager::camerasLoaded,
            this, [this](const QVariantList& cameras) {
        if (!m_streamManager)
            return;
        m_streamManager->clearCameraDirectMainUrls();
        for (const QVariant& v : cameras) {
            const QVariantMap m = v.toMap();
            const QString id = m.value(QStringLiteral("id")).toString();
            if (id.isEmpty())
                continue;
            QString mainUrl = m.value(QStringLiteral("mainUrl")).toString();
            if (mainUrl.isEmpty())
                mainUrl = m.value(QStringLiteral("rtsp")).toString();
            const QString user = m.value(QStringLiteral("username")).toString();
            const QString pass = m.value(QStringLiteral("password")).toString();
            m_streamManager->setCameraDirectMainUrl(id, mainUrl, user, pass);
        }
    });
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
    connect(m_cameraManager, &FrigateCameraManager::frigateConfigLoaded,
            this, &FrigateAPI::frigateConfigLoaded);
    connect(m_cameraManager, &FrigateCameraManager::frigateConfigSaved,
            this, &FrigateAPI::frigateConfigSaved);
    connect(m_cameraManager, &FrigateCameraManager::go2rtcConfigLoaded,
            this, &FrigateAPI::go2rtcConfigLoaded);
    connect(m_cameraManager, &FrigateCameraManager::go2rtcConfigSaved,
            this, &FrigateAPI::go2rtcConfigSaved);

    connect(m_onvif, &FrigateOnvif::onvifDevicesDiscovered,
            this, &FrigateAPI::onvifDevicesDiscovered);
    connect(m_onvif, &FrigateOnvif::onvifProgress,
            this, &FrigateAPI::onvifProgress);
    connect(m_onvif, &FrigateOnvif::rtspResolved,
            this, &FrigateAPI::rtspResolved);
    connect(m_onvif, &FrigateOnvif::onvifError,
            this, &FrigateAPI::onvifError);

    connect(m_timeline, &FrigateTimeline::recordingsLoaded,
            this, &FrigateAPI::recordingsLoaded);
    connect(m_timeline, &FrigateTimeline::eventsLoaded,
            this, &FrigateAPI::eventsLoaded);
    connect(m_timeline, &FrigateTimeline::motionActivityLoaded,
            this, &FrigateAPI::motionActivityLoaded);
    connect(m_timeline, &FrigateTimeline::recordingDaysLoaded,
            this, &FrigateAPI::recordingDaysLoaded);

    connect(m_playback, &FrigatePlayback::playbackPositionChanged,
            this, &FrigateAPI::playbackPositionChanged);
    connect(m_playback, &FrigatePlayback::playbackStarted,
            this, &FrigateAPI::playbackStarted);
    connect(m_playback, &FrigatePlayback::playbackStopped,
            this, &FrigateAPI::playbackStopped);

    connect(m_streamManager, &FrigateStreamManager::cameraOnline,
            this, [this](const QString& id) {
        if (m_cameraManager)
            m_cameraManager->setCameraOnline(id, true);
    });
    connect(m_streamManager, &FrigateStreamManager::cameraOffline,
            this, [this](const QString& id) {
        if (m_cameraManager)
            m_cameraManager->setCameraOnline(id, false);
    });
    connect(m_streamManager, &FrigateStreamManager::cameraStatsChanged,
            this, &FrigateAPI::cameraStatsChanged);
    connect(m_streamManager, &FrigateStreamManager::fullscreenFrameReady,
            this, &FrigateAPI::fullscreenFrameReady);
    connect(m_streamManager, &FrigateStreamManager::fullscreenUsingSub,
            this, &FrigateAPI::fullscreenUsingSub);
    connect(m_streamManager, &FrigateStreamManager::fullscreenMainStatus,
            this, &FrigateAPI::fullscreenMainStatus);

    connect(m_cameraManager, &FrigateCameraManager::moduleInformationReceived,
            this, &FrigateAPI::moduleInformationReceived);
}

void FrigateAPI::setServer(QString server)
{
    if (m_server == server)
        return;
    m_server = server;
    m_cameraManager->setServer(server);
    m_streamManager->setServer(server);
    m_timeline->setServer(server);
    m_playback->setServer(server);
    emit serverChanged();
}

void FrigateAPI::setModuleServer(QString server)
{
    if (m_moduleServer == server)
        return;
    m_moduleServer = server;
    m_cameraManager->setModuleServer(server);
    m_timeline->setModuleServer(server);
    m_playback->setModuleServer(server);
    m_onvif->setModuleServer(server);
    emit moduleServerChanged();
}

void FrigateAPI::setServerIp(QString ip)
{
    if (m_serverIp == ip)
        return;
    m_serverIp = ip;
    if (m_streamManager) {
        m_streamManager->stopAllStreams();
        m_streamManager->setServerIp(ip);
    }
    if (m_cameraManager)
        m_cameraManager->clearCameraOnlineState();
    if (m_playback)
        m_playback->setServerIp(ip);
    emit serverIpChanged();
}

void FrigateAPI::loadCameras()
{
    m_cameraManager->loadCameras();
}

void FrigateAPI::addCamera(QString id, QString mainUrl, QString subUrl, bool record)
{
    m_cameraManager->addCamera(id, mainUrl, subUrl, record);
}

void FrigateAPI::editCamera(QString id, QString url)
{
    m_cameraManager->editCamera(id, url);
}

void FrigateAPI::removeCamera(QString id)
{
    m_cameraManager->removeCamera(id);
}

void FrigateAPI::loadFrigateConfig()
{
    m_cameraManager->loadFrigateConfig();
}

void FrigateAPI::saveFrigateConfig(const QString& content, bool restart)
{
    m_cameraManager->saveFrigateConfig(content, restart);
}

void FrigateAPI::loadGo2rtcConfig()
{
    m_cameraManager->loadGo2rtcConfig();
}

void FrigateAPI::saveGo2rtcConfig(const QString& content, bool restart)
{
    m_cameraManager->saveGo2rtcConfig(content, restart);
}

bool FrigateAPI::isCameraOnline(const QString& id) const
{
    return m_cameraManager->isCameraOnline(id);
}

QVariantList FrigateAPI::getCameraList() const
{
    return m_cameraManager->getCameraList();
}

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

QObject* FrigateAPI::getQueue(const QString& cameraName)
{
    return m_streamManager->getQueue(cameraName);
}

QObject* FrigateAPI::getFullscreenQueue(const QString& cameraName)
{
    return m_streamManager->getFullscreenQueue(cameraName);
}

QObject* FrigateAPI::getPlaybackQueue(const QString& cameraName)
{
    return m_playback->getPlaybackQueue(cameraName);
}

void FrigateAPI::stopStream(const QString& cameraName)
{
    m_streamManager->stopStream(cameraName);
}

void FrigateAPI::stopFullscreenStream(const QString& cameraName)
{
    m_streamManager->stopFullscreenStream(cameraName);
}

void FrigateAPI::stopAllFullscreenStreams()
{
    m_streamManager->stopAllFullscreenStreams();
}

void FrigateAPI::stopAllStreams()
{
    m_streamManager->stopAllStreams();
}

void FrigateAPI::stopAllStreamsAndWait(int timeoutMs)
{
    m_streamManager->stopAllStreamsAndWait(timeoutMs);
}

QObject* FrigateAPI::getWorker(const QString& cameraName)
{
    return m_streamManager->getWorker(cameraName);
}

void FrigateAPI::loadRecordings(const QString& cameraId)
{
    m_timeline->loadRecordings(cameraId);
}

void FrigateAPI::loadEvents(const QString& cameraId)
{
    m_timeline->loadEvents(cameraId);
}

void FrigateAPI::loadMotionActivity(const QString& cameraId)
{
    m_timeline->loadMotionActivity(cameraId);
}

void FrigateAPI::loadRecordingsRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec)
{
    m_timeline->loadRecordingsRange(cameraId, afterSec, beforeSec);
}

void FrigateAPI::loadEventsRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec)
{
    m_timeline->loadEventsRange(cameraId, afterSec, beforeSec);
}

void FrigateAPI::loadMotionActivityRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec)
{
    m_timeline->loadMotionActivityRange(cameraId, afterSec, beforeSec);
}

void FrigateAPI::loadRecordingDays(const QString& cameraId)
{
    m_timeline->loadRecordingDays(cameraId);
}

QStringList FrigateAPI::getRecordingDaysForCamera(const QString& cameraId)
{
    return m_timeline->getRecordingDays(cameraId);
}

QVariantList FrigateAPI::getRecordingsForCamera(const QString& cameraId)
{
    return m_timeline->getRecordings(cameraId);
}

QVariantList FrigateAPI::getEventsForCamera(const QString& cameraId)
{
    return m_timeline->getEvents(cameraId);
}

QVariantList FrigateAPI::getMotionActivityForCamera(const QString& cameraId)
{
    return m_timeline->getMotionActivity(cameraId);
}

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

void FrigateAPI::stopPlayback(const QString& cameraId)
{
    m_playback->stopPlayback(cameraId);
}

void FrigateAPI::loadModuleInformation()
{
    m_cameraManager->loadModuleInformation();
}

void FrigateAPI::testRtsp(const QString& url)
{
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

        if (status == QProcess::NormalExit && exitCode == 0)
            emit rtspTestResult(true, "RTSP Test Passed");
        else
            emit rtspTestResult(false, "RTSP Test Failed: " + shortError);

        ff->deleteLater();
    });
    ff->start(program, args);
}

QString FrigateAPI::cameraResolution(const QString& cameraName) const
{
    return m_streamManager ? m_streamManager->cameraResolution(cameraName) : QString();
}

double FrigateAPI::cameraFps(const QString& cameraName) const
{
    return m_streamManager ? m_streamManager->cameraFps(cameraName) : 0.0;
}

int FrigateAPI::cameraBitrateKbps(const QString& cameraName) const
{
    return m_streamManager ? m_streamManager->cameraBitrateKbps(cameraName) : 0;
}

QString FrigateAPI::cameraCodec(const QString& cameraName) const
{
    return m_streamManager ? m_streamManager->cameraCodec(cameraName) : QString();
}

bool FrigateAPI::isFullscreenTrueMain(const QString& cameraName) const
{
    return m_streamManager ? m_streamManager->isFullscreenTrueMain(cameraName) : false;
}