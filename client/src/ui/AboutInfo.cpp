#include "AboutInfo.h"
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QProcess>
#include <QtConcurrent>

AboutInfo::AboutInfo(QObject* parent)
    : QObject(parent)
{
    // Run GPU detection asynchronously
    (void) QtConcurrent::run([this]() {
        QProcess p;
        p.start("powershell", {
            "-Command",
            "(Get-CimInstance Win32_VideoController).Name"
        });
        p.waitForFinished();

        QString output = p.readAllStandardOutput().trimmed();
        QStringList lines = output.split("\n", Qt::SkipEmptyParts);

        for (QString &line : lines)
            line = line.trimmed();

        m_gpuList = lines;
        emit gpuListChanged();

        // Vendor detection
        m_gpuVendors.clear();
        for (const QString &gpu : m_gpuList) {
            QString lower = gpu.toLower();
            if (lower.contains("nvidia"))
                m_gpuVendors << "NVIDIA";
            else if (lower.contains("amd") || lower.contains("radeon"))
                m_gpuVendors << "AMD";
            else if (lower.contains("intel"))
                m_gpuVendors << "Intel";
            else
                m_gpuVendors << "Unknown";
        }

        emit gpuVendorsChanged();
    });
}

QStringList AboutInfo::gpuList() const {
    return m_gpuList;
}

QStringList AboutInfo::gpuVendors() const {
    return m_gpuVendors;
}

bool AboutInfo::hardwareDecoding() const
{
    QByteArray gl = qgetenv("QT_OPENGL");
    if (gl == "software")
        return false;

    QByteArray hw = qgetenv("QT_FFMPEG_HWACCEL");
    if (hw == "none")
        return false;

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
