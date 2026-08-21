#ifndef FRIGATETIMELINE_H
#define FRIGATETIMELINE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QHash>
#include <QNetworkAccessManager>

class FrigateTimeline : public QObject
{
    Q_OBJECT

public:
    explicit FrigateTimeline(QObject* parent = nullptr);

    void setServer(const QString& server);
    void setModuleServer(const QString& server);

    // Default window: last 24 hours
    void loadRecordings(const QString& cameraId);
    void loadEvents(const QString& cameraId);
    void loadMotionActivity(const QString& cameraId);

    // Explicit range (Unix seconds) — used by calendar day jump
    void loadRecordingsRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec);
    void loadEventsRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec);
    void loadMotionActivityRange(const QString& cameraId, qint64 afterSec, qint64 beforeSec);

    // Lightweight list of days with recordings for the calendar
    void loadRecordingDays(const QString& cameraId);

    void loadPlaybackWindow(const QString& cameraId, qint64 timestampMs);

    QVariantList getRecordings(const QString& cameraId) const;
    QVariantList getEvents(const QString& cameraId) const;
    QVariantList getMotionActivity(const QString& cameraId) const;
    QStringList getRecordingDays(const QString& cameraId) const;

    void clearCamera(const QString& cameraId);

signals:
    void recordingsLoaded(const QString& cameraId, const QVariantList& segments);
    void eventsLoaded(const QString& cameraId, const QVariantList& events);
    void motionActivityLoaded(const QString& cameraId, const QVariantList& points);
    void recordingDaysLoaded(const QString& cameraId, const QStringList& days);

private:
    QString m_server;
    QString m_moduleServer;
    QNetworkAccessManager* m_net;

    QHash<QString, QVariantList> m_recordingsByCamera;
    QHash<QString, QVariantList> m_eventsByCamera;
    QHash<QString, QVariantList> m_motionByCamera;
    QHash<QString, QStringList>  m_recordingDaysByCamera;
};

#endif