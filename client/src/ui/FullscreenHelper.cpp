#include "FullscreenHelper.h"
#include <QQuickWindow>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QGuiApplication>
#include <QScreen>
#include <QQuickItem>
#include <QEvent>
#include <QCursor>
#include <QDebug>

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

    // Cleanup cursor when this object is destroyed without needing to modify FullscreenHelper.h
    connect(this, &QObject::destroyed, this, [this]() {
        stopIdleCursor();
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
    if (!engine)
        return nullptr;

    QQmlComponent comp(engine, QUrl(qmlPath));
    QObject* obj = comp.create();

    if (!obj) {
        qWarning() << "FullscreenHelper: Failed to create QML Component:" << comp.errorString();
        return nullptr;
    }

    QQuickWindow* win = qobject_cast<QQuickWindow*>(obj);

    if (!win) {
        QQuickItem* item = qobject_cast<QQuickItem*>(obj);
        if (item) {
            win = new QQuickWindow();
            item->setParentItem(win->contentItem());

            // Ensure child item scales with window size
            QObject::connect(win, &QQuickWindow::widthChanged, [item, win]() { item->setWidth(win->width()); });
            QObject::connect(win, &QQuickWindow::heightChanged, [item, win]() { item->setHeight(win->height()); });
            item->setSize(win->size());
        } else {
            qWarning() << "FullscreenHelper: Created root QML object is neither a QQuickWindow nor QQuickItem";
            delete obj;
            return nullptr;
        }
    }

    // Auto-delete window when closed to prevent memory leaks (Qt Quick compatible)
    QObject::connect(win, &QQuickWindow::closing, win, &QObject::deleteLater);

    win->setFlags(Qt::Window | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);

    // Detect current screen under mouse cursor instead of hardcoding primary screen
    QScreen* targetScreen = QGuiApplication::screenAt(QCursor::pos());
    if (!targetScreen)
        targetScreen = QGuiApplication::primaryScreen();

    QRect screenRect = targetScreen->geometry();
    win->setScreen(targetScreen);
    win->setGeometry(screenRect);

#ifdef Q_OS_WIN
    HWND hwnd = reinterpret_cast<HWND>(win->winId());
    if (hwnd) {
        LONG style = GetWindowLong(hwnd, GWL_STYLE);
        style &= ~WS_OVERLAPPEDWINDOW;
        style |= WS_POPUP;
        SetWindowLong(hwnd, GWL_STYLE, style);

        LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        exStyle |= WS_EX_TOPMOST;
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);

        SetWindowPos(hwnd, HWND_TOPMOST,
                     screenRect.x(),
                     screenRect.y(),
                     screenRect.width(),
                     screenRect.height(),
                     SWP_FRAMECHANGED);
    }

    win->show();

    if (hwnd) {
        SetForegroundWindow(hwnd);
        SetActiveWindow(hwnd);
        SetFocus(hwnd);
    }
#else
    win->showFullScreen();
    win->raise();
    win->requestActivate();
#endif

    return win;
}