#pragma once

#include <QObject>
#include <QQuickWindow>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QGuiApplication>
#include <QTimer>

class FullscreenHelper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool cursorHidden READ cursorHidden NOTIFY cursorHiddenChanged)
public:
    explicit FullscreenHelper(QObject* parent = nullptr);

    Q_INVOKABLE QQuickWindow* openFullscreen(QQmlEngine* engine,
                                             const QString& qmlPath);

    bool cursorHidden() const { return m_cursorHidden; }

    Q_INVOKABLE void startIdleCursor(int idleMs = 10000);
    Q_INVOKABLE void stopIdleCursor();
    Q_INVOKABLE void noteUserActivity();

signals:
    void cursorHiddenChanged();

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    void setCursorHidden(bool hidden);

    QTimer m_idleTimer;
    bool m_cursorHidden = false;
    bool m_active = false;
};
