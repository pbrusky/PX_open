#ifndef DISCOVERYPROXY_H
#define DISCOVERYPROXY_H

#include <QObject>

class DiscoveryProxy : public QObject
{
    Q_OBJECT

public:
    explicit DiscoveryProxy(QObject* parent = nullptr) : QObject(parent) {}

signals:
    void serverFound(const QString& name,
                     const QString& address,
                     int port,
                     const QString& container,
                     const QString& systemId,
                     const QString& moduleId,
                     const QString& type);
};

#endif // DISCOVERYPROXY_H