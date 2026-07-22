#ifndef FRIGATEONVIF_H
#define FRIGATEONVIF_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QNetworkAccessManager>

class FrigateOnvif : public QObject
{
    Q_OBJECT

public:
    explicit FrigateOnvif(QObject* parent = nullptr);

    void setModuleServer(const QString& server);

    void discoverOnvif(const QString& username, const QString& password);
    QVariantList getOnvifProgress() const;

    void getRtsp(const QString& ip, const QString& username, const QString& password);

signals:
    void onvifDevicesDiscovered(QVariantList devices);
    void onvifProgress(QVariantList devices);
    void rtspResolved(QString rtsp);

    // ⭐ REQUIRED BY FrigateAPI.cpp
    void onvifError(QString message);

private:
    QString m_moduleServer;
    QNetworkAccessManager* m_net;

    QVariantList m_onvifProgress;
};

#endif
