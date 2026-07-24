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

    // Set application icon (embedded via resources.qrc)
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

    QObject* mainWindow = engine.rootObjects().first();
    engine.rootContext()->setContextProperty("mainWindow", mainWindow);

    return app.exec();
}
