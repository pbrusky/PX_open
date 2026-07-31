#ifndef DISCOVERYLISTENER_H
#define DISCOVERYLISTENER_H

#include <QObject>
#include <QUdpSocket>

class DiscoveryListener : public QObject
{
    Q_OBJECT

public:
    explicit DiscoveryListener(QObject* parent = nullptr);

public slots:
    void startDiscovery();
    void stopDiscovery();

signals:
    void serverFound(QString name,
                     QString address,
                     int port,
                     QString container,
                     QString systemId,
                     QString moduleId,
                     QString type);

private slots:
    void processPendingDatagrams();

private:
    QUdpSocket* m_socket;
};

#endif // DISCOVERYLISTENER_H
