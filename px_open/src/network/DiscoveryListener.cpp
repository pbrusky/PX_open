#include "DiscoveryListener.h"
#include <QNetworkDatagram>
#include <QDebug>

DiscoveryListener::DiscoveryListener(QObject* parent)
    : QObject(parent),
      socket(new QUdpSocket(this))
{
}

void DiscoveryListener::start()
{
    // Listen on UDP port 54545 (your discovery proxy uses this)
    if (!socket->bind(QHostAddress::AnyIPv4, 54545, QUdpSocket::ShareAddress)) {
        qWarning() << "Failed to bind UDP discovery socket!";
        return;
    }

    connect(socket, &QUdpSocket::readyRead,
            this, &DiscoveryListener::processPendingDatagrams);

    qDebug() << "DiscoveryListener started on UDP port 54545";
}

void DiscoveryListener::processPendingDatagrams()
{
    while (socket->hasPendingDatagrams()) {
        QNetworkDatagram datagram = socket->receiveDatagram();
        QByteArray data = datagram.data();

        QString msg = QString::fromUtf8(data).trimmed();
        QString senderIp = datagram.senderAddress().toString();

        qDebug() << "Discovery packet:" << msg << "from" << senderIp;

        // Expected format from your discovery proxy:
        // FRIGATE <ip>:<port> NAME=<name> VERSION=<version>
        //
        // Example:
        // FRIGATE 192.168.1.50:5000 NAME=HomeServer VERSION=0.12.0

        if (!msg.startsWith("FRIGATE"))
            continue;

        QStringList parts = msg.split(" ");
        if (parts.size() < 2)
            continue;

        QString address = parts[1]; // "192.168.1.50:5000"

        QString name = "Frigate Server";
        for (const QString& p : parts) {
            if (p.startsWith("NAME="))
                name = p.mid(5);
        }

        emit serverFound(name, address);
    }
}
