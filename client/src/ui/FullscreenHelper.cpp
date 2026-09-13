#include "FullscreenHelper.h"
#include <QQuickWindow>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QGuiApplication>
#include <QScreen>
#include <QQuickItem>
#include <QEvent>
#include <QCursor>

#ifdef Q_OS_WIN
#  include <windows.h>
#endif

FullscreenHelper::FullscreenHelper(QObject* parent)
    : QObject(parent)
{
    m_idleTimer.setSingleShot(true);
    connect(&m_idleTimer, &QTimer::timeout, this, [this]() {
        setCursorHidden(true);
    });
}

void FullscreenHelper::startIdleCursor(int idleMs)
{
    if (!m_active) {
        qApp->installEventFilter(this);
        m_active = true;
    }
    m_idleTimer.setInterval(qMax(1000, idleMs));
    noteUserActivity();
}

void FullscreenHelper::stopIdleCursor()
{
    if (m_active) {
        qApp->removeEventFilter(this);
        m_active = false;
    }
    m_idleTimer.stop();
    setCursorHidden(false);
}

void FullscreenHelper::noteUserActivity()
{
    setCursorHidden(false);
    if (m_active)
        m_idleTimer.start();
}

void FullscreenHelper::setCursorHidden(bool hidden)
{
    if (m_cursorHidden == hidden)
        return;
    m_cursorHidden = hidden;
    if (hidden)
        QGuiApplication::setOverrideCursor(Qt::BlankCursor);
    else
        QGuiApplication::restoreOverrideCursor();
    emit cursorHiddenChanged();
}

bool FullscreenHelper::eventFilter(QObject* watched, QEvent* event)
{
    Q_UNUSED(watched);
    switch (event->type()) {
    case QEvent::MouseMove:
    case QEvent::HoverMove:
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonDblClick:
    case QEvent::Wheel:
    case QEvent::KeyPress:
    case QEvent::TabletMove:
        noteUserActivity();
        break;
    default:
        break;
    }
    return false;
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

    win->setFlags(Qt::Window | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);

    QRect screenRect = QGuiApplication::primaryScreen()->geometry();
    win->setGeometry(screenRect);

#ifdef Q_OS_WIN
    win->show();

    HWND hwnd = reinterpret_cast<HWND>(win->winId());
    if (hwnd) {
        // True fullscreen popup (covers taskbar)
        LONG style = GetWindowLong(hwnd, GWL_STYLE);
        style &= ~WS_OVERLAPPEDWINDOW;
        style |= WS_POPUP;
        SetWindowLong(hwnd, GWL_STYLE, style);

        LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        exStyle |= WS_EX_TOPMOST;
        exStyle |= WS_EX_TOOLWINDOW;
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);

        SetForegroundWindow(hwnd);
        SetActiveWindow(hwnd);
        SetFocus(hwnd);

        SetWindowPos(hwnd, HWND_TOPMOST,
                     screenRect.x(),
                     screenRect.y(),
                     screenRect.width(),
                     screenRect.height(),
                     SWP_SHOWWINDOW | SWP_FRAMECHANGED);
    }
#else
    // Linux / macOS: Qt fullscreen is reliable; no Win32 needed
    win->showFullScreen();
    win->raise();
    win->requestActivate();
#endif

    return win;
}