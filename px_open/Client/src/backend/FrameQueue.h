#pragma once

#include <QObject>
#include <QMutex>
#include <QQueue>
#include <QImage>

class FrameQueue : public QObject
{
    Q_OBJECT

public:
    explicit FrameQueue(QObject* parent = nullptr);
    ~FrameQueue() override;

    void pushImage(const QImage& img);
    Q_INVOKABLE QImage popImage();
    void clear();

signals:
    void frameReady();

private:
    QMutex m_mutex;
    QQueue<QImage> m_queue;
    int m_maxSize = 3;
};
