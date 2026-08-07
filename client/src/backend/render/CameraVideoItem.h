#pragma once

#include <QQuickItem>
#include <QImage>

class FrameQueue;

class CameraVideoItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QObject* queue READ queue WRITE setQueue NOTIFY queueChanged)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)

public:
    explicit CameraVideoItem(QQuickItem* parent = nullptr);

    QObject* queue() const { return reinterpret_cast<QObject*>(m_queue); }
    void setQueue(QObject* q);

    bool hasFrame() const { return m_hasFrame; }

signals:
    void queueChanged();
    void hasFrameChanged();
    void framePresented();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode,
                             UpdatePaintNodeData*) override;

private:
    FrameQueue* m_queue = nullptr;
    QImage m_lastImage;
    qint64 m_lastPaintMs = 0;
    bool m_hasFrame = false;
};