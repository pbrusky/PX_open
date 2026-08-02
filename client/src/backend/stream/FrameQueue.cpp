#include "FrameQueue.h"

FrameQueue::FrameQueue(QObject* parent)
    : QObject(parent)
{
}

QImage FrameQueue::popImage()
{
    QMutexLocker locker(&m_mutex);

    if (m_imageQueue.isEmpty())
        return QImage();

    return m_imageQueue.dequeue();
}

void FrameQueue::pushImage(const QImage& img)
{
    if (img.isNull())
        return;

    {
        QMutexLocker locker(&m_mutex);

        // Guard: never dequeue from an empty queue (avoids QList assert)
        const int maxSize = m_maxSize > 0 ? m_maxSize : 1;
        while (!m_imageQueue.isEmpty() && m_imageQueue.size() >= maxSize)
            m_imageQueue.dequeue();

        m_imageQueue.enqueue(img.copy()); // deep copy — safe across threads
    }

    emit frameReady();
}

ID3D11Texture2D* FrameQueue::popTexture()
{
    QMutexLocker locker(&m_mutex);

    if (m_textureQueue.isEmpty())
        return nullptr;

    return m_textureQueue.dequeue();
}

void FrameQueue::pushTexture(ID3D11Texture2D* tex)
{
    if (!tex)
        return;

    {
        QMutexLocker locker(&m_mutex);

        const int maxSize = m_maxSize > 0 ? m_maxSize : 1;
        while (!m_textureQueue.isEmpty() && m_textureQueue.size() >= maxSize)
            m_textureQueue.dequeue();

        m_textureQueue.enqueue(tex);
    }

    emit frameReady();
}