#include "AboutInfo.h"

#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QProcess>
#include <QSysInfo>
#include <QtConcurrent>
#include <QMetaObject>
#include <QFile>
#include <QTextStream>

#ifdef Q_OS_WIN
#  include <windows.h>
#else
#  include <unistd.h>
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
        QStringList lines;

#ifdef Q_OS_WIN
        QProcess p;
        p.start(QStringLiteral("powershell"), {
            QStringLiteral("-NoProfile"),
            QStringLiteral("-Command"),
            QStringLiteral("(Get-CimInstance Win32_VideoController).Name")
        });
        p.waitForFinished(8000);

        const QString output = QString::fromLocal8Bit(p.readAllStandardOutput()).trimmed();
        lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (QString& line : lines)
            line = line.trimmed();
        lines.removeAll(QString());
#else
        QProcess p;
        p.start(QStringLiteral("lspci"), QStringList());
        if (p.waitForFinished(3000)) {
            const QString output = QString::fromLocal8Bit(p.readAllStandardOutput());
            const QStringList all = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
            for (const QString& line : all) {
                const QString lower = line.toLower();
                if (lower.contains(QStringLiteral("vga")) ||
                    lower.contains(QStringLiteral("3d")) ||
                    lower.contains(QStringLiteral("display"))) {
                    const int colon = line.indexOf(QLatin1Char(':'));
                    QString name = (colon >= 0) ? line.mid(colon + 1).trimmed() : line.trimmed();
                    if (!name.isEmpty())
                        lines.append(name);
                }
            }
        }
        if (lines.isEmpty())
            lines.append(QStringLiteral("Unknown"));
#endif

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
        QString name = QStringLiteral("Unknown");

#ifdef Q_OS_WIN
        QProcess p;
        p.start(QStringLiteral("powershell"), {
            QStringLiteral("-NoProfile"),
            QStringLiteral("-Command"),
            QStringLiteral("(Get-CimInstance Win32_Processor | Select-Object -First 1).Name")
        });
        p.waitForFinished(8000);

        name = QString::fromLocal8Bit(p.readAllStandardOutput()).trimmed();
        if (name.isEmpty())
            name = QStringLiteral("Unknown");
#else
        auto readCpuFromProc = []() -> QString {
            QFile f(QStringLiteral("/proc/cpuinfo"));
            if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
                return {};
            const QString all = QString::fromUtf8(f.readAll());
            QString fallback;
            for (const QString& raw : all.split(QLatin1Char('\n'))) {
                const QString line = raw.trimmed();
                if (line.startsWith(QStringLiteral("model name"))) {
                    const int c = line.indexOf(QLatin1Char(':'));
                    if (c >= 0) {
                        const QString v = line.mid(c + 1).trimmed();
                        if (!v.isEmpty())
                            return v;
                    }
                }
                if (line.startsWith(QStringLiteral("Hardware")) ||
                    line.startsWith(QStringLiteral("Processor"))) {
                    const int c = line.indexOf(QLatin1Char(':'));
                    if (c >= 0) {
                        const QString v = line.mid(c + 1).trimmed();
                        if (!v.isEmpty())
                            fallback = v;
                    }
                }
            }
            return fallback;
        };

        name = readCpuFromProc();
        if (name.isEmpty()) {
            QProcess p;
            p.start(QStringLiteral("lscpu"), QStringList());
            if (p.waitForFinished(3000)) {
                const QString out = QString::fromLocal8Bit(p.readAllStandardOutput());
                for (const QString& raw : out.split(QLatin1Char('\n'))) {
                    if (raw.startsWith(QStringLiteral("Model name:"))) {
                        name = raw.mid(QStringLiteral("Model name:").size()).trimmed();
                        break;
                    }
                }
            }
        }
        if (name.isEmpty())
            name = QStringLiteral("Unknown");
#endif

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
#else
        qint64 totalBytes = 0;
        qint64 availBytes = 0;

#if defined(_SC_PHYS_PAGES) && defined(_SC_PAGESIZE)
        {
            const long pages = sysconf(_SC_PHYS_PAGES);
            const long pageSize = sysconf(_SC_PAGESIZE);
            if (pages > 0 && pageSize > 0)
                totalBytes = qint64(pages) * qint64(pageSize);
        }
#endif
#if defined(_SC_AVPHYS_PAGES) && defined(_SC_PAGESIZE)
        {
            const long pages = sysconf(_SC_AVPHYS_PAGES);
            const long pageSize = sysconf(_SC_PAGESIZE);
            if (pages > 0 && pageSize > 0)
                availBytes = qint64(pages) * qint64(pageSize);
        }
#endif

        if (totalBytes <= 0) {
            QFile f(QStringLiteral("/proc/meminfo"));
            if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
                qint64 totalKb = 0;
                qint64 availKb = 0;
                const QString all = QString::fromUtf8(f.readAll());
                for (const QString& raw : all.split(QLatin1Char('\n'))) {
                    if (raw.startsWith(QStringLiteral("MemTotal:"))) {
                        const QStringList parts = raw.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                        if (parts.size() >= 2)
                            totalKb = parts[1].toLongLong();
                    } else if (raw.startsWith(QStringLiteral("MemAvailable:"))) {
                        const QStringList parts = raw.split(QLatin1Char(' '), Qt::SkipEmptyParts);
                        if (parts.size() >= 2)
                            availKb = parts[1].toLongLong();
                    }
                }
                totalBytes = totalKb * 1024;
                availBytes = availKb * 1024;
            }
        }

        if (totalBytes > 0) {
            const double totalGb = double(totalBytes) / (1024.0 * 1024.0 * 1024.0);
            const double availGb = double(availBytes) / (1024.0 * 1024.0 * 1024.0);
            const double usedGb  = qMax(0.0, totalGb - availGb);
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