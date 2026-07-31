#pragma once

#include <QQuickItem>
#include <QSGTexture>
#include <QSGSimpleTextureNode>

class FrameQueue;
class D3D11Renderer;

class CameraVideoItemD3D : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QObject* queue READ queue WRITE setQueue NOTIFY queueChanged)

public:
    explicit CameraVideoItemD3D(QQuickItem* parent = nullptr);
    ~CameraVideoItemD3D();

    QObject* queue() const { return reinterpret_cast<QObject*>(m_queue); }
    void setQueue(QObject* q);

signals:
    void queueChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode,
                             UpdatePaintNodeData*) override;

private:
    FrameQueue* m_queue = nullptr;
    D3D11Renderer* m_renderer = nullptr;

    QSize m_lastSize;
};
