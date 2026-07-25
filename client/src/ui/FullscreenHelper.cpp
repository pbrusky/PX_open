#include "FullscreenHelper.h"
#include <QQuickWindow>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QGuiApplication>
#include <QScreen>
#include <QQuickItem>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

FullscreenHelper::FullscreenHelper(QObject* parent)
    : QObject(parent)
{
}

QQuickWindow* FullscreenHelper::openFullscreen(QQmlEngine* engine,
                                               const QString& qmlPath)
{
    QQmlComponent comp(engine, QUrl(qmlPath));

    QQuickWindow* win = qobject_cast<QQuickWindow*>(comp.create());

    if (!win) {
        QObject* obj = comp.create();
        QQuickItem* item = qobject_cast<QQuickItem*>(obj);

        win = new QQuickWindow();

        if (item)
            item->setParentItem(win->contentItem());
    }

    win->setFlags(Qt::Window | Qt::FramelessWindowHint);

    QRect screenRect = QGuiApplication::primaryScreen()->geometry();
    win->setGeometry(screenRect);
    win->show();

#ifdef Q_OS_WIN
    HWND hwnd = (HWND)win->winId();

    // ⭐ Make it a true fullscreen popup window
    LONG style = GetWindowLong(hwnd, GWL_STYLE);
    style &= ~WS_OVERLAPPEDWINDOW;
    style |= WS_POPUP;                 // <‑‑ THIS is the magic
    SetWindowLong(hwnd, GWL_STYLE, style);

    LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
    exStyle |= WS_EX_TOPMOST;
    exStyle |= WS_EX_TOOLWINDOW;
    SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);

    // ⭐ Force activation + foreground
    SetForegroundWindow(hwnd);
    SetActiveWindow(hwnd);
    SetFocus(hwnd);

    // ⭐ Force topmost above taskbar
    SetWindowPos(hwnd, HWND_TOPMOST,
                 screenRect.x(),
                 screenRect.y(),
                 screenRect.width(),
                 screenRect.height(),
                 SWP_SHOWWINDOW | SWP_FRAMECHANGED);
#endif

    return win;
}
