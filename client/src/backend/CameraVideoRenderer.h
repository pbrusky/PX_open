#pragma once

#include <QQuickFramebufferObject>
#include "D3D11Renderer.h"
#include "FrameQueue.h"

class CameraVideoRenderer : public QQuickFramebufferObject::Renderer
{
public:
    CameraVideoRenderer(FrameQueue* queue);

    void render() override;
    void synchronize(QQuickFramebufferObject* item) override;

private:
    FrameQueue* m_queue;
    D3D11Renderer m_renderer;
    int m_width = 0;
    int m_height = 0;
};
