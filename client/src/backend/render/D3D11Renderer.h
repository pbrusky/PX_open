#pragma once

#include <QSize>

#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>

extern "C" {
#include <libavutil/frame.h>
}

class FrameQueue;   // forward declaration

using Microsoft::WRL::ComPtr;

class D3D11Renderer
{
public:
    D3D11Renderer(FrameQueue* queue);
    ~D3D11Renderer();

    void render();
    void resize(int w, int h);

private:
    bool initD3D(const QSize& size);
    void uploadFrame(AVFrame* frame);
    void drawFrame();

private:
    FrameQueue* m_queue = nullptr;

    // D3D11 core
    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_context;

    // Render target
    ComPtr<ID3D11Texture2D> m_renderTarget;
    ComPtr<ID3D11RenderTargetView> m_rtv;

    // YUV420P textures
    ComPtr<ID3D11Texture2D> m_texY;
    ComPtr<ID3D11Texture2D> m_texU;
    ComPtr<ID3D11Texture2D> m_texV;

    ComPtr<ID3D11ShaderResourceView> m_srvY;
    ComPtr<ID3D11ShaderResourceView> m_srvU;
    ComPtr<ID3D11ShaderResourceView> m_srvV;

    // NV12 texture (hardware decode)
    ComPtr<ID3D11Texture2D> m_texUV;
    ComPtr<ID3D11ShaderResourceView> m_srvUV;

    // Sampler
    ComPtr<ID3D11SamplerState> m_sampler;

    // Shaders
    ComPtr<ID3D11VertexShader> m_vs;
    ComPtr<ID3D11PixelShader> m_ps;
    ComPtr<ID3D11InputLayout> m_inputLayout;

    // Geometry
    ComPtr<ID3D11Buffer> m_vertexBuffer;

    QSize m_size;
    bool m_initialized = false;
};
