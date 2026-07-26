#pragma once
#include <QObject>
#include <QString>

class AboutInfo : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString gpuName READ gpuName CONSTANT)
    Q_PROPERTY(bool hardwareDecoding READ hardwareDecoding CONSTANT)
    Q_PROPERTY(QString graphicsApi READ graphicsApi CONSTANT)

public:
    explicit AboutInfo(QObject* parent = nullptr);

    QString gpuName() const;
    bool hardwareDecoding() const;
    QString graphicsApi() const;
};
