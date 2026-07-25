#include "CameraVideoRenderer.h"
#include <QDebug>

CameraVideoRenderer::CameraVideoRenderer(FrameQueue* queue)
    : m_queue(queue),
      m_renderer(queue)
{
}

void CameraVideoRenderer::synchronize(QQuickFramebufferObject* item)
{
    m_width  = int(item->width());
    m_height = int(item->height());

    m_renderer.resize(m_width, m_height);
}

void CameraVideoRenderer::render()
{
    m_renderer.render();
    update();   // schedule next frame
}
