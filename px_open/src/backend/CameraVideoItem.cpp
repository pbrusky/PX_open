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
        // ⭐ Ensure GUI-thread update
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

    // ⭐ Only popImage once per frame
    if (m_queue) {
        QImage img = m_queue->popImage();
        if (!img.isNull())
            m_lastImage = img;
    }

    if (!window() || m_lastImage.isNull()) {
        return oldNode;   // ⭐ Do NOT delete node; keep stable
    }

    // ⭐ Reuse node if possible
    if (!node)
        node = new QSGSimpleTextureNode();

    // ⭐ Replace texture safely
    QSGTexture* tex = window()->createTextureFromImage(m_lastImage);
    if (!tex)
        return node;

    node->setTexture(tex);
    node->setOwnsTexture(true);
    node->setRect(boundingRect());

    return node;
}
