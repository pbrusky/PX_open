#include "FrameQueue.h"

FrameQueue::FrameQueue(QObject* parent)
    : QObject(parent)
{
}

// -----------------------------
// CPU path (QImage)
// -----------------------------
QImage FrameQueue::popImage()
{
    QMutexLocker locker(&m_mutex);

    if (m_imageQueue.isEmpty())
        return QImage();

    return m_imageQueue.dequeue();
}

void FrameQueue::pushImage(const QImage& img)
{
    {
        QMutexLocker locker(&m_mutex);

        // Drop oldest frames if queue is full
        while (m_imageQueue.size() >= m_maxSize)
            m_imageQueue.dequeue();

        m_imageQueue.enqueue(img);
    }

    emit frameReady();
}

// -----------------------------
// GPU path (ID3D11Texture2D*)
// -----------------------------
ID3D11Texture2D* FrameQueue::popTexture()
{
    QMutexLocker locker(&m_mutex);

    if (m_textureQueue.isEmpty())
        return nullptr;

    return m_textureQueue.dequeue();
}

void FrameQueue::pushTexture(ID3D11Texture2D* tex)
{
    {
        QMutexLocker locker(&m_mutex);

        while (m_textureQueue.size() >= m_maxSize) {
            // Note: we are not releasing the D3D texture here.
            // If you ever use the GPU path you must release the dropped textures.
            m_textureQueue.dequeue();
        }

        m_textureQueue.enqueue(tex);
    }

    emit frameReady();
}