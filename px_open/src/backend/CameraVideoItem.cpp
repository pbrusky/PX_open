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

    m_queue = q ? dynamic_cast<FrameQueue*>(q) : nullptr;

    if (m_queue) {
        connect(m_queue, &FrameQueue::frameReady,
                this, &QQuickItem::update);
    }

    emit queueChanged();
    update();
}

QSGNode* CameraVideoItem::updatePaintNode(QSGNode* oldNode,
                                          UpdatePaintNodeData*)
{
    QSGSimpleTextureNode* node = static_cast<QSGSimpleTextureNode*>(oldNode);

    if (m_queue) {
        QImage img = m_queue->popImage();
        if (!img.isNull())
            m_lastImage = img;
    }

    if (!window() || m_lastImage.isNull()) {
        delete node;
        return nullptr;
    }

    QSGTexture* tex = window()->createTextureFromImage(m_lastImage);
    if (!tex) {
        delete node;
        return nullptr;
    }

    if (!node)
        node = new QSGSimpleTextureNode();

    node->setTexture(tex);
    node->setOwnsTexture(true);
    node->setRect(boundingRect());

    return node;
}
