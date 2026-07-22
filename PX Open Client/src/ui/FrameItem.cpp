#include "FrameItem.h"
#include <QPainter>

FrameItem::FrameItem(QQuickItem* parent)
    : QQuickPaintedItem(parent)
{
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
}

void FrameItem::setFrame(const QImage& img)
{
    m_frame = img;
    update();
    emit frameChanged();
}

void FrameItem::paint(QPainter* painter)
{
    if (!m_frame.isNull())
        painter->drawImage(boundingRect(), m_frame);
}
