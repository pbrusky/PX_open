#pragma once

#include <QObject>
#include <QUdpSocket>

class DiscoveryListener : public QObject
{
    Q_OBJECT

public:
    explicit DiscoveryListener(QObject* parent = nullptr);

    Q_INVOKABLE void start();

signals:
    void serverFound(QString name, QString address);

private slots:
    void processPendingDatagrams();

private:
    QUdpSocket* socket;
};
