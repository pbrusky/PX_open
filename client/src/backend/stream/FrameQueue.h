#pragma once
#include <QObject>
#include <QImage>
#include <QMutex>
#include <QQueue>

class FrameQueue : public QObject
{
    Q_OBJECT

public:
    explicit FrameQueue(QObject* parent = nullptr);

    Q_INVOKABLE QImage popImage();
    void pushImage(const QImage& img);

signals:
    void frameReady();

private:
    QMutex m_mutex;
    QQueue<QImage> m_queue;
};
