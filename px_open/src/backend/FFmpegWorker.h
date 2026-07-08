#ifndef FFMPEGWORKER_H
#define FFMPEGWORKER_H

#include <QObject>
#include <QString>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
}

class FFmpegWorker : public QObject
{
    Q_OBJECT

public:
    explicit FFmpegWorker(QObject* parent = nullptr);
    ~FFmpegWorker() override;

    void setUrl(const QString& url);

    // ⭐ FIXED — declaration only (no inline body)
    void setTestMode(bool test);

    void startDecoding();
    void stopDecoding();

signals:
    // Streaming
    void frameReady(AVFrame* frame);
    void streamStarted();
    void streamStopped();
    void streamError(QString reason);
    void finished();

    // RTSP test
    void openInputOk();
    void openInputFailed(QString reason);

private:
    void decodeLoop();

    QString m_url;
    bool m_abort = false;
    bool m_testMode = false;   // ⭐ normal vs test
};

#endif // FFMPEGWORKER_H
