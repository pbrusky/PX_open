#include "CameraVideoItem.h"
#include "FrameQueue.h"

#include <QSGSimpleTextureNode>
#include <QQuickWindow>
#include <QDebug>
#include <QDateTime>

CameraVideoItem::CameraVideoItem(QQuickItem* parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

void CameraVideoItem::setQueue(QObject* q)
{
    if (m_queue)
        disconnect(m_queue, nullptr, this, nullptr);

    m_queue = q ? qobject_cast<FrameQueue*>(q) : nullptr;

    if (m_queue) {
        connect(m_queue, &FrameQueue::frameReady,
                this, &QQuickItem::update,
                Qt::QueuedConnection);
    }

    emit queueChanged();
    update();
}

QSGNode* CameraVideoItem::updatePaintNode(QSGNode* oldNode,
                                          UpdatePaintNodeData*)
{
    QSGSimpleTextureNode* node = static_cast<QSGSimpleTextureNode*>(oldNode);

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const bool shouldRender = m_lastPaintMs == 0 || (nowMs - m_lastPaintMs) >= 8;

    // Pop latest QImage frame
    if (m_queue) {
        QImage img = m_queue->popImage();
        if (!img.isNull() && shouldRender && (m_lastImage.isNull() || !(m_lastImage.size() == img.size() && m_lastImage == img))) {
            m_lastImage = img;
            m_lastPaintMs = nowMs;
        }
    }

    if (!window() || m_lastImage.isNull())
        return oldNode;

    if (!node)
        node = new QSGSimpleTextureNode();

    QSGTexture* tex = window()->createTextureFromImage(m_lastImage);
    if (!tex)
        return node;

    node->setTexture(tex);
    node->setOwnsTexture(true);

    // Aspect ratio preservation
    QRectF bounds = boundingRect();
    float tileW = bounds.width();
    float tileH = bounds.height();

    float frameW = m_lastImage.width();
    float frameH = m_lastImage.height();

    if (frameW > 0 && frameH > 0) {
        float frameAspect = frameW / frameH;
        float tileAspect = tileW / tileH;

        float renderW, renderH;

        if (frameAspect > tileAspect) {
            renderW = tileW;
            renderH = tileW / frameAspect;
        } else {
            renderH = tileH;
            renderW = tileH * frameAspect;
        }

        float x = (tileW - renderW) / 2.0f;
        float y = (tileH - renderH) / 2.0f;

        node->setRect(QRectF(x, y, renderW, renderH));
    }

    return node;
}
