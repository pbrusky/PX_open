#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>

#include <QtWebEngineQuick>
#include <QQuickStyle>

#include "FrigateAPI.h"
#include "DiscoveryListener.h"
#include "CameraVideoItem.h"

int main(int argc, char *argv[])
{
    // USE DIRECT3D 11 (REQUIRED FOR YOUR PIPELINE)
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);

    // QtWebEngine must be initialized BEFORE QGuiApplication
    QtWebEngineQuick::initialize();

    // ENABLE FUSION STYLE (FIXES BACKGROUND CUSTOMIZATION WARNINGS)
    QQuickStyle::setStyle("Fusion");

    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;

    // Register your custom video item
    qmlRegisterType<CameraVideoItem>("PxOpen", 1, 0, "CameraVideoItem");

    // Create backend instances
    FrigateAPI* frigateApi = new FrigateAPI(&engine);
    DiscoveryListener* discovery = new DiscoveryListener(&engine);

    // Expose to QML as global singletons
    engine.rootContext()->setContextProperty("frigate", frigateApi);
    engine.rootContext()->setContextProperty("discovery", discovery);

    // Ensure FFmpeg threads stop before exit
    QObject::connect(&app, &QCoreApplication::aboutToQuit,
                     frigateApi, &FrigateAPI::stopAllStreams);

    // Load main window
    engine.load(QUrl("qrc:/app/resources/qml/MainWindow.qml"));

    if (engine.rootObjects().isEmpty())
        return -1;

    QObject* mainWindow = engine.rootObjects().first();
    engine.rootContext()->setContextProperty("mainWindow", mainWindow);

    return app.exec();
}
