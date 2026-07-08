#include "FFmpegWorker.h"
#include <QDebug>
#include <QDateTime>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
}

FFmpegWorker::FFmpegWorker(QObject* parent)
    : QObject(parent)
{
    m_abort = false;
    m_testMode = false;

    static bool ffmpegInit = false;
    if (!ffmpegInit) {
        av_log_set_level(AV_LOG_ERROR);
        avformat_network_init();
        ffmpegInit = true;
    }
}

FFmpegWorker::~FFmpegWorker()
{
    // Owner calls stopDecoding()
}

void FFmpegWorker::setUrl(const QString& url)
{
    m_url = url;
}

void FFmpegWorker::setTestMode(bool enabled)
{
    m_testMode = enabled;
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

void FFmpegWorker::decodeLoop()
{
    qDebug() << "FFmpegWorker: starting, url =" << m_url;

    AVFormatContext* fmtCtx = nullptr;
    AVCodecContext* codecCtx = nullptr;
    SwsContext* sws = nullptr;
    AVFrame* frame = nullptr;
    AVFrame* outFrame = nullptr;

    AVDictionary* opts = nullptr;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    av_dict_set(&opts, "stimeout", "5000000", 0); // 5s timeout

    int ret = avformat_open_input(&fmtCtx, m_url.toUtf8().constData(), nullptr, &opts);
    av_dict_free(&opts);

    if (ret < 0) {
        qDebug() << "FFmpegWorker: open_input FAILED";
        emit streamError("Failed to open RTSP input");
        emit openInputFailed("Failed to open RTSP input");
        emit finished();
        return;
    }

    qDebug() << "FFmpegWorker: open_input OK";
    emit openInputOk();

    // ⭐ Make av_read_frame non-blocking so timeout and abort work
    if (fmtCtx)
        fmtCtx->flags |= AVFMT_FLAG_NONBLOCK;

    //
    // ⭐ TEST MODE — stop immediately after open_input
    //
    if (m_testMode) {
        if (fmtCtx)
            avformat_close_input(&fmtCtx);

        emit finished();
        qDebug() << "FFmpegWorker: test mode, exiting after open_input OK";
        return;
    }

    //
    // ⭐ Normal streaming path
    //
    ret = avformat_find_stream_info(fmtCtx, nullptr);
    if (ret < 0) {
        qDebug() << "FFmpegWorker: stream_info FAILED";
        emit streamError("Failed to find stream info");
        emit openInputFailed("Failed to find stream info");

        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    qDebug() << "FFmpegWorker: stream_info OK";

    int videoStreamIndex = -1;
    for (unsigned i = 0; i < fmtCtx->nb_streams; ++i) {
        if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStreamIndex = static_cast<int>(i);
            break;
        }
    }

    if (videoStreamIndex < 0) {
        qDebug() << "FFmpegWorker: no video stream";
        emit streamError("No video stream");
        emit openInputFailed("No video stream");

        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    AVStream* videoStream = fmtCtx->streams[videoStreamIndex];
    const AVCodec* codec = avcodec_find_decoder(videoStream->codecpar->codec_id);

    if (!codec) {
        qDebug() << "FFmpegWorker: decoder not found";
        emit streamError("Decoder not found");
        emit openInputFailed("Decoder not found");

        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    codecCtx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(codecCtx, videoStream->codecpar);

    ret = avcodec_open2(codecCtx, codec, nullptr);
    if (ret < 0) {
        qDebug() << "FFmpegWorker: codec open FAILED";
        emit streamError("Failed to open codec");
        emit openInputFailed("Failed to open codec");

        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    qDebug() << "FFmpegWorker: codec open OK";

    frame = av_frame_alloc();
    outFrame = av_frame_alloc();

    outFrame->format = AV_PIX_FMT_NV12;
    outFrame->width  = codecCtx->width;
    outFrame->height = codecCtx->height;

    if (av_frame_get_buffer(outFrame, 32) < 0) {
        qDebug() << "FFmpegWorker: output frame alloc FAILED";
        emit streamError("Failed to allocate output frame");
        emit openInputFailed("Failed to allocate output frame");

        av_frame_free(&frame);
        av_frame_free(&outFrame);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    sws = sws_getContext(codecCtx->width, codecCtx->height, codecCtx->pix_fmt,
                         codecCtx->width, codecCtx->height, AV_PIX_FMT_NV12,
                         SWS_BILINEAR, nullptr, nullptr, nullptr);

    if (!sws) {
        qDebug() << "FFmpegWorker: sws_getContext FAILED";
        emit streamError("Failed to create scaler");
        emit openInputFailed("Failed to create scaler");

        av_frame_free(&frame);
        av_frame_free(&outFrame);
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

    emit streamStarted();
    qDebug() << "FFmpegWorker: decode loop started";

    //
    // ⭐ FIRST FRAME TIMEOUT (2 seconds)
    //
    qint64 firstFrameDeadline = QDateTime::currentMSecsSinceEpoch() + 2000;
    bool firstFrameDecoded = false;

    while (!m_abort) {

        AVPacket pkt;
        av_init_packet(&pkt);

        ret = av_read_frame(fmtCtx, &pkt);

        //
        // ⭐ Timeout: no frames received
        //
        if (!firstFrameDecoded &&
            QDateTime::currentMSecsSinceEpoch() > firstFrameDeadline)
        {
            qDebug() << "FFmpegWorker: no frames received (timeout)";
            emit streamError("No frames received");
            emit openInputFailed("No frames received");
            m_abort = true;
            av_packet_unref(&pkt);
            break;
        }

        if (m_abort) {
            av_packet_unref(&pkt);
            break;
        }

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
            if (ret < 0)
                break;

            //
            // ⭐ First frame decoded → camera ONLINE
            //
            if (!firstFrameDecoded) {
                firstFrameDecoded = true;
                qDebug() << "FFmpegWorker: first frame decoded:"
                         << frame->width << "x" << frame->height;
            }

            sws_scale(sws,
                      frame->data,
                      frame->linesize,
                      0,
                      frame->height,
                      outFrame->data,
                      outFrame->linesize);

            AVFrame* cloned = av_frame_clone(outFrame);
            emit frameReady(cloned);
        }
    }

    qDebug() << "FFmpegWorker: decode loop exiting";

    if (sws) sws_freeContext(sws);
    if (frame) av_frame_free(&frame);
    if (outFrame) av_frame_free(&outFrame);
    if (codecCtx) avcodec_free_context(&codecCtx);
    if (fmtCtx) avformat_close_input(&fmtCtx);

    emit streamStopped();
    emit finished();
    qDebug() << "FFmpegWorker: finished";
}
