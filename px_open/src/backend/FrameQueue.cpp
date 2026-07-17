#include "FrameQueue.h"
#include <QMutexLocker>

FrameQueue::FrameQueue(QObject* parent)
    : QObject(parent)
{
}

FrameQueue::~FrameQueue()
{
    clear();
}

void FrameQueue::pushImage(const QImage& img)
{
    QMutexLocker locker(&m_mutex);

    if (img.isNull())
        return;

    if (m_queue.size() >= m_maxSize)
        m_queue.dequeue();

    m_queue.enqueue(img);
    emit frameReady();
}

QImage FrameQueue::popImage()
{
    QMutexLocker locker(&m_mutex);

    if (m_queue.isEmpty())
        return QImage();

    return m_queue.dequeue();
}

void FrameQueue::clear()
{
    QMutexLocker locker(&m_mutex);
    m_queue.clear();
}
