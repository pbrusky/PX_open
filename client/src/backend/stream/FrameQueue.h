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

signals:
    void frameReady();

private:
    QMutex m_mutex;

    QQueue<QImage> m_imageQueue;
    QQueue<ID3D11Texture2D*> m_textureQueue;
};
