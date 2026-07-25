#pragma once

#include <QQuickItem>
#include <QImage>

struct ID3D11Texture2D;
class FrameQueue;

class CameraVideoItemTexture : public QQuickItem
{
    Q_OBJECT

    Q_PROPERTY(QObject* queue READ queue WRITE setQueue NOTIFY queueChanged)

public:
    explicit CameraVideoItemTexture(QQuickItem* parent = nullptr);

    QObject* queue() const { return reinterpret_cast<QObject*>(m_queue); }
    void setQueue(QObject* q);

signals:
    void queueChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode,
                             UpdatePaintNodeData*) override;

private:
    FrameQueue* m_queue = nullptr;

    // Fallback CPU image
    QImage m_lastImage;
};
