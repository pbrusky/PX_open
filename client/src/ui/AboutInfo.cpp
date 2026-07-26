#include "AboutInfo.h"
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QProcess>

AboutInfo::AboutInfo(QObject* parent)
    : QObject(parent)
{
}

QString AboutInfo::gpuName() const
{
    QProcess p;
    p.start("wmic path win32_VideoController get Name");
    p.waitForFinished();
    QString output = p.readAllStandardOutput().trimmed();
    return output;
}

bool AboutInfo::hardwareDecoding() const
{
    // If you forced software OpenGL for AMD, hardware decode is OFF
    QByteArray gl = qgetenv("QT_OPENGL");
    if (gl == "software")
        return false;

    // If you disabled hwaccel explicitly
    QByteArray hw = qgetenv("QT_FFMPEG_HWACCEL");
    if (hw == "none")
        return false;

    // Otherwise assume ON
    return true;
}

QString AboutInfo::graphicsApi() const
{
    auto api = QQuickWindow::graphicsApi();
    switch (api) {
        case QSGRendererInterface::Direct3D11: return "Direct3D 11";
        case QSGRendererInterface::OpenGL: return "OpenGL";
        case QSGRendererInterface::Software: return "Software Renderer";
        default: return "Unknown";
    }
}
