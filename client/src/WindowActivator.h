#pragma once

#include <QObject>
#include <QWindow>
#include <QTimer>
#include <windows.h>

class WindowActivator : public QObject
{
    Q_OBJECT
public:
    explicit WindowActivator(QObject* parent = nullptr)
        : QObject(parent)
    {}

    Q_INVOKABLE void activateDelayed(QObject* windowObject)
    {
        auto window = qobject_cast<QWindow*>(windowObject);
        if (!window)
            return;

        QTimer::singleShot(0, [window]() {
            HWND hwnd = reinterpret_cast<HWND>(window->winId());
            SetForegroundWindow(hwnd);
            SetActiveWindow(hwnd);
            BringWindowToTop(hwnd);
            window->requestActivate();
        });
    }
};
