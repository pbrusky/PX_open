#include "FrameQueue.h"

#include <QMutexLocker>
#include <QImage>
#include <QDebug>

extern "C" {
#include <libswscale/swscale.h>
}

//
// Convert NV12 → QImage (RGB32/BGRA)
//
static QImage convertNV12ToRGB(const AVFrame* frame)
{
    const int w = frame->width;
    const int h = frame->height;

    // Allocate QImage
    QImage img(w, h, QImage::Format_RGB32);
    if (img.isNull()) {
        qWarning() << "FrameQueue: Failed to allocate QImage";
        return QImage();
    }

    // Create scaler
    SwsContext* sws = sws_getContext(
        w, h, AV_PIX_FMT_NV12,
        w, h, AV_PIX_FMT_BGRA,   // BGRA matches QImage::Format_RGB32
        SWS_BILINEAR,
        nullptr, nullptr, nullptr
    );

    if (!sws) {
        qWarning() << "FrameQueue: sws_getContext FAILED";
        return img;
    }

    uint8_t* dest[4] = { img.bits(), nullptr, nullptr, nullptr };
    int destStride[4] = { img.bytesPerLine(), 0, 0, 0 };

    sws_scale(
        sws,
        frame->data,
        frame->linesize,
        0,
        h,
        dest,
        destStride
    );

    sws_freeContext(sws);
    return img;
}

//
// Constructor
//
FrameQueue::FrameQueue(QObject* parent)
    : QObject(parent)
{
}

//
// Destructor
//
FrameQueue::~FrameQueue()
{
    clear();
}

//
// Push a decoded FFmpeg frame into the queue
//
void FrameQueue::pushFrame(AVFrame* frame)
{
    QMutexLocker locker(&m_mutex);

    if (!frame) {
        return;
    }

    if (frame->format != AV_PIX_FMT_NV12) {
        // Unsupported format — ignore silently
        return;
    }

    // Convert NV12 → QImage
    QImage img = convertNV12ToRGB(frame);
    if (img.isNull()) {
        return;
    }

    // Drop oldest frame if queue is full
    if (m_queue.size() >= m_maxSize) {
        m_queue.dequeue();
    }

    m_queue.enqueue(img);

    emit frameReady();
}

//
// Pop the next QImage
//
QImage FrameQueue::popImage()
{
    QMutexLocker locker(&m_mutex);

    if (m_queue.isEmpty()) {
        return QImage();
    }

    return m_queue.dequeue();
}

//
// Clear all frames
//
void FrameQueue::clear()
{
    QMutexLocker locker(&m_mutex);
    m_queue.clear();
}
