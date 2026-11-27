#pragma once

#include <QQuickItem>
#include <QImage>

#include <atomic>

extern "C" {
#include <libavutil/frame.h>
}

class FrameQueue;
struct SwsContext;

class CameraVideoItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QObject* queue READ queue WRITE setQueue NOTIFY queueChanged)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged)

public:
    explicit CameraVideoItem(QQuickItem* parent = nullptr);
    ~CameraVideoItem() override;

    QObject* queue() const { return reinterpret_cast<QObject*>(m_queue); }
    void setQueue(QObject* q);

    bool hasFrame() const { return m_hasFrame; }

signals:
    void queueChanged();
    void hasFrameChanged();
    void framePresented();

protected:
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*) override;

private:
    QImage convertFrame(const AVFrame* frame);

    FrameQueue* m_queue = nullptr;
    QImage m_lastImage;
    qint64 m_lastPaintMs = 0;
    bool m_hasFrame = false;
    std::atomic<quint64> m_queueGeneration{0};

    // Reused conversion context
    SwsContext* m_swsContext = nullptr;
    int m_lastSwsWidth = 0;
    int m_lastSwsHeight = 0;
    int m_lastSwsFormat = -1;
};