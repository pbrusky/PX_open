#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>

#include <QtWebEngineQuick>
#include <QQuickStyle>

#include "FrigateAPI.h"
#include "FrigateCameraManager.h"
#include "FrigateStreamManager.h"
#include "FrigatePlayback.h"
#include "FrigateTimeline.h"
#include "FrigateOnvif.h"

#include "DiscoveryListener.h"
#include "CameraVideoItem.h"
#include "FrameItem.h"

int main(int argc, char *argv[])
{
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
    QtWebEngineQuick::initialize();
    QQuickStyle::setStyle("Fusion");

    QGuiApplication app(argc, argv);
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
