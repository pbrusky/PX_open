#include "FFmpegWorker.h"
#include "FrameQueue.h"

#include <QDebug>
#include <QDateTime>
#include <QThread>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

extern "C" {
#include <libavutil/error.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
}

static enum AVPixelFormat get_hw_format(AVCodecContext* ctx,
                                        const enum AVPixelFormat* pix_fmts)
{
    FFmpegWorker* self = static_cast<FFmpegWorker*>(ctx->opaque);
    if (!self)
        return AV_PIX_FMT_NONE;

    const AVPixelFormat target = self->hwPixFmt();
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == target)
            return *p;
    }
    return AV_PIX_FMT_NONE;
}

FFmpegWorker::FFmpegWorker(QObject* parent)
    : QObject(parent)
{
    static bool ffmpegInit = false;
    if (!ffmpegInit) {
        av_log_set_level(AV_LOG_ERROR);
        avformat_network_init();
        ffmpegInit = true;
    }
}

FFmpegWorker::~FFmpegWorker()
{
    m_abort = true;
    clearHw();
}

void FFmpegWorker::setUrl(const QString& url)
{
    m_url = url;
}

void FFmpegWorker::setTestMode(bool enabled)
{
    m_testMode = enabled;
}

void FFmpegWorker::setFrameQueue(FrameQueue* queue)
{
    m_queue = queue;
}

void FFmpegWorker::setHighQuality(bool enabled)
{
    m_highQuality = enabled;
}

void FFmpegWorker::clearHw()
{
    if (m_hwDeviceCtx) {
        av_buffer_unref(&m_hwDeviceCtx);
        m_hwDeviceCtx = nullptr;
    }
    m_hwPixFmt = AV_PIX_FMT_NONE;
}

bool FFmpegWorker::initHwDevice(AVCodecContext* ctx)
{
#ifdef Q_OS_WIN
    const char* candidates[] = { "d3d11va", "dxva2", "cuda", "qsv", nullptr };
#else
    const char* candidates[] = { "vaapi", "cuda", "vdpau", nullptr };
#endif

    ctx->opaque = this;

    for (int i = 0; candidates[i]; ++i) {
        AVHWDeviceType type = av_hwdevice_find_type_by_name(candidates[i]);
        if (type == AV_HWDEVICE_TYPE_NONE)
            continue;

        clearHw();

        int ret = av_hwdevice_ctx_create(&m_hwDeviceCtx, type, nullptr, nullptr, 0);
        if (ret < 0)
            continue;

        AVPixelFormat foundFmt = AV_PIX_FMT_NONE;
        for (int j = 0; ; ++j) {
            const AVCodecHWConfig* config = avcodec_get_hw_config(ctx->codec, j);
            if (!config)
                break;

            if ((config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX) &&
                config->device_type == type) {
                foundFmt = config->pix_fmt;
                break;
            }
        }

        if (foundFmt == AV_PIX_FMT_NONE) {
            clearHw();
            continue;
        }

        m_hwPixFmt = foundFmt;
        ctx->hw_device_ctx = av_buffer_ref(m_hwDeviceCtx);
        ctx->get_format = get_hw_format;

        qDebug() << "[FFmpegWorker] HW decode enabled:"
                 << candidates[i]
                 << "codec:" << (ctx->codec ? ctx->codec->name : "?");
        return true;
    }

    clearHw();
    ctx->hw_device_ctx = nullptr;
    ctx->get_format = nullptr;
    ctx->opaque = nullptr;
    return false;
}

bool FFmpegWorker::openCodec(AVCodecContext** pCtx,
                             const AVCodec* codec,
                             AVCodecParameters* params,
                             bool tryHw)
{
    if (*pCtx) {
        avcodec_free_context(pCtx);
        *pCtx = nullptr;
    }

    clearHw();

    AVCodecContext* ctx = avcodec_alloc_context3(codec);
    if (!ctx)
        return false;

    avcodec_parameters_to_context(ctx, params);
    ctx->flags |= AV_CODEC_FLAG_LOW_DELAY;
    ctx->flags2 |= AV_CODEC_FLAG2_SHOW_ALL;
    ctx->err_recognition = AV_EF_CAREFUL | AV_EF_IGNORE_ERR;
    ctx->thread_count = tryHw ? 1 : qMin(4, QThread::idealThreadCount());
    ctx->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;

    bool hwOk = false;
    if (tryHw)
        hwOk = initHwDevice(ctx);

    int ret = avcodec_open2(ctx, codec, nullptr);
    if (ret < 0) {
        clearHw();
        avcodec_free_context(&ctx);

        ctx = avcodec_alloc_context3(codec);
        if (!ctx)
            return false;

        avcodec_parameters_to_context(ctx, params);
        ctx->flags |= AV_CODEC_FLAG_LOW_DELAY;
        ctx->flags2 |= AV_CODEC_FLAG2_SHOW_ALL;
        ctx->err_recognition = AV_EF_CAREFUL | AV_EF_IGNORE_ERR;
        ctx->thread_count = qMin(4, QThread::idealThreadCount());
        ctx->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
        ctx->opaque = nullptr;
        ctx->get_format = nullptr;
        ctx->hw_device_ctx = nullptr;

        ret = avcodec_open2(ctx, codec, nullptr);
        if (ret < 0) {
            avcodec_free_context(&ctx);
            return false;
        }

        qDebug() << "[FFmpegWorker] Software decoder (open fallback)"
                 << "codec:" << (codec ? codec->name : "?");
        *pCtx = ctx;
        return true;
    }

    if (!hwOk) {
        qDebug() << "[FFmpegWorker] Software decoder"
                 << "codec:" << (codec ? codec->name : "?");
    }

    *pCtx = ctx;
    return true;
}

void FFmpegWorker::startDecoding()
{
    m_abort = false;
    decodeLoop();
}

void FFmpegWorker::stopDecoding()
{
    m_abort = true;
}

void FFmpegWorker::updateStats(AVFormatContext* fmtCtx,
                               AVCodecContext* codecCtx,
                               AVStream* videoStream)
{
    if (!codecCtx)
        return;

    m_resolution = QString::number(codecCtx->width) + "x" +
                   QString::number(codecCtx->height);

    if (videoStream &&
        videoStream->avg_frame_rate.num > 0 &&
        videoStream->avg_frame_rate.den > 0) {
        m_fps = double(videoStream->avg_frame_rate.num) /
                double(videoStream->avg_frame_rate.den);
    } else {
        m_fps = 0.0;
    }

    int64_t br = codecCtx->bit_rate;
    if (br <= 0 && fmtCtx && fmtCtx->bit_rate > 0)
        br = fmtCtx->bit_rate;

    m_bitrateKbps = br > 0 ? int(br / 1000) : 0;

    if (codecCtx->codec && codecCtx->codec->name)
        m_codec = QString::fromUtf8(codecCtx->codec->name);
    else
        m_codec.clear();

    emit statsChanged();
}

void FFmpegWorker::decodeLoop()
{
    AVFormatContext* fmtCtx = nullptr;
    AVCodecContext* codecCtx = nullptr;
    AVFrame* frame = nullptr;
    AVFrame* swFrame = nullptr;
    SwsContext* rgbSws = nullptr;

    AVDictionary* opts = nullptr;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    av_dict_set(&opts, "rtsp_flags", "prefer_tcp", 0);
    // Faster open / faster 404 on missing *_main
    av_dict_set(&opts, "probesize", "200000", 0);
    av_dict_set(&opts, "analyzeduration", "500000", 0);
    av_dict_set(&opts, "fflags", "discardcorrupt+nobuffer+genpts", 0);
    av_dict_set(&opts, "flags", "low_delay", 0);
    av_dict_set(&opts, "max_delay", "250000", 0);
    av_dict_set(&opts, "stimeout", "2000000", 0);   // 2s (was 8s)
    av_dict_set(&opts, "rw_timeout", "2000000", 0);  // 2s (was 8s)

    int ret = avformat_open_input(&fmtCtx, m_url.toUtf8().constData(), nullptr, &opts);
    av_dict_free(&opts);

    if (ret < 0) {
        char errbuf[256];
        av_strerror(ret, errbuf, sizeof(errbuf));
        emit openInputFailed(QString("Failed to open RTSP input: %1").arg(errbuf));
        emit finished();
        return;
    }

    fmtCtx->flags |= AVFMT_FLAG_GENPTS;
    fmtCtx->flags |= AVFMT_FLAG_DISCARD_CORRUPT;
    fmtCtx->max_analyze_duration = AV_TIME_BASE / 2;  // 0.5s (was 2s)

    emit openInputOk();

    if (m_testMode) {
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    ret = avformat_find_stream_info(fmtCtx, nullptr);
    if (ret < 0) {
        emit openInputFailed("Failed to find stream info");
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    int videoStreamIndex = -1;
    for (unsigned i = 0; i < fmtCtx->nb_streams; ++i) {
        if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStreamIndex = int(i);
            break;
        }
    }

    if (videoStreamIndex < 0) {
        emit openInputFailed("No video stream");
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    AVStream* videoStream = fmtCtx->streams[videoStreamIndex];
    AVCodecParameters* params = videoStream->codecpar;
    const AVCodec* codec = avcodec_find_decoder(params->codec_id);
    if (!codec) {
        emit openInputFailed("Decoder not found");
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    // Grid (hq=false): software only → stable multi-camera tiles
    // Fullscreen (hq=true): try HW, then fast software fallback
    const bool tryHw = m_highQuality;

    if (!openCodec(&codecCtx, codec, params, tryHw)) {
        emit openInputFailed("Failed to open codec");
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    const bool usingHwInitial = (codecCtx->hw_device_ctx != nullptr);

    qDebug() << "[FFmpegWorker] Decoder started codec:"
             << (codec->name ? codec->name : "?")
             << "size:" << codecCtx->width << "x" << codecCtx->height
             << "hq:" << m_highQuality
             << "hw:" << usingHwInitial;

    frame = av_frame_alloc();
    swFrame = av_frame_alloc();
    if (!frame || !swFrame) {
        if (frame) av_frame_free(&frame);
        if (swFrame) av_frame_free(&swFrame);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    AVPacket* packet = av_packet_alloc();
    if (!packet) {
        av_frame_free(&frame);
        av_frame_free(&swFrame);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    bool usingHw = usingHwInitial;
    int goodFrames = 0;
    int packetsSinceStart = 0;
    int lastSrcW = 0, lastSrcH = 0, lastDstW = 0, lastDstH = 0;
    qint64 lastStatsMs = 0;

    auto switchToSoftware = [&](const char* reason) -> bool {
        if (!usingHw)
            return false;

        qWarning() << "[FFmpegWorker]" << reason << "→ software fallback";

        usingHw = false;
        goodFrames = 0;
        packetsSinceStart = 0;

        if (!openCodec(&codecCtx, codec, params, false)) {
            qWarning() << "[FFmpegWorker] software fallback open failed";
            return false;
        }
        return true;
    };

    // Output caps: grid ~640, fullscreen ~1920
    const int kMaxOutW = m_highQuality ? 1920 : 640;
    const int kMaxOutH = m_highQuality ? 1080 : 360;

    while (!m_abort) {
        ret = av_read_frame(fmtCtx, packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN)) {
                QThread::msleep(5);
                continue;
            }
            break;
        }

        if (packet->stream_index != videoStreamIndex) {
            av_packet_unref(packet);
            continue;
        }

        packetsSinceStart++;

        ret = avcodec_send_packet(codecCtx, packet);
        av_packet_unref(packet);

        if (ret < 0) {
            if (usingHw && packetsSinceStart > 8) {
                if (!switchToSoftware("HW send_packet failing"))
                    break;
            }
            continue;
        }

        while (!m_abort) {
            ret = avcodec_receive_frame(codecCtx, frame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                break;
            if (ret < 0) {
                if (usingHw) {
                    if (!switchToSoftware("HW receive_frame failing"))
                        break;
                    continue;
                }
                break;
            }

            AVFrame* srcFrame = frame;

            if (usingHw && frame->format == m_hwPixFmt) {
                ret = av_hwframe_transfer_data(swFrame, frame, 0);
                if (ret < 0) {
                    av_frame_unref(frame);
                    if (!switchToSoftware("HW transfer failing"))
                        break;
                    continue;
                }
                srcFrame = swFrame;
            }

            goodFrames++;

            int dstW = srcFrame->width;
            int dstH = srcFrame->height;

            if (dstW > kMaxOutW || dstH > kMaxOutH) {
                const float scale = qMin(float(kMaxOutW) / float(dstW),
                                         float(kMaxOutH) / float(dstH));
                dstW = int(dstW * scale) & ~1;
                dstH = int(dstH * scale) & ~1;
            }

            if (dstW < 2 || dstH < 2) {
                av_frame_unref(frame);
                continue;
            }

            qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
            if (nowMs - lastStatsMs > 1000) {
                lastStatsMs = nowMs;
                updateStats(fmtCtx, codecCtx, videoStream);
            }

            if (!rgbSws ||
                lastSrcW != srcFrame->width || lastSrcH != srcFrame->height ||
                lastDstW != dstW || lastDstH != dstH) {
                if (rgbSws)
                    sws_freeContext(rgbSws);

                rgbSws = sws_getContext(
                    srcFrame->width, srcFrame->height,
                    (AVPixelFormat)srcFrame->format,
                    dstW, dstH,
                    AV_PIX_FMT_BGRA,
                    SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);

                lastSrcW = srcFrame->width;
                lastSrcH = srcFrame->height;
                lastDstW = dstW;
                lastDstH = dstH;
            }

            if (!rgbSws) {
                av_frame_unref(frame);
                continue;
            }

            QImage img(dstW, dstH, QImage::Format_RGB32);
            if (img.isNull()) {
                av_frame_unref(frame);
                continue;
            }

            uint8_t* dest[4] = { img.bits(), nullptr, nullptr, nullptr };
            int destStride[4] = { int(img.bytesPerLine()), 0, 0, 0 };

            sws_scale(rgbSws,
                      srcFrame->data,
                      srcFrame->linesize,
                      0,
                      srcFrame->height,
                      dest,
                      destStride);

            if (m_queue && !img.isNull() && img.width() > 16 && img.height() > 16)
                m_queue->pushImage(img);

            av_frame_unref(frame);
        }

        // No picture after enough packets while still on HW
        if (usingHw && goodFrames == 0 && packetsSinceStart >= 12) {
            switchToSoftware("HW produced 0 frames");
        }
    }

    av_packet_free(&packet);
    if (rgbSws)
        sws_freeContext(rgbSws);
    if (frame)
        av_frame_free(&frame);
    if (swFrame)
        av_frame_free(&swFrame);
    if (codecCtx)
        avcodec_free_context(&codecCtx);
    if (fmtCtx)
        avformat_close_input(&fmtCtx);

    clearHw();

    emit streamStopped();
    emit finished();
}