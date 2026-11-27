#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QThread>
#include <QCoreApplication>
#include <QDir>
#include <QUrl>

#include <QtWebEngineQuick>
#include <QQuickStyle>
#include <QIcon>
#include <QProcess>
#include <QLoggingCategory>
#include <QFile>

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
#  include <windows.h>
#endif

extern "C" {
#include <libavutil/log.h>
}

bool isAmdGpuPresent()
{
#ifdef Q_OS_WIN
    DISPLAY_DEVICEW dd;
    dd.cb = sizeof(dd);
    DWORD deviceIndex = 0;

    while (EnumDisplayDevicesW(NULL, deviceIndex, &dd, 0)) {
        if (dd.StateFlags & DISPLAY_DEVICE_ACTIVE || dd.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) {
            const QString gpuName = QString::fromWCharArray(dd.DeviceString).toLower();
            if (gpuName.contains(QStringLiteral("amd")) ||
                gpuName.contains(QStringLiteral("radeon")) ||
                gpuName.contains(QStringLiteral("advanced micro devices")))
            {
                return true;
            }
        }
        deviceIndex++;
    }
    return false;
#else
    QProcess p;
    p.start(QStringLiteral("lspci"), QStringList());
    if (!p.waitForFinished(2000)) {
        p.kill();
        p.waitForFinished(500);
        return false;
    }
    const QString output = QString::fromLocal8Bit(p.readAllStandardOutput()).toLower();
    return output.contains("amd") || output.contains("radeon");
#endif
}

int main(int argc, char *argv[])
{
    if (isAmdGpuPresent()) {
        qputenv("QT_OPENGL", "software");
    }

#ifdef Q_OS_WIN
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
#else
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
#endif

    QtWebEngineQuick::initialize();
    QQuickStyle::setStyle("Fusion");

    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("PXOpen"));
    app.setOrganizationDomain(QStringLiteral("pxopen.local"));
    app.setApplicationName(QStringLiteral("PX Open"));
    app.setWindowIcon(QIcon(":/assets/icon.ico"));

    av_log_set_level(AV_LOG_QUIET);

    QQmlApplicationEngine engine;

    qmlRegisterSingletonType<AboutInfo>("PxOpen", 1, 0, "AboutInfo",
        [](QQmlEngine*, QJSEngine*) -> QObject* {
            return new AboutInfo();
        });

    qmlRegisterSingletonType(
        QUrl(QStringLiteral("qrc:/app/resources/qml/components/NxStyle.qml")),
        "PxOpen", 1, 0, "NxStyle");

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

#ifndef PX_OPEN_VERSION
#define PX_OPEN_VERSION "unknown"
#endif

    QString version = QStringLiteral(PX_OPEN_VERSION);
    const QStringList versionCandidates = {
        QDir(QCoreApplication::applicationDirPath()).filePath("version.txt"),
        QDir(QCoreApplication::applicationDirPath()).filePath("../version.txt"),
        QStringLiteral("client/version.txt"),
        QStringLiteral("version.txt"),
    };
    for (const QString& path : versionCandidates) {
        QFile vf(path);
        if (vf.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString fileVersion = QString::fromUtf8(vf.readAll()).trimmed();
            if (!fileVersion.isEmpty()) {
                version = fileVersion;
                break;
            }
        }
    }
    app.setApplicationVersion(version);
    engine.rootContext()->setContextProperty("PX_VERSION", version);

    FrigateAPI* frigateApi = new FrigateAPI(&engine);
    FrigateStreamManager* frigateStream = new FrigateStreamManager(&engine);

    DiscoveryListener* discovery = new DiscoveryListener();
    DiscoveryProxy* discoveryProxy = new DiscoveryProxy(&engine);
    QThread* discoveryThread = new QThread(&app);

    discovery->moveToThread(discoveryThread);

    QObject::connect(discoveryThread, &QThread::finished, discovery, &QObject::deleteLater);

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

    engine.rootContext()->setContextProperty("frigate", frigateApi);
    engine.rootContext()->setContextProperty("discovery", discoveryProxy);
    engine.rootContext()->setContextProperty("frigateStream", frigateStream);

    engine.load(QUrl("qrc:/app/resources/qml/MainWindow.qml"));
    if (engine.rootObjects().isEmpty())
        return -1;

    QObject* mainWindowObj = engine.rootObjects().first();
    QWindow* mainWindow = qobject_cast<QWindow*>(mainWindowObj);

    if (mainWindow) {
        mainWindow->setFlags(Qt::FramelessWindowHint | Qt::Window);
    }

#ifdef Q_OS_WIN
    if (mainWindow) {
        const HWND hwnd = reinterpret_cast<HWND>(mainWindow->winId());

        const QStringList iconCandidates = {
            QDir(QCoreApplication::applicationDirPath()).filePath("icon.ico"),
            QDir(QCoreApplication::applicationDirPath()).filePath("../assets/icon.ico"),
        };

        HICON hIcon = nullptr;
        for (const QString& iconPath : iconCandidates) {
            if (!QFile::exists(iconPath))
                continue;
            hIcon = static_cast<HICON>(LoadImageW(
                nullptr,
                reinterpret_cast<LPCWSTR>(iconPath.utf16()),
                IMAGE_ICON,
                32, 32,
                LR_LOADFROMFILE
            ));
            if (hIcon)
                break;
        }

        if (hIcon) {
            SendMessage(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(hIcon));
            SendMessage(hwnd, WM_SETICON, ICON_BIG,   reinterpret_cast<LPARAM>(hIcon));
            DestroyIcon(hIcon);
        }

        LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        exStyle &= ~WS_EX_TOOLWINDOW;
        exStyle |= WS_EX_APPWINDOW;
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle);

        SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
    }
#endif

    engine.rootContext()->setContextProperty("mainWindow", mainWindowObj);

    return app.exec();
}   