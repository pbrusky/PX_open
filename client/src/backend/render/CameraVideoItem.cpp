#include "CameraVideoItem.h"
#include "FrameQueue.h"

#include <QSGSimpleTextureNode>
#include <QQuickWindow>
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

    m_lastImage = QImage();
    m_lastPaintMs = 0;
    if (m_hasFrame) {
        m_hasFrame = false;
        emit hasFrameChanged();
    }

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

    if (m_queue) {
        QImage img = m_queue->popImage();
        if (!img.isNull()) {
            m_lastImage = img;
            m_lastPaintMs = QDateTime::currentMSecsSinceEpoch();
            if (!m_hasFrame) {
                m_hasFrame = true;
                QMetaObject::invokeMethod(this, [this]() {
                    emit hasFrameChanged();
                    emit framePresented();
                }, Qt::QueuedConnection);
            }
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

    QRectF bounds = boundingRect();
    const float tileW = bounds.width();
    const float tileH = bounds.height();
    const float frameW = m_lastImage.width();
    const float frameH = m_lastImage.height();

    if (frameW > 0 && frameH > 0 && tileW > 0 && tileH > 0) {
        const float frameAspect = frameW / frameH;
        const float tileAspect = tileW / tileH;
        float renderW, renderH;

        if (frameAspect > tileAspect) {
            renderW = tileW;
            renderH = tileW / frameAspect;
        } else {
            renderH = tileH;
            renderW = tileH * frameAspect;
        }

        node->setRect(QRectF((tileW - renderW) * 0.5f,
                             (tileH - renderH) * 0.5f,
                             renderW, renderH));
    }

    return node;
}