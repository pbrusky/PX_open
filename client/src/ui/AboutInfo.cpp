#include "AboutInfo.h"

#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QProcess>
#include <QSysInfo>
#include <QtConcurrent>
#include <QMetaObject>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

AboutInfo::AboutInfo(QObject* parent)
    : QObject(parent)
{
    detectGpus();
    detectCpu();
    detectMemory();
}

void AboutInfo::detectGpus()
{
    m_gpusLoading = true;
    emit gpusLoadingChanged();

    (void) QtConcurrent::run([this]() {
        QProcess p;
        p.start(QStringLiteral("powershell"), {
            QStringLiteral("-NoProfile"),
            QStringLiteral("-Command"),
            QStringLiteral("(Get-CimInstance Win32_VideoController).Name")
        });
        p.waitForFinished(8000);

        QString output = QString::fromLocal8Bit(p.readAllStandardOutput()).trimmed();
        QStringList lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (QString& line : lines)
            line = line.trimmed();
        lines.removeAll(QString());

        QMetaObject::invokeMethod(this, [this, lines]() {
            m_gpuList = lines;
            m_gpusLoading = false;
            emit gpuListChanged();
            emit gpusLoadingChanged();
        }, Qt::QueuedConnection);
    });
}

void AboutInfo::detectCpu()
{
    m_cpuLoading = true;
    emit cpuLoadingChanged();

    (void) QtConcurrent::run([this]() {
        QProcess p;
        p.start(QStringLiteral("powershell"), {
            QStringLiteral("-NoProfile"),
            QStringLiteral("-Command"),
            QStringLiteral("(Get-CimInstance Win32_Processor | Select-Object -First 1).Name")
        });
        p.waitForFinished(8000);

        QString name = QString::fromLocal8Bit(p.readAllStandardOutput()).trimmed();
        if (name.isEmpty())
            name = QStringLiteral("Unknown");

        QMetaObject::invokeMethod(this, [this, name]() {
            m_cpuName = name;
            m_cpuLoading = false;
            emit cpuNameChanged();
            emit cpuLoadingChanged();
        }, Qt::QueuedConnection);
    });
}

void AboutInfo::detectMemory()
{
    m_memoryLoading = true;
    emit memoryLoadingChanged();

    (void) QtConcurrent::run([this]() {
        QString info = QStringLiteral("Unknown");

#ifdef Q_OS_WIN
        MEMORYSTATUSEX st;
        st.dwLength = sizeof(st);
        if (GlobalMemoryStatusEx(&st)) {
            const double totalGb = double(st.ullTotalPhys) / (1024.0 * 1024.0 * 1024.0);
            const double availGb = double(st.ullAvailPhys) / (1024.0 * 1024.0 * 1024.0);
            const double usedGb  = totalGb - availGb;
            info = QStringLiteral("%1 GB total  ·  %2 GB used  ·  %3 GB free")
                       .arg(totalGb, 0, 'f', 1)
                       .arg(usedGb, 0, 'f', 1)
                       .arg(availGb, 0, 'f', 1);
        }
#endif

        QMetaObject::invokeMethod(this, [this, info]() {
            m_memoryInfo = info;
            m_memoryLoading = false;
            emit memoryInfoChanged();
            emit memoryLoadingChanged();
        }, Qt::QueuedConnection);
    });
}

QStringList AboutInfo::gpuList() const
{
    return m_gpuList;
}

bool AboutInfo::hardwareDecoding() const
{
    if (qgetenv("QT_OPENGL") == "software")
        return false;
    if (qgetenv("QT_FFMPEG_HWACCEL") == "none")
        return false;
    return true;
}

QString AboutInfo::graphicsApi() const
{
    switch (QQuickWindow::graphicsApi()) {
    case QSGRendererInterface::Direct3D11: return QStringLiteral("Direct3D 11");
    case QSGRendererInterface::OpenGL:     return QStringLiteral("OpenGL");
    case QSGRendererInterface::Software:   return QStringLiteral("Software Renderer");
    default:                               return QStringLiteral("Unknown");
    }
}

QString AboutInfo::qtVersion() const
{
    return QString::fromLatin1(qVersion());
}

QString AboutInfo::osName() const
{
    const QString pretty = QSysInfo::prettyProductName();
    if (!pretty.isEmpty())
        return pretty;
    return QSysInfo::productType() + QLatin1Char(' ') + QSysInfo::productVersion();
}