#ifndef FRIGATETIMELINE_H
#define FRIGATETIMELINE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QHash>
#include <QNetworkAccessManager>

class FrigateTimeline : public QObject
{
    Q_OBJECT

public:
    explicit FrigateTimeline(QObject* parent = nullptr);

    //
    // Server configuration
    //
    void setServer(const QString& server);
    void setModuleServer(const QString& server);

    //
    // Timeline API
    //
    void loadRecordings(const QString& cameraId);
    void loadEvents(const QString& cameraId);

    // Optional: playback window (for scrubbing)
    void loadPlaybackWindow(const QString& cameraId, qint64 timestampMs);

    //
    // Accessors
    //
    QVariantList getRecordings(const QString& cameraId) const;
    QVariantList getEvents(const QString& cameraId) const;

    //
    // Cleanup
    //
    void clearCamera(const QString& cameraId);

signals:
    void recordingsLoaded(const QString& cameraId, const QVariantList& segments);
    void eventsLoaded(const QString& cameraId, const QVariantList& events);

private:
    QString m_server;
    QString m_moduleServer;

    QNetworkAccessManager* m_net;

    QHash<QString, QVariantList> m_recordingsByCamera;
    QHash<QString, QVariantList> m_eventsByCamera;
};

#endif
