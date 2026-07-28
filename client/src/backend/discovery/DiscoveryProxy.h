#ifndef DISCOVERYPROXY_H
#define DISCOVERYPROXY_H

#include <QObject>

class DiscoveryProxy : public QObject
{
    Q_OBJECT

public:
    explicit DiscoveryProxy(QObject* parent = nullptr) : QObject(parent) {}

signals:
    void serverFound(QString name,
                     QString address,
                     int port,
                     QString container,
                     QString systemId,
                     QString moduleId,
                     QString type);
};

#endif // DISCOVERYPROXY_H
