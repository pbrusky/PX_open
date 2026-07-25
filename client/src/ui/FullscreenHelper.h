#pragma once

#include <QObject>
#include <QQuickWindow>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QGuiApplication>

class FullscreenHelper : public QObject
{
    Q_OBJECT
public:
    explicit FullscreenHelper(QObject* parent = nullptr);

    Q_INVOKABLE QQuickWindow* openFullscreen(QQmlEngine* engine,
                                             const QString& qmlPath);
};
