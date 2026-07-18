#include "CameraVideoItem.h"
#include <QSGSimpleTextureNode>
#include <QQuickWindow>
#include <QDebug>

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
        // Ensure GUI-thread update
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

    // Pop one frame per update
    if (m_queue) {
        QImage img = m_queue->popImage();
        if (!img.isNull())
            m_lastImage = img;
    }

    if (!window() || m_lastImage.isNull()) {
        return oldNode;   // Keep node stable
    }

    // Reuse node if possible
    if (!node)
        node = new QSGSimpleTextureNode();

    // Create texture from latest frame
    QSGTexture* tex = window()->createTextureFromImage(m_lastImage);
    if (!tex)
        return node;

    node->setTexture(tex);
    node->setOwnsTexture(true);

    //
    // ⭐ NX Witness–style aspect ratio preservation
    //
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
            // Frame is wider → limit by width
            renderW = tileW;
            renderH = tileW / frameAspect;
        } else {
            // Frame is taller → limit by height
            renderH = tileH;
            renderW = tileH * frameAspect;
        }

        // Center the video inside the tile
        float x = (tileW - renderW) / 2.0f;
        float y = (tileH - renderH) / 2.0f;

        node->setRect(QRectF(x, y, renderW, renderH));
    }

    return node;
}
