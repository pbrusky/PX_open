#include "FFmpegWorker.h"
#include "FrameQueue.h"

#include <QDebug>
#include <QDateTime>

extern "C" {
#include <libavutil/error.h>
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
    SwsContext* sws = nullptr;
    AVFrame* frame = nullptr;
    AVFrame* outFrame = nullptr;

    AVDictionary* opts = nullptr;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);

    // Low-latency input tuning
    av_dict_set(&opts, "probesize", "32768", 0);
    av_dict_set(&opts, "analyzeduration", "0", 0);

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

    // Low-latency but HEVC-safe
    codecCtx->flags |= AV_CODEC_FLAG_LOW_DELAY;

    // Tolerate minor bitstream errors (helps with imperfect HEVC streams)
    codecCtx->err_recognition = AV_EF_IGNORE_ERR;

    // Do NOT force max_b_frames = 0 here; it breaks HEVC
    // codecCtx->max_b_frames = 0;  // removed

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
    outFrame = av_frame_alloc();

    outFrame->format = AV_PIX_FMT_NV12;
    outFrame->width  = codecCtx->width;
    outFrame->height = codecCtx->height;

    av_frame_get_buffer(outFrame, 32);

    sws = sws_getContext(codecCtx->width, codecCtx->height, codecCtx->pix_fmt,
                         codecCtx->width, codecCtx->height, AV_PIX_FMT_NV12,
                         SWS_BILINEAR, nullptr, nullptr, nullptr);

    emit streamStarted();

    qint64 lastStatsMs = QDateTime::currentMSecsSinceEpoch();

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

        if (ret < 0)
            continue;

        while (!m_abort) {

            ret = avcodec_receive_frame(codecCtx, frame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                break;

            qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
            if (nowMs - lastStatsMs > 1000) {
                lastStatsMs = nowMs;
                updateStats(fmtCtx, codecCtx, videoStream);
            }

            sws_scale(sws,
                      frame->data,
                      frame->linesize,
                      0,
                      frame->height,
                      outFrame->data,
                      outFrame->linesize);

            QImage img(codecCtx->width, codecCtx->height, QImage::Format_RGB32);

            SwsContext* rgbSws = sws_getContext(
                codecCtx->width, codecCtx->height, AV_PIX_FMT_NV12,
                codecCtx->width, codecCtx->height, AV_PIX_FMT_BGRA,
                SWS_BILINEAR, nullptr, nullptr, nullptr
            );

            uint8_t* dest[4] = { img.bits(), nullptr, nullptr, nullptr };
            int destStride[4] = { img.bytesPerLine(), 0, 0, 0 };

            sws_scale(rgbSws,
                      outFrame->data,
                      outFrame->linesize,
                      0,
                      outFrame->height,
                      dest,
                      destStride);

            sws_freeContext(rgbSws);

            if (m_queue)
                m_queue->pushImage(img);
        }
    }

    if (sws) sws_freeContext(sws);
    if (frame) av_frame_free(&frame);
    if (outFrame) av_frame_free(&outFrame);
    if (codecCtx) avcodec_free_context(&codecCtx);
    if (fmtCtx) avformat_close_input(&fmtCtx);

    emit streamStopped();
    emit finished();
}
