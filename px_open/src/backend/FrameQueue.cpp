#include "FrameQueue.h"
#include <QMutexLocker>
#include <QImage>
#include <QDebug>

extern "C" {
#include <libswscale/swscale.h>
}

static QImage convertNV12ToRGB(const AVFrame* frame)
{
    const int w = frame->width;
    const int h = frame->height;

    // Allocate RGB32 output
    QImage img(int(w), int(h), QImage::Format_RGB32);   // ⭐ Fix narrowing warning

    // Create swscale context
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

FrameQueue::FrameQueue(QObject* parent)
    : QObject(parent)
{
    // m_maxSize is now declared in the header
}

FrameQueue::~FrameQueue()
{
    clear();
}

void FrameQueue::pushFrame(AVFrame* frame)
{
    QMutexLocker locker(&m_mutex);

    if (!frame || frame->format != AV_PIX_FMT_NV12)
        return;

    // Convert using FFmpeg scaler (fast)
    QImage img = convertNV12ToRGB(frame);

    // Drop oldest frame if queue is full
    if (m_queue.size() >= m_maxSize)
        m_queue.dequeue();

    m_queue.enqueue(img);

    emit frameReady();
}

QImage FrameQueue::popImage()
{
    QMutexLocker locker(&m_mutex);

    if (m_queue.isEmpty())
        return QImage();

    return m_queue.dequeue();
}

void FrameQueue::clear()
{
    QMutexLocker locker(&m_mutex);
    m_queue.clear();
}
