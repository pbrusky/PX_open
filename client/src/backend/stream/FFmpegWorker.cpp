#include "FFmpegWorker.h"
#include "FrameQueue.h"

#include <QDebug>
#include <QDateTime>

extern "C" {
#include <libavutil/error.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
}

static enum AVPixelFormat g_hwPixFmt = AV_PIX_FMT_NONE;

static enum AVPixelFormat get_hw_format(AVCodecContext *ctx,
                                        const enum AVPixelFormat *pix_fmts)
{
    Q_UNUSED(ctx);
    for (const enum AVPixelFormat *p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == g_hwPixFmt)
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

bool FFmpegWorker::initHwDevice(AVCodecContext* ctx, AVCodecID codecId)
{
    if (codecId != AV_CODEC_ID_HEVC) {
        qDebug() << "[FFmpegWorker] Not HEVC – using software decoder";
        return false;
    }

    const char* candidates[] = { "d3d11va", "dxva2", nullptr };

    for (int i = 0; candidates[i]; ++i) {
        AVHWDeviceType type = av_hwdevice_find_type_by_name(candidates[i]);
        if (type == AV_HWDEVICE_TYPE_NONE)
            continue;

        if (m_hwDeviceCtx) {
            av_buffer_unref(&m_hwDeviceCtx);
            m_hwDeviceCtx = nullptr;
        }

        int ret = av_hwdevice_ctx_create(&m_hwDeviceCtx, type, nullptr, nullptr, 0);
        if (ret < 0)
            continue;

        ctx->hw_device_ctx = av_buffer_ref(m_hwDeviceCtx);

        for (int j = 0; ; ++j) {
            const AVCodecHWConfig* config = avcodec_get_hw_config(ctx->codec, j);
            if (!config)
                break;

            if ((config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX) &&
                config->device_type == type)
            {
                g_hwPixFmt = config->pix_fmt;
                ctx->get_format = get_hw_format;
                qDebug() << "[FFmpegWorker] Using hardware acceleration for HEVC:" << candidates[i];
                return true;
            }
        }
    }

    qDebug() << "[FFmpegWorker] HEVC hardware acceleration not available – using software";
    return false;
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
    m_resolution = QString::number(codecCtx->width) + "x" +
                   QString::number(codecCtx->height);

    if (videoStream &&
        videoStream->avg_frame_rate.num > 0 &&
        videoStream->avg_frame_rate.den > 0)
    {
        m_fps = double(videoStream->avg_frame_rate.num) /
                double(videoStream->avg_frame_rate.den);
    } else {
        m_fps = 0.0;
    }

    int64_t br = codecCtx->bit_rate;
    if (br <= 0 && fmtCtx && fmtCtx->bit_rate > 0)
        br = fmtCtx->bit_rate;

    m_bitrateKbps = br > 0 ? int(br / 1000) : 0;

    if (codecCtx && codecCtx->codec && codecCtx->codec->name)
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
    av_dict_set(&opts, "probesize", "32768", 0);
    av_dict_set(&opts, "analyzeduration", "0", 0);
    av_dict_set(&opts, "fflags", "discardcorrupt", 0);
    av_dict_set(&opts, "max_delay", "500000", 0);

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

    emit openInputOk();

    if (m_testMode) {
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    ret = avformat_find_stream_info(fmtCtx, nullptr);
    if (ret < 0) {
        char errbuf[256];
        av_strerror(ret, errbuf, sizeof(errbuf));
        emit openInputFailed(QString("Failed to find stream info: %1").arg(errbuf));
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
    const AVCodec* codec = avcodec_find_decoder(videoStream->codecpar->codec_id);

    codecCtx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(codecCtx, videoStream->codecpar);

    codecCtx->flags |= AV_CODEC_FLAG_LOW_DELAY;
    codecCtx->err_recognition = AV_EF_CAREFUL;
    codecCtx->thread_count = 0;
    codecCtx->thread_type = FF_THREAD_FRAME;

    bool hwOk = initHwDevice(codecCtx, videoStream->codecpar->codec_id);

    ret = avcodec_open2(codecCtx, codec, nullptr);
    if (ret < 0) {
        char errbuf[256];
        av_strerror(ret, errbuf, sizeof(errbuf));
        emit openInputFailed(QString("Failed to open codec: %1").arg(errbuf));
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    updateStats(fmtCtx, codecCtx, videoStream);

    frame = av_frame_alloc();
    swFrame = av_frame_alloc();

    emit streamStarted();

    qint64 lastStatsMs = QDateTime::currentMSecsSinceEpoch();
    int lastSrcW = 0, lastSrcH = 0, lastDstW = 0, lastDstH = 0;
    int consecutiveErrors = 0;

    // Grid = low res, Fullscreen primary = high res
    const int kMaxOutW = m_highQuality ? 1920 : 640;
    const int kMaxOutH = m_highQuality ? 1080 : 360;

    while (!m_abort) {
        AVPacket pkt;
        av_init_packet(&pkt);

        ret = av_read_frame(fmtCtx, &pkt);
        if (ret < 0) {
            av_packet_unref(&pkt);
            break;
        }

        if (pkt.stream_index != videoStreamIndex) {
            av_packet_unref(&pkt);
            continue;
        }

        ret = avcodec_send_packet(codecCtx, &pkt);
        av_packet_unref(&pkt);

        if (ret < 0) {
            consecutiveErrors++;
            if (consecutiveErrors > 30)
                break;
            continue;
        }

        while (!m_abort) {
            ret = avcodec_receive_frame(codecCtx, frame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                break;
            if (ret < 0) {
                consecutiveErrors++;
                continue;
            }

            consecutiveErrors = 0;
            AVFrame* srcFrame = frame;

            if (hwOk && frame->format == g_hwPixFmt) {
                if (av_hwframe_transfer_data(swFrame, frame, 0) < 0)
                    continue;
                srcFrame = swFrame;
            }

            if (srcFrame->width <= 16 || srcFrame->height <= 16)
                continue;

            int dstW = srcFrame->width;
            int dstH = srcFrame->height;

            if (dstW > kMaxOutW || dstH > kMaxOutH) {
                const float scale = qMin(float(kMaxOutW) / float(dstW),
                                         float(kMaxOutH) / float(dstH));
                dstW = int(dstW * scale);
                dstH = int(dstH * scale);
            }

            dstW &= ~1;
            dstH &= ~1;
            if (dstW < 2 || dstH < 2)
                continue;

            qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
            if (nowMs - lastStatsMs > 1000) {
                lastStatsMs = nowMs;
                updateStats(fmtCtx, codecCtx, videoStream);
            }

            if (!rgbSws ||
                lastSrcW != srcFrame->width || lastSrcH != srcFrame->height ||
                lastDstW != dstW || lastDstH != dstH)
            {
                if (rgbSws)
                    sws_freeContext(rgbSws);

                rgbSws = sws_getContext(
                    srcFrame->width, srcFrame->height,
                    (AVPixelFormat)srcFrame->format,
                    dstW, dstH,
                    AV_PIX_FMT_BGRA,
                    SWS_FAST_BILINEAR, nullptr, nullptr, nullptr
                );

                lastSrcW = srcFrame->width;
                lastSrcH = srcFrame->height;
                lastDstW = dstW;
                lastDstH = dstH;
            }

            if (!rgbSws)
                continue;

            QImage img(dstW, dstH, QImage::Format_RGB32);
            if (img.isNull())
                continue;

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
        }
    }

    if (rgbSws) sws_freeContext(rgbSws);
    if (frame) av_frame_free(&frame);
    if (swFrame) av_frame_free(&swFrame);
    if (codecCtx) avcodec_free_context(&codecCtx);
    if (fmtCtx) avformat_close_input(&fmtCtx);
    if (m_hwDeviceCtx) av_buffer_unref(&m_hwDeviceCtx);

    emit streamStopped();
    emit finished();
}