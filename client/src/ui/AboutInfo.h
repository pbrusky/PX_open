#pragma once
#include <QObject>
#include <QString>
#include <QStringList>

class AboutInfo : public QObject {
    Q_OBJECT

    Q_PROPERTY(QStringList gpuList READ gpuList NOTIFY gpuListChanged)
    Q_PROPERTY(bool gpusLoading READ gpusLoading NOTIFY gpusLoadingChanged)
    Q_PROPERTY(bool hardwareDecoding READ hardwareDecoding CONSTANT)
    Q_PROPERTY(QString graphicsApi READ graphicsApi CONSTANT)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
    Q_PROPERTY(QString osName READ osName CONSTANT)
    Q_PROPERTY(QString cpuName READ cpuName NOTIFY cpuNameChanged)
    Q_PROPERTY(bool cpuLoading READ cpuLoading NOTIFY cpuLoadingChanged)
    Q_PROPERTY(QString memoryInfo READ memoryInfo NOTIFY memoryInfoChanged)
    Q_PROPERTY(bool memoryLoading READ memoryLoading NOTIFY memoryLoadingChanged)

public:
    explicit AboutInfo(QObject* parent = nullptr);

    QStringList gpuList() const;
    bool gpusLoading() const { return m_gpusLoading; }

    bool hardwareDecoding() const;
    QString graphicsApi() const;

    QString qtVersion() const;
    QString osName() const;
    QString cpuName() const { return m_cpuName; }
    bool cpuLoading() const { return m_cpuLoading; }

    QString memoryInfo() const { return m_memoryInfo; }
    bool memoryLoading() const { return m_memoryLoading; }

signals:
    void gpuListChanged();
    void gpusLoadingChanged();
    void cpuNameChanged();
    void cpuLoadingChanged();
    void memoryInfoChanged();
    void memoryLoadingChanged();

private:
    void detectGpus();
    void detectCpu();
    void detectMemory();

    QStringList m_gpuList;
    bool m_gpusLoading = true;

    QString m_cpuName;
    bool m_cpuLoading = true;

    QString m_memoryInfo;
    bool m_memoryLoading = true;
};