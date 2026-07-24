#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>

#include <QtWebEngineQuick>
#include <QQuickStyle>
#include <QIcon>
#include <QProcess>
#include <QDebug>

#include "FrigateAPI.h"
#include "FrigateCameraManager.h"
#include "FrigateStreamManager.h"
#include "FrigatePlayback.h"
#include "FrigateTimeline.h"
#include "FrigateOnvif.h"

#include "DiscoveryListener.h"
#include "CameraVideoItem.h"
#include "FrameItem.h"

#ifdef Q_OS_WIN
#include <windows.h>
#endif

// ---------------------------------------------------------
// GPU Detection (AMD → force software OpenGL)
// ---------------------------------------------------------
bool isAmdGpuPresent()
{
    QProcess p;
    p.start("wmic path win32_VideoController get Name");
    p.waitForFinished();
    QString output = p.readAllStandardOutput().toLower();

    return output.contains("amd") || output.contains("radeon");
}

int main(int argc, char *argv[])
{
    // GPU detection BEFORE creating QGuiApplication
    if (isAmdGpuPresent()) {
        qputenv("QT_OPENGL", "software");
        qDebug() << "AMD GPU detected — forcing software OpenGL";
    } else {
        qDebug() << "Non-AMD GPU detected — using default OpenGL";
    }

    // Force D3D11 for stability
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);

    // Initialize WebEngine
    QtWebEngineQuick::initialize();

    // Use Fusion style
    QQuickStyle::setStyle("Fusion");

    // Create application
    QGuiApplication app(argc, argv);

    // Qt internal icon (used for dialogs, etc.)
    app.setWindowIcon(QIcon(":/assets/icon.ico"));

    QQmlApplicationEngine engine;

    //
    // Register backend types
    //
    qmlRegisterType<FrigateAPI>("PxOpen", 1, 0, "FrigateAPI");
    qmlRegisterType<FrigateCameraManager>("PxOpen", 1, 0, "FrigateCameraManager");
    qmlRegisterType<FrigateStreamManager>("PxOpen", 1, 0, "FrigateStreamManager");
    qmlRegisterType<FrigatePlayback>("PxOpen", 1, 0, "FrigatePlayback");
    qmlRegisterType<FrigateTimeline>("PxOpen", 1, 0, "FrigateTimeline");
    qmlRegisterType<FrigateOnvif>("PxOpen", 1, 0, "FrigateOnvif");

    qmlRegisterType<CameraVideoItem>("PxOpen", 1, 0, "CameraVideoItem");
    qmlRegisterType<FrameItem>("PxOpen", 1, 0, "FrameItem");

    //
    // Create backend singletons
    //
    FrigateAPI* frigateApi = new FrigateAPI(&engine);
    DiscoveryListener* discovery = new DiscoveryListener(&engine);
    FrigateStreamManager* frigateStream = new FrigateStreamManager(&engine);

    //
    // Expose to QML
    //
    engine.rootContext()->setContextProperty("frigate", frigateApi);
    engine.rootContext()->setContextProperty("discovery", discovery);
    engine.rootContext()->setContextProperty("frigateStream", frigateStream);

    //
    // Graceful shutdown: stop all FFmpeg workers BEFORE QML engine dies
    //
    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&]() {
        frigateStream->stopAllStreams();
    });

    engine.load(QUrl("qrc:/app/resources/qml/MainWindow.qml"));

    if (engine.rootObjects().isEmpty())
        return -1;

    //
    // ⭐ Set icon on the actual Win32 window (required for frameless windows)
    //
    QObject* mainWindowObj = engine.rootObjects().first();
    QWindow* mainWindow = qobject_cast<QWindow*>(mainWindowObj);

#ifdef Q_OS_WIN
    if (mainWindow) {
        HWND hwnd = (HWND)mainWindow->winId();

        // Load icon from your actual filesystem path
        HICON hIcon = (HICON)LoadImageW(
            nullptr,
            L"C:\\PX\\px_open\\client\\assets\\icon.ico",   // ⭐ YOUR REAL PATH
            IMAGE_ICON,
            32, 32,
            LR_LOADFROMFILE
        );

        if (hIcon) {
            // Apply icon to small + large Win32 slots
            SendMessage(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);
            SendMessage(hwnd, WM_SETICON, ICON_BIG,   (LPARAM)hIcon);

            // Force Windows to treat this as a normal app window
            LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            exStyle &= ~WS_EX_TOOLWINDOW;
            exStyle |= WS_EX_APPWINDOW;
            SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);

            // Refresh window frame so icon appears immediately
            SetWindowPos(hwnd, nullptr, 0,0,0,0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        }
    }
#endif

    engine.rootContext()->setContextProperty("mainWindow", mainWindowObj);

    return app.exec();
}
