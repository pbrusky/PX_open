#pragma once
#include <QObject>
#include <QtQml/qqml.h>

class QmlDummy : public QObject {
    Q_OBJECT
    QML_ELEMENT
public:
    explicit QmlDummy(QObject *parent = nullptr);
};
