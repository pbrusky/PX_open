#include "CameraVideoItemD3D.h"
#include "FrameQueue.h"
#include "D3D11Renderer.h"

#include <QSGSimpleTextureNode>
#include <QQuickWindow>
#include <QDebug>

CameraVideoItemD3D::CameraVideoItemD3D(QQuickItem* parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

CameraVideoItemD3D::~CameraVideoItemD3D()
{
    delete m_renderer;
}

void CameraVideoItemD3D::setQueue(QObject* q)
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

QSGNode* CameraVideoItemD3D::updatePaintNode(QSGNode* oldNode,
                                             UpdatePaintNodeData*)
{
    if (!window() || !m_queue)
        return oldNode;

    // Create renderer if needed
    if (!m_renderer) {
        m_renderer = new D3D11Renderer(m_queue);
        m_lastSize = QSize(int(width()), int(height()));
        m_renderer->resize(m_lastSize.width(), m_lastSize.height());
    }

    // Resize renderer if item size changed
    QSize newSize(int(width()), int(height()));
    if (newSize != m_lastSize) {
        m_lastSize = newSize;
        m_renderer->resize(newSize.width(), newSize.height());
    }

    // Render into D3D11 texture
    m_renderer->render();

    // Wrap D3D11 render target into a QSGTexture
    ID3D11Texture2D* tex = m_renderer->m_renderTarget.Get();
    if (!tex)
        return oldNode;

    QSGSimpleTextureNode* node = static_cast<QSGSimpleTextureNode*>(oldNode);
    if (!node)
        node = new QSGSimpleTextureNode();

    QSGTexture* sgTex = window()->createTextureFromNativeObject(
        QQuickWindow::NativeObjectTexture,
        tex,
        0,
        newSize
    );

    node->setTexture(sgTex);
    node->setOwnsTexture(true);
    node->setRect(boundingRect());

    return node;
}
