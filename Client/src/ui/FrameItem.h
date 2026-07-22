#pragma once
#include <QQuickPaintedItem>
#include <QImage>

class FrameItem : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QImage frame READ frame WRITE setFrame NOTIFY frameChanged)

public:
    FrameItem(QQuickItem* parent = nullptr);

    QImage frame() const { return m_frame; }
    void setFrame(const QImage& img);

    void paint(QPainter* painter) override;

signals:
    void frameChanged();

private:
    QImage m_frame;
};
