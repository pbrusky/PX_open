#ifndef DISCOVERYLISTENER_H
#define DISCOVERYLISTENER_H

#include <QObject>
#include <QUdpSocket>

class DiscoveryListener : public QObject
{
    Q_OBJECT

public:
    explicit DiscoveryListener(QObject* parent = nullptr);

    // ⭐ Both callable from QML
    Q_INVOKABLE void startDiscovery();
    Q_INVOKABLE void stopDiscovery();

signals:
    // ⭐ Full discovery info (matches your JSON)
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
