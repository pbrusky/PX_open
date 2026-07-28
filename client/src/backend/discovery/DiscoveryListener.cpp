#include "DiscoveryListener.h"
#include <QNetworkDatagram>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

DiscoveryListener::DiscoveryListener(QObject* parent)
    : QObject(parent),
      m_socket(new QUdpSocket(this))
{
    connect(m_socket, &QUdpSocket::readyRead,
            this, &DiscoveryListener::processPendingDatagrams);
}

void DiscoveryListener::startDiscovery()
{
    if (m_socket->state() != QAbstractSocket::UnconnectedState) {
        qDebug() << "[Discovery] Already running, ignoring startDiscovery()";
        return;
    }

    qDebug() << "[Discovery] Binding UDP 3666";

    if (!m_socket->bind(3666, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        qWarning() << "[Discovery] Failed to bind UDP 3666";
        return;
    }

    qDebug() << "[Discovery] Listening for Frigate discovery packets";
}

void DiscoveryListener::stopDiscovery()
{
    if (m_socket->state() != QAbstractSocket::UnconnectedState) {
        qDebug() << "[Discovery] Stopping discovery";
        m_socket->close();
    }
}

void DiscoveryListener::processPendingDatagrams()
{
    while (m_socket->hasPendingDatagrams()) {

        QNetworkDatagram datagram = m_socket->receiveDatagram();
        QByteArray data = datagram.data();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (!doc.isObject())
            continue;

        QJsonObject obj = doc.object();

        QString name       = obj.value("name").toString();
        int port           = obj.value("port").toInt();
        QString container  = obj.value("container").toString();
        QString systemId   = obj.value("systemId").toString();
        QString moduleId   = obj.value("id").toString();
        QString type       = obj.value("type").toString();

        QString senderIp = datagram.senderAddress().toString();
        if (senderIp.startsWith("::ffff:"))
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
