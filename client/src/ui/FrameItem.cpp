#include "FrameItem.h"
#include <QPainter>
#include <QMutexLocker>

FrameItem::FrameItem(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    setRenderTarget(QQuickPaintedItem::Image);
    setMipmap(false);
    setSmooth(false);
    setAntialiasing(false);
    setOpaquePainting(true);
}

QImage FrameItem::frame() const
{
    QMutexLocker locker(&m_mutex);
    return m_frame;
}

void FrameItem::setFrame(const QImage& img)
{
    if (img.isNull() || img.width() < 32 || img.height() < 32)
        return;

    // Scale the image down once when it arrives (much cheaper than scaling every paint)
    QImage scaled = img.scaled(1920, 1080, Qt::KeepAspectRatio, Qt::FastTransformation);

    {
        QMutexLocker locker(&m_mutex);
        m_frame = std::move(scaled);   // move instead of copy
    }

    update();
    emit frameChanged();
}

void FrameItem::paint(QPainter* painter)
{
    QImage local;

    {
        QMutexLocker locker(&m_mutex);
        if (m_frame.isNull())
            return;
        local = m_frame;               // cheap shallow copy
    }

    if (local.isNull())
        return;

    // Just draw – already scaled
    painter->drawImage(boundingRect(), local);
}