#pragma once

#include <QQuickPaintedItem>
#include <QImage>
#include <QMutex>

class FrameItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QImage frame READ frame WRITE setFrame NOTIFY frameChanged)

public:
    explicit FrameItem(QQuickItem* parent = nullptr);

    QImage frame() const;
    void setFrame(const QImage& img);

signals:
    void frameChanged();

protected:
    void paint(QPainter* painter) override;

private:
    QImage m_frame;
    mutable QMutex m_mutex;
};