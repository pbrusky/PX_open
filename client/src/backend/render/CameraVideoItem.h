#pragma once

#include <QQuickItem>
#include <QImage>

class FrameQueue;

class CameraVideoItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QObject* queue READ queue WRITE setQueue NOTIFY queueChanged)

public:
    explicit CameraVideoItem(QQuickItem* parent = nullptr);

    QObject* queue() const { return reinterpret_cast<QObject*>(m_queue); }
    void setQueue(QObject* q);

signals:
    void queueChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode,
                             UpdatePaintNodeData*) override;

private:
    FrameQueue* m_queue = nullptr;
    QImage m_lastImage;
    qint64 m_lastPaintMs = 0;
};
