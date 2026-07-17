#pragma once

#include <QObject>
#include <QMutex>
#include <QQueue>
#include <QImage>

extern "C" {
#include <libavutil/frame.h>
}

class FrameQueue : public QObject
{
    Q_OBJECT

public:
    explicit FrameQueue(QObject* parent = nullptr);
    ~FrameQueue() override;

    void pushFrame(AVFrame* frame);
    QImage popImage();
    void clear();

signals:
    void frameReady();

private:
    QMutex m_mutex;
    QQueue<QImage> m_queue;

    // ⭐ Prevents runaway memory growth
    int m_maxSize = 3;
};
