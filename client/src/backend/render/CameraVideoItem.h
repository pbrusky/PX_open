#pragma once

#include <QQuickItem>
#include "FrameQueue.h"

class CameraVideoItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QObject* queue READ queue WRITE setQueue NOTIFY queueChanged)

public:
    explicit CameraVideoItem(QQuickItem* parent = nullptr);

    QObject* queue() const { return m_queue; }
    void setQueue(QObject* q);

signals:
    void queueChanged();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*) override;

private:
    FrameQueue* m_queue = nullptr;
    QImage m_lastImage;
};
