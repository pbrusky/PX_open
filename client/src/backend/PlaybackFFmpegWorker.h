#ifndef PLAYBACKFFMPEGWORKER_H
#define PLAYBACKFFMPEGWORKER_H

#include <QObject>
#include <QThread>
#include <QAtomicInt>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
}

class PlaybackFFmpegWorker : public QObject
{
    Q_OBJECT

public:
    explicit PlaybackFFmpegWorker(QObject* parent = nullptr);
    ~PlaybackFFmpegWorker();

    void setFile(const QString& path);
    void seekToMs(qint64 timestampMs);
    void start();
    void stop();

signals:
    void frameReady(AVFrame* frame);
    void playbackPositionChanged(qint64 positionMs);
    void finished();

private:
    void decodeLoop();
    bool openInput();
    void closeInput();

    QString m_filePath;
    qint64 m_seekTargetMs = -1;

    AVFormatContext* fmtCtx = nullptr;
    AVCodecContext* codecCtx = nullptr;
    AVStream* videoStream = nullptr;
    int videoStreamIndex = -1;

    QAtomicInt m_abort;
};

#endif // PLAYBACKFFMPEGWORKER_H
