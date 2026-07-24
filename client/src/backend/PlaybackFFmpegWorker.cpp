#include "PlaybackFFmpegWorker.h"
#include <QDebug>

PlaybackFFmpegWorker::PlaybackFFmpegWorker(QObject* parent)
    : QObject(parent),
      m_abort(false)
{
}

PlaybackFFmpegWorker::~PlaybackFFmpegWorker()
{
    stop();
    closeInput();
}

void PlaybackFFmpegWorker::setFile(const QString& path)
{
    m_filePath = path;
}

void PlaybackFFmpegWorker::seekToMs(qint64 timestampMs)
{
    m_seekTargetMs = timestampMs;
}

void PlaybackFFmpegWorker::start()
{
    m_abort = false;
    decodeLoop();
}

void PlaybackFFmpegWorker::stop()
{
    m_abort = true;
}

bool PlaybackFFmpegWorker::openInput()
{
    if (m_filePath.isEmpty()) {
        qWarning() << "[PlaybackFFmpegWorker] No file path set";
        return false;
    }

    if (avformat_open_input(&fmtCtx, m_filePath.toUtf8().constData(), nullptr, nullptr) < 0) {
        qWarning() << "[PlaybackFFmpegWorker] Failed to open file";
        return false;
    }

    if (avformat_find_stream_info(fmtCtx, nullptr) < 0) {
        qWarning() << "[PlaybackFFmpegWorker] Failed to find stream info";
        return false;
    }

    for (unsigned i = 0; i < fmtCtx->nb_streams; ++i) {
        if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStreamIndex = i;
            videoStream = fmtCtx->streams[i];
            break;
        }
    }

    if (videoStreamIndex < 0) {
        qWarning() << "[PlaybackFFmpegWorker] No video stream found";
        return false;
    }

    const AVCodec* codec = avcodec_find_decoder(videoStream->codecpar->codec_id);
    if (!codec) {
        qWarning() << "[PlaybackFFmpegWorker] No decoder found";
        return false;
    }

    codecCtx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(codecCtx, videoStream->codecpar);

    if (avcodec_open2(codecCtx, codec, nullptr) < 0) {
        qWarning() << "[PlaybackFFmpegWorker] Failed to open codec";
        return false;
    }

    return true;
}

void PlaybackFFmpegWorker::closeInput()
{
    if (codecCtx) {
        avcodec_free_context(&codecCtx);
        codecCtx = nullptr;
    }

    if (fmtCtx) {
        avformat_close_input(&fmtCtx);
        fmtCtx = nullptr;
    }
}

void PlaybackFFmpegWorker::decodeLoop()
{
    if (!openInput()) {
        emit finished();
        return;
    }

    AVPacket* pkt = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();

    while (!m_abort)
    {
        // SEEK REQUEST?
        if (m_seekTargetMs >= 0) {
            int64_t ts = m_seekTargetMs * (videoStream->time_base.den / 1000.0)
                         / videoStream->time_base.num;

            avformat_seek_file(fmtCtx, videoStreamIndex, ts, ts, ts, 0);
            avcodec_flush_buffers(codecCtx);

            m_seekTargetMs = -1;
        }

        if (av_read_frame(fmtCtx, pkt) < 0)
            break;

        if (pkt->stream_index != videoStreamIndex) {
            av_packet_unref(pkt);
            continue;
        }

        if (avcodec_send_packet(codecCtx, pkt) < 0) {
            av_packet_unref(pkt);
            continue;
        }

        while (avcodec_receive_frame(codecCtx, frame) == 0) {
            int64_t pts = frame->pts;
            double ms = pts * av_q2d(videoStream->time_base) * 1000.0;

            emit playbackPositionChanged(ms);
            emit frameReady(frame);
        }

        av_packet_unref(pkt);
    }

    av_frame_free(&frame);
    av_packet_free(&pkt);

    closeInput();
    emit finished();
}
