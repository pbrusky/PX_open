#include "DiscoveryListener.h"

#include <QUdpSocket>
#include <QNetworkDatagram>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QHostAddress>

DiscoveryListener::DiscoveryListener(QObject* parent)
    : QObject(parent),
      m_socket(nullptr)
{
}

void DiscoveryListener::startDiscovery()
{
    if (!m_socket) {
        m_socket = new QUdpSocket(this);
        connect(m_socket, &QUdpSocket::readyRead,
                this, &DiscoveryListener::processPendingDatagrams);
    }

    if (m_socket->state() != QAbstractSocket::UnconnectedState) {
        qDebug() << "[Discovery] Already running, ignoring startDiscovery()";
        return;
    }

    qDebug() << "[Discovery] Binding UDP 3666";

    if (!m_socket->bind(QHostAddress::AnyIPv4, 3666, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        qWarning() << "[Discovery] Failed to bind UDP 3666:" << m_socket->errorString();
        return;
    }

    qDebug() << "[Discovery] Listening for Frigate discovery packets";
}

void DiscoveryListener::stopDiscovery()
{
    if (m_socket && m_socket->state() != QAbstractSocket::UnconnectedState) {
        qDebug() << "[Discovery] Stopping discovery";
        m_socket->close();
    }
}

void DiscoveryListener::processPendingDatagrams()
{
    if (!m_socket)
        return;

    while (m_socket->hasPendingDatagrams()) {
        QNetworkDatagram datagram = m_socket->receiveDatagram();
        QByteArray data = datagram.data();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (!doc.isObject())
            continue;

        QJsonObject obj = doc.object();

        QString name       = obj.value(QStringLiteral("name")).toString();
        int port           = obj.value(QStringLiteral("port")).toInt();
        QString container  = obj.value(QStringLiteral("container")).toString();
        QString systemId   = obj.value(QStringLiteral("systemId")).toString();
        QString moduleId   = obj.value(QStringLiteral("id")).toString();
        QString type       = obj.value(QStringLiteral("type")).toString();

        if (port <= 0 || (name.isEmpty() && systemId.isEmpty()))
            continue;

        QHostAddress senderAddr = datagram.senderAddress();
        if (senderAddr.protocol() == QAbstractSocket::IPv6Protocol) {
            bool ok = false;
            QHostAddress ipv4(senderAddr.toIPv4Address(&ok));
            if (ok)
                senderAddr = ipv4;
        }

        QString senderIp = senderAddr.toString();
        if (senderIp.startsWith(QLatin1String("::ffff:")))
            senderIp = senderIp.mid(7);

        emit serverFound(name,
                         senderIp,
                         port,
                         container,
                         systemId,
                         moduleId,
                         type);
    }
}