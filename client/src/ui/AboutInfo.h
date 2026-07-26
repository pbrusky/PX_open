#pragma once
#include <QObject>
#include <QString>
#include <QStringList>

class AboutInfo : public QObject {
    Q_OBJECT

    Q_PROPERTY(QStringList gpuList READ gpuList NOTIFY gpuListChanged)
    Q_PROPERTY(QStringList gpuVendors READ gpuVendors NOTIFY gpuVendorsChanged)
    Q_PROPERTY(bool hardwareDecoding READ hardwareDecoding CONSTANT)
    Q_PROPERTY(QString graphicsApi READ graphicsApi CONSTANT)

public:
    explicit AboutInfo(QObject* parent = nullptr);

    QStringList gpuList() const;
    QStringList gpuVendors() const;

    bool hardwareDecoding() const;
    QString graphicsApi() const;

signals:
    void gpuListChanged();
    void gpuVendorsChanged();

private:
    QStringList m_gpuList;
    QStringList m_gpuVendors;
};
