#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>

#include <QtWebEngineQuick>
#include <QQuickStyle>
#include <QIcon>
#include <QProcess>
#include <QLoggingCategory>

#include "FrigateAPI.h"
#include "FrigateCameraManager.h"
#include "FrigateStreamManager.h"
#include "FrigatePlayback.h"
#include "FrigateTimeline.h"
#include "FrigateOnvif.h"

#include "DiscoveryListener.h"
#include "DiscoveryProxy.h"

#include "CameraVideoItem.h"
#include "FrameItem.h"

#include "FullscreenHelper.h"
#include "AboutInfo.h"

#ifdef Q_OS_WIN
#include <windows.h>
#endif

extern "C" {
#include <libavutil/log.h>
}

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
    if (isAmdGpuPresent()) {
        qputenv("QT_OPENGL", "software");
    }

    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
    QtWebEngineQuick::initialize();
    QQuickStyle::setStyle("Fusion");

    QGuiApplication app(argc, argv);
    app.setWindowIcon(QIcon(":/assets/icon.ico"));

    av_log_set_level(AV_LOG_QUIET);

    QQmlApplicationEngine engine;

    qmlRegisterSingletonType<AboutInfo>("PxOpen", 1, 0, "AboutInfo",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return new AboutInfo();
        });

    qmlRegisterType<FrigateAPI>("PxOpen", 1, 0, "FrigateAPI");
    qmlRegisterType<FrigateCameraManager>("PxOpen", 1, 0, "FrigateCameraManager");
    qmlRegisterType<FrigateStreamManager>("PxOpen", 1, 0, "FrigateStreamManager");
    qmlRegisterType<FrigatePlayback>("PxOpen", 1, 0, "FrigatePlayback");
    qmlRegisterType<FrigateTimeline>("PxOpen", 1, 0, "FrigateTimeline");
    qmlRegisterType<FrigateOnvif>("PxOpen", 1, 0, "FrigateOnvif");

    qmlRegisterType<CameraVideoItem>("PxOpen", 1, 0, "CameraVideoItem");
    qmlRegisterType<FrameItem>("PxOpen", 1, 0, "FrameItem");

    qmlRegisterSingletonType<FullscreenHelper>("PxOpen", 1, 0, "FullscreenHelper",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return new FullscreenHelper();
        });

    //
    // Backend singletons
    //
    FrigateAPI* frigateApi = new FrigateAPI(&engine);
    FrigateStreamManager* frigateStream = new FrigateStreamManager(&engine);

    //
    // Threaded DiscoveryListener + safe QML proxy
    //
    DiscoveryListener* discovery = new DiscoveryListener();
    DiscoveryProxy* discoveryProxy = new DiscoveryProxy();

    QThread* discoveryThread = new QThread;
    discovery->moveToThread(discoveryThread);

    QObject::connect(discoveryThread, &QThread::started,
                     discovery, &DiscoveryListener::startDiscovery);

    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&]() {
        QMetaObject::invokeMethod(discovery, "stopDiscovery", Qt::QueuedConnection);
        discoveryThread->quit();
        discoveryThread->wait();
        frigateStream->stopAllStreams();
    });

    QObject::connect(discovery, &DiscoveryListener::serverFound,
                     discoveryProxy, &DiscoveryProxy::serverFound);

    discoveryThread->start();

    //
    // Load cameras
    //
    frigateApi->setServer("http://10.36.24.104:5000");
    frigateApi->loadCameras();

    //
    // Expose to QML
    //
    engine.rootContext()->setContextProperty("frigate", frigateApi);
    engine.rootContext()->setContextProperty("discovery", discoveryProxy);
    engine.rootContext()->setContextProperty("frigateStream", frigateStream);

    engine.load(QUrl("qrc:/app/resources/qml/MainWindow.qml"));
    if (engine.rootObjects().isEmpty())
        return -1;

    QObject* mainWindowObj = engine.rootObjects().first();
    QWindow* mainWindow = qobject_cast<QWindow*>(mainWindowObj);

#ifdef Q_OS_WIN
    if (mainWindow) {
        HWND hwnd = (HWND)mainWindow->winId();

        HICON hIcon = (HICON)LoadImageW(
            nullptr,
            L"C:\\PX\\px_open\\client\\assets\\icon.ico",
            IMAGE_ICON,
            32, 32,
            LR_LOADFROMFILE
        );

        if (hIcon) {
            SendMessage(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)hIcon);
            SendMessage(hwnd, WM_SETICON, ICON_BIG,   (LPARAM)hIcon);

            LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            exStyle &= ~WS_EX_TOOLWINDOW;
            exStyle |= WS_EX_APPWINDOW;
            SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);

            SetWindowPos(hwnd, nullptr, 0,0,0,0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
        }
    }
#endif

    if (mainWindow) {
        mainWindow->setFlags(Qt::FramelessWindowHint | Qt::Window);
    }

    engine.rootContext()->setContextProperty("mainWindow", mainWindowObj);

    return app.exec();
}
