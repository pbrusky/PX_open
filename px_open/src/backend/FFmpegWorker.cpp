#include "FFmpegWorker.h"
#include "FrameQueue.h"

#include <QDebug>
#include <QDateTime>

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
    av_dict_set(&opts, "stimeout", "5000000", 0);

    int ret = avformat_open_input(&fmtCtx, m_url.toUtf8().constData(), nullptr, &opts);
    av_dict_free(&opts);

    if (ret < 0) {
        emit openInputFailed("Failed to open RTSP input");
        emit finished();
        return;
    }

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
            videoStreamIndex = i;
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

    ret = avcodec_open2(codecCtx, codec, nullptr);
    if (ret < 0) {
        emit openInputFailed("Failed to open codec");
        avcodec_free_context(&codecCtx);
        avformat_close_input(&fmtCtx);
        emit finished();
        return;
    }

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

            sws_scale(sws,
                      frame->data,
                      frame->linesize,
                      0,
                      frame->height,
                      outFrame->data,
                      outFrame->linesize);

            // Convert NV12 → QImage (BGRA)
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

            if (m_queue) {
                m_queue->pushImage(img);
            }
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
