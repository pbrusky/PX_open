#include "FrameQueue.h"
#include <QDateTime>

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

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();

    {
        QMutexLocker locker(&m_mutex);

        const int maxSize = m_maxSize > 0 ? m_maxSize : 1;
        while (!m_imageQueue.isEmpty() && m_imageQueue.size() >= maxSize)
            m_imageQueue.dequeue();

        m_lastImage = img.copy();
        m_imageQueue.enqueue(m_lastImage);
        m_lastEmitMs = nowMs;
    }

    emit frameReady();
}

bool FrameQueue::hasFrames() const
{
    QMutexLocker locker(&m_mutex);
    return !m_imageQueue.isEmpty() || !m_lastImage.isNull();
}

int FrameQueue::frameCount() const
{
    QMutexLocker locker(&m_mutex);
    return m_imageQueue.size();
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