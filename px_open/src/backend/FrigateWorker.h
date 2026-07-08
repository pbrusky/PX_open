#ifndef FRIGATEWORKER_H
#define FRIGATEWORKER_H

#include <QObject>
#include <QNetworkAccessManager>

class FrigateWorker : public QObject
{
    Q_OBJECT

public:
    explicit FrigateWorker(QObject* parent = nullptr);

public slots:
    void setServer(const QString& url);
    void loadCameras();

    // NEW — required so QML/FrigateAPI can call it safely
    void loadModuleInformation();

signals:
    // Send RAW JSON back to FrigateAPI
    void camerasLoaded(const QByteArray& jsonData);

private:
    QString m_serverUrl;
    QNetworkAccessManager* m_net;
};

#endif // FRIGATEWORKER_H
