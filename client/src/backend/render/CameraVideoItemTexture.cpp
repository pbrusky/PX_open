#include "CameraVideoItemTexture.h"
#include "FrameQueue.h"

#include <QSGSimpleTextureNode>
#include <QQuickWindow>
#include <QDebug>

CameraVideoItemTexture::CameraVideoItemTexture(QQuickItem* parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

void CameraVideoItemTexture::setQueue(QObject* q)
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

QSGNode* CameraVideoItemTexture::updatePaintNode(QSGNode* oldNode,
                                                 UpdatePaintNodeData*)
{
    QSGSimpleTextureNode* node = static_cast<QSGSimpleTextureNode*>(oldNode);

    if (!window() || !m_queue)
        return oldNode;

    // Try to pop a GPU texture (not yet used with Qt 6.5)
    ID3D11Texture2D* tex2d = m_queue->popTexture();
    Q_UNUSED(tex2d); // Qt 6.5 has no public API to bind this directly

    // Fallback: CPU image path
    QImage img = m_queue->popImage();
    if (!img.isNull())
        m_lastImage = img;

    if (m_lastImage.isNull())
        return oldNode;

    if (!node)
        node = new QSGSimpleTextureNode();

    QSGTexture* tex = window()->createTextureFromImage(m_lastImage);
    if (!tex)
        return oldNode;

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
