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

    // CPU frames
    Q_INVOKABLE QImage popImage();
    void pushImage(const QImage& img);

    // GPU frames
    ID3D11Texture2D* popTexture();
    void pushTexture(ID3D11Texture2D* tex);

    // Keep only the newest N frames
    void setMaxSize(int size) { m_maxSize = size; }

signals:
    void frameReady();

private:
    QMutex m_mutex;
    int m_maxSize = 2;          // critical: keep only 1–2 frames

    QQueue<QImage> m_imageQueue;
    QQueue<ID3D11Texture2D*> m_textureQueue;
};