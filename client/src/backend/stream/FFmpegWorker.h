#pragma once

#include <QObject>
#include <QString>
#include <QImage>
#include <QSet>
#include <atomic>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

class FrameQueue;

class FFmpegWorker : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString resolution READ resolution NOTIFY statsChanged)
    Q_PROPERTY(double fps READ fps NOTIFY statsChanged)
    Q_PROPERTY(int bitrateKbps READ bitrateKbps NOTIFY statsChanged)
    Q_PROPERTY(QString codec READ codec NOTIFY statsChanged)

public:
    explicit FFmpegWorker(QObject* parent = nullptr);
    ~FFmpegWorker() override;

    void setUrl(const QString& url);
    void setTestMode(bool enabled);
    void setFrameQueue(FrameQueue* queue);
    void setHighQuality(bool enabled);

    QString resolution() const { return m_resolution; }
    double fps() const { return m_fps; }
    int bitrateKbps() const { return m_bitrateKbps; }
    QString codec() const { return m_codec; }

    AVPixelFormat hwPixFmt() const { return m_hwPixFmt; }
    bool isAbortRequested() const { return m_abort.load(); }

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
    void statsChanged();
    void statsUpdated(const QString& resolution, double fps,
                      int bitrateKbps, const QString& codec);

private:
    void decodeLoop();
    void updateStats(AVFormatContext* fmtCtx,
                     AVCodecContext* codecCtx,
                     AVStream* videoStream);

    bool initHwDevice(AVCodecContext* ctx);
    bool openCodec(AVCodecContext** codecCtx,
                   const AVCodec* codec,
                   AVCodecParameters* params,
                   bool tryHw);
    void clearHw();

    static int decodeInterruptCb(void* opaque);

    QString m_url;
    std::atomic_bool m_abort{false};
    bool m_testMode = false;
    bool m_highQuality = false;

    FrameQueue* m_queue = nullptr;

    QString m_resolution;
    double m_fps = 0.0;
    int m_bitrateKbps = 0;
    QString m_codec;

    AVBufferRef* m_hwDeviceCtx = nullptr;
    AVPixelFormat m_hwPixFmt = AV_PIX_FMT_NONE;
    bool m_usingHw = false;
};