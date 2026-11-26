#include "FrameQueue.h"

FrameQueue::FrameQueue(QObject* parent)
    : QObject(parent)
{
}

void FrameQueue::pushFrame(AVFramePtr frame)
{
    if (!frame)
        return;

    {
        QMutexLocker locker(&m_mutex);
        const int maxSize = m_maxSize > 0 ? m_maxSize : 1;
        while (!m_frameQueue.isEmpty() && m_frameQueue.size() >= maxSize)
            m_frameQueue.dequeue();

        m_frameQueue.enqueue(std::move(frame));
        m_receivedAny = true;
    }
    emit frameReady();
}

AVFramePtr FrameQueue::popFrame()
{
    QMutexLocker locker(&m_mutex);
    if (m_frameQueue.isEmpty())
        return nullptr;
    return m_frameQueue.dequeue();
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
        const int maxSize = m_maxSize > 0 ? m_maxSize : 1;
        while (!m_imageQueue.isEmpty() && m_imageQueue.size() >= maxSize)
            m_imageQueue.dequeue();

        m_lastImage = img.copy();
        m_imageQueue.enqueue(m_lastImage);
        m_receivedAny = true;
    }
    emit frameReady();
}

bool FrameQueue::hasFrames() const
{
    QMutexLocker locker(&m_mutex);
    return !m_imageQueue.isEmpty()
        || !m_lastImage.isNull()
        || !m_textureQueue.isEmpty()
        || !m_frameQueue.isEmpty();
}

bool FrameQueue::hasReceivedFrames() const
{
    QMutexLocker locker(&m_mutex);
    return m_receivedAny;
}

void FrameQueue::resetReceived()
{
    QMutexLocker locker(&m_mutex);
    m_receivedAny = false;
}

void FrameQueue::clear()
{
    QMutexLocker locker(&m_mutex);
    m_imageQueue.clear();
    m_lastImage = QImage();
    m_textureQueue.clear();
    m_frameQueue.clear();
    m_receivedAny = false;
}

int FrameQueue::frameCount() const
{
    QMutexLocker locker(&m_mutex);
    return m_imageQueue.size() + m_textureQueue.size() + m_frameQueue.size();
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
        m_receivedAny = true;
    }
    emit frameReady();
}