#pragma once

#include <QObject>
#include <QString>
#include <QImage>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
}

class FrameQueue;

class FFmpegWorker : public QObject
{
    Q_OBJECT

public:
    explicit FFmpegWorker(QObject* parent = nullptr);
    ~FFmpegWorker() override;

    void setUrl(const QString& url);
    void setTestMode(bool enabled);

    // ⭐ NEW: connect worker → FrameQueue
    void setFrameQueue(FrameQueue* queue);

public slots:
    void startDecoding();
    void stopDecoding();

signals:
    void openInputOk();
    void openInputFailed(const QString& reason);
    void streamStarted();
    void streamStopped();
    void streamError(const QString& reason);
    void finished();

private:
    void decodeLoop();

    QString m_url;
    bool m_abort = false;
    bool m_testMode = false;

    // ⭐ NEW: where decoded frames go
    FrameQueue* m_queue = nullptr;
};
