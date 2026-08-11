#pragma once

#include <QObject>
#include <QImage>
#include <QMutex>
#include <QQueue>

struct ID3D11Texture2D;

class FrameQueue : public QObject
{
    Q_OBJECT

public:
    explicit FrameQueue(QObject* parent = nullptr);

    Q_INVOKABLE QImage popImage();
    void pushImage(const QImage& img);

    ID3D11Texture2D* popTexture();
    void pushTexture(ID3D11Texture2D* tex);

    void setMaxSize(int size) { m_maxSize = size; }

    Q_INVOKABLE bool hasFrames() const;
    Q_INVOKABLE int frameCount() const;
    Q_INVOKABLE bool hasReceivedFrames() const;
    Q_INVOKABLE void resetReceived();
    Q_INVOKABLE void clear();

signals:
    void frameReady();

private:
    mutable QMutex m_mutex;
    int m_maxSize = 2;
    bool m_receivedAny = false;

    QImage m_lastImage;
    QQueue<QImage> m_imageQueue;
    QQueue<ID3D11Texture2D*> m_textureQueue;
};