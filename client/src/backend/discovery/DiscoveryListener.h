#ifndef DISCOVERYLISTENER_H
#define DISCOVERYLISTENER_H

#include <QObject>
#include <QString>

class QUdpSocket;

class DiscoveryListener : public QObject
{
    Q_OBJECT

public:
    explicit DiscoveryListener(QObject* parent = nullptr);

public slots:
    void startDiscovery();
    void stopDiscovery();

signals:
    void serverFound(const QString& name,
                     const QString& address,
                     int port,
                     const QString& container,
                     const QString& systemId,
                     const QString& moduleId,
                     const QString& type);

private slots:
    void processPendingDatagrams();

private:
    QUdpSocket* m_socket = nullptr;
};

#endif // DISCOVERYLISTENER_H