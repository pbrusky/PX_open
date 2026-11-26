#pragma once

#include <QObject>
#include <QImage>
#include <QMutex>
#include <QQueue>
#include <memory>

extern "C" {
#include <libavutil/frame.h>
}

struct ID3D11Texture2D;

// Shared definition - only here
struct AVFrameDeleter {
    void operator()(AVFrame* f) const {
        if (f) {
            av_frame_free(&f);
        }
    }
};

using AVFramePtr = std::shared_ptr<AVFrame>;

class FrameQueue : public QObject
{
    Q_OBJECT

public:
    explicit FrameQueue(QObject* parent = nullptr);

    // Preferred path
    void pushFrame(AVFramePtr frame);
    AVFramePtr popFrame();

    // Legacy QImage path
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
    QQueue<AVFramePtr> m_frameQueue;
};