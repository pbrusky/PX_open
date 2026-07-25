#include "FrameQueue.h"

FrameQueue::FrameQueue(QObject* parent)
    : QObject(parent)
{
}

QImage FrameQueue::popImage()
{
    QMutexLocker locker(&m_mutex);
    if (m_queue.isEmpty())
        return QImage();
    return m_queue.dequeue();
}

void FrameQueue::pushImage(const QImage& img)
{
    {
        QMutexLocker locker(&m_mutex);
        m_queue.enqueue(img);
    }
    emit frameReady();
}
