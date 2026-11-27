#include "CameraVideoItem.h"
#include "FrameQueue.h"

#include <QSGSimpleTextureNode>
#include <QQuickWindow>
#include <QDateTime>
#include <QDebug>

extern "C" {
#include <libswscale/swscale.h>
#include <libavutil/pixfmt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/imgutils.h>
#include <libavutil/hwcontext.h>
}

CameraVideoItem::CameraVideoItem(QQuickItem* parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

CameraVideoItem::~CameraVideoItem()
{
    if (m_swsContext) {
        sws_freeContext(m_swsContext);
        m_swsContext = nullptr;
    }
}

void CameraVideoItem::setQueue(QObject* q)
{
    if (m_queue)
        disconnect(m_queue, nullptr, this, nullptr);

    // Invalidate callbacks queued by a previously connected FrameQueue.
    m_queueGeneration.fetch_add(1);
    m_queue = q ? qobject_cast<FrameQueue*>(q) : nullptr;

    // Keep last image to avoid flashing
    m_lastPaintMs = 0;

    if (m_hasFrame) {
        m_hasFrame = false;
        emit hasFrameChanged();
    }

    if (m_queue) {
        connect(m_queue, &FrameQueue::frameReady,
                this, &QQuickItem::update,
                Qt::QueuedConnection);
    }

    emit queueChanged();
    update();
}

QImage CameraVideoItem::convertFrame(const AVFrame* frame)
{
    if (!frame || frame->width <= 0 || frame->height <= 0)
        return QImage();

    const AVFrame* source = frame;

    // Hardware-decoded frames contain GPU buffer handles, not CPU pixel data.
    // libswscale cannot consume those handles directly. A camera can therefore
    // appear black when it uses D3D11VA/VAAPI/CUDA while other cameras fall
    // back to software decoding. Copy such frames to CPU memory first.
    const AVPixFmtDescriptor* desc =
        av_pix_fmt_desc_get(static_cast<AVPixelFormat>(frame->format));
    const bool hardwareFrame = frame->hw_frames_ctx != nullptr
        || (desc && (desc->flags & AV_PIX_FMT_FLAG_HWACCEL));

    AVFramePtr softwareFrame;
    if (hardwareFrame) {
        softwareFrame = AVFramePtr(av_frame_alloc(), AVFrameDeleter());
        if (!softwareFrame)
            return QImage();

        if (av_hwframe_transfer_data(softwareFrame.get(), frame, 0) < 0)
            return QImage();

        // Keep colorspace and other properties from the original frame.
        av_frame_copy_props(softwareFrame.get(), frame);
        source = softwareFrame.get();
    }

    if (source->width <= 0 || source->height <= 0)
        return QImage();

    // Reuse SwsContext when possible
    if (!m_swsContext ||
        m_lastSwsWidth != source->width ||
        m_lastSwsHeight != source->height ||
        m_lastSwsFormat != source->format) {

        if (m_swsContext) {
            sws_freeContext(m_swsContext);
            m_swsContext = nullptr;
        }

        m_swsContext = sws_getContext(
            source->width, source->height, static_cast<AVPixelFormat>(source->format),
            source->width, source->height, AV_PIX_FMT_BGRA,
            SWS_BILINEAR, nullptr, nullptr, nullptr);

        m_lastSwsWidth = source->width;
        m_lastSwsHeight = source->height;
        m_lastSwsFormat = source->format;
    }

    if (!m_swsContext)
        return QImage();

    QImage img(source->width, source->height, QImage::Format_RGB32);
    if (img.isNull())
        return QImage();

    uint8_t* dest[4] = { img.bits(), nullptr, nullptr, nullptr };
    int destStride[4] = { static_cast<int>(img.bytesPerLine()), 0, 0, 0 };

    if (sws_scale(m_swsContext,
                  source->data,
                  source->linesize,
                  0,
                  source->height,
                  dest,
                  destStride) < 0)
        return QImage();

    return img;
}

QSGNode* CameraVideoItem::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*)
{
    QSGSimpleTextureNode* node = static_cast<QSGSimpleTextureNode*>(oldNode);

    bool gotNewFrame = false;
    const quint64 queueGeneration = m_queueGeneration.load();

    if (m_queue) {
        // Preferred path: AVFrame
        AVFramePtr frame = m_queue->popFrame();
        if (frame) {
            QImage img = convertFrame(frame.get());
            if (!img.isNull()) {
                m_lastImage = img;
                gotNewFrame = true;
            }
        }

        // Fallback: old QImage path
        if (!gotNewFrame) {
            QImage img = m_queue->popImage();
            if (!img.isNull()) {
                m_lastImage = img;
                gotNewFrame = true;
            }
        }

        if (gotNewFrame) {
            m_lastPaintMs = QDateTime::currentMSecsSinceEpoch();

            const bool first = !m_hasFrame;
            m_hasFrame = true;

            QMetaObject::invokeMethod(this, [this, first, queueGeneration]() {
                if (queueGeneration != m_queueGeneration.load())
                    return;
                if (first)
                    emit hasFrameChanged();
                emit framePresented();
            }, Qt::QueuedConnection);
        }
    }

    if (!window() || m_lastImage.isNull())
        return oldNode;

    if (!node)
        node = new QSGSimpleTextureNode();

    QSGTexture* tex = window()->createTextureFromImage(m_lastImage);
    if (!tex)
        return node;

    node->setTexture(tex);
    node->setOwnsTexture(true);

    // Correct aspect ratio (letterbox)
    QRectF bounds = boundingRect();
    const float tileW = bounds.width();
    const float tileH = bounds.height();
    const float frameW = m_lastImage.width();
    const float frameH = m_lastImage.height();

    if (frameW > 0 && frameH > 0 && tileW > 0 && tileH > 0) {
        const float frameAspect = frameW / frameH;
        const float tileAspect = tileW / tileH;
        float renderW, renderH;

        if (frameAspect > tileAspect) {
            renderW = tileW;
            renderH = tileW / frameAspect;
        } else {
            renderH = tileH;
            renderW = tileH * frameAspect;
        }

        node->setRect(QRectF(
            (tileW - renderW) * 0.5f,
            (tileH - renderH) * 0.5f,
            renderW,
            renderH));
    }

    return node;
}