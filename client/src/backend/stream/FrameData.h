#pragma once
#include <QImage>
#include <QString>

struct FrameData {
    QImage image;

    int width = 0;
    int height = 0;

    double fps = 0.0;
    int bitrate = 0;          // in bits/sec
    int gop = 0;              // keyframe interval
    double motion = 0.0;      // motion %
    int objects = 0;          // number of detected objects

    QString codec;            // "h264", "h265"
    QString streamType;       // "rtsp", "go2rtc", "frigate"
};
