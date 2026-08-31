#pragma once

#include <QObject>
#include <QWindow>
#include <QTimer>

#ifdef Q_OS_WIN
#  include <windows.h>
#endif

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
#ifdef Q_OS_WIN
            HWND hwnd = reinterpret_cast<HWND>(window->winId());
            if (hwnd) {
                SetForegroundWindow(hwnd);
                SetActiveWindow(hwnd);
                BringWindowToTop(hwnd);
            }
#endif
            // Works on Windows and Linux (Qt handles focus where the OS allows)
            window->requestActivate();
            window->raise();
        });
    }
};