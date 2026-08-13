#include "FFmpegWorker.h"
#include "FrameQueue.h"

#include <QDateTime>
#include <QThread>

extern "C" {
#include <libavutil/error.h>
#include <libavutil/mathematics.h>
#include <libavutil/pixfmt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
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
    m_abort.store(true);
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
    Q_UNUSED(ctx);
    clearHw();
    return false;
}

int FFmpegWorker::decodeInterruptCb(void* opaque)
{
    FFmpegWorker* self = static_cast<FFmpegWorker*>(opaque);
    if (!self)
        return 0;
    return self->m_abort.load() ? 1 : 0;
}

bool FFmpegWorker::openCodec(AVCodecContext** codecCtx,
                             const AVCodec* codec,
                             AVCodecParameters* params,
                             bool tryHw)
{
    Q_UNUSED(tryHw);

    *codecCtx = avcodec_alloc_context3(codec);
    if (!*codecCtx)
        return false;

    if (avcodec_parameters_to_context(*codecCtx, params) < 0) {
        avcodec_free_context(codecCtx);
        return false;
    }

    (*codecCtx)->flags  |= AV_CODEC_FLAG_LOW_DELAY;
    (*codecCtx)->flags2 |= AV_CODEC_FLAG2_FAST;
    (*codecCtx)->thread_count = 2;

    if (avcodec_open2(*codecCtx, codec, nullptr) < 0) {
        avcodec_free_context(codecCtx);
        return false;
    }

    return true;
}

void FFmpegWorker::updateStats(AVFormatContext* fmtCtx,
                               AVCodecContext* codecCtx,
                               AVStream* videoStream)
{
    if (!codecCtx)
        return;

    m_resolution = QString::number(codecCtx->width) + QLatin1Char('x')
                 + QString::number(codecCtx->height);

    if (videoStream &&
        videoStream->avg_frame_rate.num > 0 &&
        videoStream->avg_frame_rate.den > 0) {
        m_fps = double(videoStream->avg_frame_rate.num)
              / double(videoStream->avg_frame_rate.den);
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
    emit statsUpdated(m_resolution, m_fps, m_bitrateKbps, m_codec);
}

void FFmpegWorker::startDecoding()
{
    m_abort.store(false);
    decodeLoop();
}

void FFmpegWorker::stopDecoding()
{
    m_abort.store(true);
    m_queue = nullptr;
}

void FFmpegWorker::decodeLoop()
{
    if (m_url.isEmpty()) {
        emit openInputFailed(QStringLiteral("Empty URL"));
        emit finished();
        return;
    }

    const bool isHttp = m_url.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)
                     || m_url.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive);

    AVFormatContext* fmtCtx = avformat_alloc_context();
    if (!fmtCtx) {
        emit openInputFailed(QStringLiteral("alloc context failed"));
        emit finished();
        return;
    }

    fmtCtx->interrupt_callback.callback = &FFmpegWorker::decodeInterruptCb;
    fmtCtx->interrupt_callback.opaque = this;

    AVDictionary* opts = nullptr;
    if (isHttp) {
        av_dict_set(&opts, "rw_timeout", "8000000", 0);
        av_dict_set(&opts, "timeout", "8000000", 0);
        av_dict_set(&opts, "reconnect", "0", 0);
        av_dict_set(&opts, "probesize", "1000000", 0);
        av_dict_set(&opts, "analyzeduration", "1000000", 0);
    } else {
        av_dict_set(&opts, "rtsp_transport", "tcp", 0);
        av_dict_set(&opts, "stimeout", "5000000", 0);
        av_dict_set(&opts, "rw_timeout", "5000000", 0);
        av_dict_set(&opts, "probesize", "100000", 0);
        av_dict_set(&opts, "analyzeduration", "300000", 0);
        av_dict_set(&opts, "fflags", "nobuffer", 0);
        av_dict_set(&opts, "flags", "low_delay", 0);
        av_dict_set(&opts, "max_delay", "0", 0);
    }

    const QByteArray urlBytes = m_url.toUtf8();
    int ret = avformat_open_input(&fmtCtx, urlBytes.constData(), nullptr, &opts);
    av_dict_free(&opts);

    if (ret < 0 || m_abort.load()) {
        if (fmtCtx)
            avformat_close_input(&fmtCtx);
        if (!m_abort.load()) {
            char errbuf[256];
            av_strerror(ret, errbuf, sizeof(errbuf));
            emit openInputFailed(QString::fromUtf8(errbuf));
        }
        emit finished();
        return;
    }

    emit openInputOk();

    if (avformat_find_stream_info(fmtCtx, nullptr) < 0 || m_abort.load()) {
        avformat_close_input(&fmtCtx);
        if (!m_abort.load())
            emit openInputFailed(QStringLiteral("find_stream_info failed"));
        emit finished();
        return;
    }

    int videoIndex = -1;
    for (unsigned i = 0; i < fmtCtx->nb_streams; ++i) {
        if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoIndex = int(i);
            break;
        }
    }

    if (videoIndex < 0) {
        avformat_close_input(&fmtCtx);
        emit openInputFailed(QStringLiteral("No video stream"));
        emit finished();
        return;
    }

    AVStream* videoStream = fmtCtx->streams[videoIndex];
    AVCodecParameters* params = videoStream->codecpar;
    const AVCodec* codec = avcodec_find_decoder(params->codec_id);
    if (!codec) {
        avformat_close_input(&fmtCtx);
        emit openInputFailed(QStringLiteral("Decoder not found"));
        emit finished();
        return;
    }

    AVCodecContext* codecCtx = nullptr;
    if (!openCodec(&codecCtx, codec, params, false) || !codecCtx) {
        avformat_close_input(&fmtCtx);
        emit openInputFailed(QStringLiteral("Failed to open codec"));
        emit finished();
        return;
    }

    emit streamStarted();

    AVFrame* frame = av_frame_alloc();
    AVPacket* packet = av_packet_alloc();
    SwsContext* rgbSws = nullptr;

    int lastSrcW = 0, lastSrcH = 0, lastDstW = 0, lastDstH = 0;
    qint64 lastStatsMs = 0;
    bool statsSent = false;

    // Real-time pace for HTTP/file clips only (not live RTSP)
    qint64 playStartPtsMs = -1;
    qint64 playStartWallMs = 0;

    const int kMaxOutW = m_highQuality ? 3840 : 1280;
    const int kMaxOutH = m_highQuality ? 2160 : 720;

    while (!m_abort.load()) {
        ret = av_read_frame(fmtCtx, packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF)
                break;
            if (ret == AVERROR(EAGAIN)) {
                QThread::msleep(5);
                continue;
            }
            break;
        }

        if (packet->stream_index != videoIndex) {
            av_packet_unref(packet);
            continue;
        }

        ret = avcodec_send_packet(codecCtx, packet);
        av_packet_unref(packet);
        if (ret < 0)
            continue;

        while (ret >= 0 && !m_abort.load()) {
            ret = avcodec_receive_frame(codecCtx, frame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                break;
            if (ret < 0)
                break;

            int dstW = frame->width;
            int dstH = frame->height;

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

            if (!statsSent) {
                statsSent = true;
                updateStats(fmtCtx, codecCtx, videoStream);
                lastStatsMs = QDateTime::currentMSecsSinceEpoch();
            } else {
                const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
                if (nowMs - lastStatsMs > 1000) {
                    lastStatsMs = nowMs;
                    updateStats(fmtCtx, codecCtx, videoStream);
                }
            }

            if (!rgbSws ||
                lastSrcW != frame->width || lastSrcH != frame->height ||
                lastDstW != dstW || lastDstH != dstH) {
                if (rgbSws)
                    sws_freeContext(rgbSws);

                rgbSws = sws_getContext(
                    frame->width, frame->height,
                    static_cast<AVPixelFormat>(frame->format),
                    dstW, dstH,
                    AV_PIX_FMT_BGRA,
                    SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);

                lastSrcW = frame->width;
                lastSrcH = frame->height;
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
                      frame->data,
                      frame->linesize,
                      0,
                      frame->height,
                      dest,
                      destStride);

            // Pace HTTP/file playback to wall-clock time (fixes fast-forward)
            if (isHttp && !m_abort.load()) {
                int64_t pts = frame->best_effort_timestamp;
                if (pts == AV_NOPTS_VALUE)
                    pts = frame->pts;

                if (pts != AV_NOPTS_VALUE) {
                    const qint64 ptsMs = av_rescale_q(pts, videoStream->time_base, {1, 1000});
                    if (playStartPtsMs < 0) {
                        playStartPtsMs = ptsMs;
                        playStartWallMs = QDateTime::currentMSecsSinceEpoch();
                    } else {
                        const qint64 targetWall = playStartWallMs + (ptsMs - playStartPtsMs);
                        const qint64 delay = targetWall - QDateTime::currentMSecsSinceEpoch();
                        // Clamp: ignore tiny/jitter and huge jumps (gaps in recording)
                        if (delay > 2 && delay < 1500)
                            QThread::msleep(static_cast<unsigned long>(delay));
                    }
                } else {
                    // No PTS: ~30 fps fallback
                    QThread::msleep(33);
                }
            }

            if (m_queue && img.width() > 16 && img.height() > 16)
                m_queue->pushImage(img);

            av_frame_unref(frame);
        }
    }

    av_packet_free(&packet);
    if (rgbSws)
        sws_freeContext(rgbSws);
    if (frame)
        av_frame_free(&frame);
    if (codecCtx)
        avcodec_free_context(&codecCtx);
    if (fmtCtx)
        avformat_close_input(&fmtCtx);

    clearHw();

    emit streamStopped();
    emit finished();
}